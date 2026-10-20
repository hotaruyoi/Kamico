import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';
import 'chapter_pdf.dart';

typedef PdfPublisher =
    Future<String?> Function(String path, String book, String chapter);

class OfflineChapter {
  const OfflineChapter({
    required this.comic,
    required this.chapter,
    required this.folder,
    required this.count,
    this.pdfUri,
  });
  final Comic comic;
  final Chapter chapter;
  final String folder;
  final int count;
  final String? pdfUri;
  File get pdf => File('$folder/chapter.pdf');
  File page(int index) => File('$folder/$index.img');
}

class DownloadRepository {
  DownloadRepository({
    required this.fetchImage,
    Future<Directory> Function()? root,
    this.publishPdf,
    this.publishSourcePdf,
  }) : _root = root ?? getApplicationSupportDirectory;
  final Future<Uint8List> Function(ReaderChapter, int) fetchImage;
  final Future<Directory> Function() _root;
  final PdfPublisher? publishPdf;
  final Future<String?> Function(String, String, String, ContentSource)?
  publishSourcePdf;
  Future<Directory> get directory => _directory();
  Future<int> get bytes async {
    var total = 0;
    await for (final entry in (await _directory()).list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is File) total += await entry.length();
    }
    return total;
  }

  Future<Directory> _directory() async {
    final root = await _root();
    return Directory('${root.path}/downloads').create(recursive: true);
  }

  Future<void> save(
    Comic comic,
    Chapter chapter,
    ReaderChapter reader,
    void Function(int, int) progress, {
    FutureOr<void> Function()? checkpoint,
  }) async {
    if (reader.pages.isEmpty) throw const FormatException('章节没有可下载的图片');
    final root = await _directory();
    final key = sha256
        .convert(utf8.encode('${comic.key}:${chapter.id}'))
        .toString();
    final folder = await Directory('${root.path}/$key').create(recursive: true);
    for (var index = 0; index < reader.pages.length; index++) {
      await checkpoint?.call();
      final target = File('${folder.path}/$index.img');
      if (!await target.exists()) {
        final original = await fetchImage(reader, index);
        await checkpoint?.call();
        final temporary = File('${target.path}.part');
        await temporary.writeAsBytes(original, flush: true);
        await temporary.rename(target.path);
      }
      progress(index + 1, reader.pages.length);
    }
    await checkpoint?.call();
    final pdf = File('${folder.path}/chapter.pdf');
    await writeChapterPdf(
      pdf,
      List.generate(reader.pages.length, (i) => File('${folder.path}/$i.img')),
      checkpoint: () async {
        await checkpoint?.call();
      },
    );
    await checkpoint?.call();
    final uri = publishSourcePdf != null
        ? await publishSourcePdf!(
            pdf.path,
            '${comic.title}_${comic.id}',
            '${chapter.title}_${chapter.exportId}',
            comic.source,
          )
        : await publishPdf?.call(
            pdf.path,
            '${comic.title}_${comic.id}',
            '${chapter.title}_${chapter.exportId}',
          );
    // Publish a chapter only after every page has reached disk.
    final manifest = File('${folder.path}/chapter.json.part');
    await manifest.writeAsString(
      jsonEncode({
        'comic': comic.toJson(),
        'id': chapter.id,
        'title': chapter.title,
        'count': reader.pages.length,
        'pdfUri': uri,
      }),
      flush: true,
    );
    final published = File('${folder.path}/chapter.json');
    if (await published.exists()) await published.delete();
    await manifest.rename(published.path);
  }

  Future<void> delete(OfflineChapter chapter) async {
    final root = await _directory();
    final target = Directory(chapter.folder);
    final parent = await target.parent.resolveSymbolicLinks();
    if (parent != await root.resolveSymbolicLinks()) {
      throw const FileSystemException('拒绝删除书库目录之外的文件');
    }
    if (await target.exists()) await target.delete(recursive: true);
  }

  Future<File> ensurePdf(OfflineChapter chapter) async {
    final root = await _directory();
    if (await Directory(chapter.folder).parent.resolveSymbolicLinks() !=
        await root.resolveSymbolicLinks()) {
      throw const FileSystemException('离线章节不属于本地书库');
    }
    if (!await chapter.pdf.exists()) {
      await writeChapterPdf(
        chapter.pdf,
        List.generate(chapter.count, chapter.page),
      );
    }
    return chapter.pdf;
  }

  Future<List<OfflineChapter>> registerImports(List<Json> entries) async {
    final root = await _directory();
    final rootPath = await root.resolveSymbolicLinks();
    for (final item in entries) {
      final folder = Directory('${item['folder']}');
      if (await folder.parent.resolveSymbolicLinks() != rootPath) {
        throw const FileSystemException('导入目录不属于本地书库');
      }
      final pdf = File('${folder.path}/chapter.pdf');
      await writeChapterPdf(
        pdf,
        List.generate(
          integer(item['count']),
          (i) => File('${folder.path}/$i.img'),
        ),
      );
      final comic = Comic.fromJson(item['comic'] as Json);
      item['pdfUri'] = publishSourcePdf != null
          ? await publishSourcePdf!(
              pdf.path,
              '${comic.title}_${comic.id}',
              '${item['title']}_${Chapter(id: '${item['id']}', title: '').exportId}',
              comic.source,
            )
          : await publishPdf?.call(
              pdf.path,
              '${comic.title}_${comic.id}',
              '${item['title']}_${Chapter(id: '${item['id']}', title: '').exportId}',
            );
      await File(
        '${folder.path}/chapter.json',
      ).writeAsString(jsonEncode(item), flush: true);
    }
    return list();
  }

  Future<List<OfflineChapter>> list() async {
    final root = await _directory();
    final chapters = <OfflineChapter>[];
    await for (final folder in root.list()) {
      if (folder is! Directory) continue;
      final manifest = File('${folder.path}/chapter.json');
      if (!await manifest.exists()) continue;
      try {
        final data = jsonDecode(await manifest.readAsString()) as Json;
        final count = integer(data['count']);
        if (count <= 0) continue;
        var complete = true;
        for (var index = 0; index < count; index++) {
          if (!await File('${folder.path}/$index.img').exists()) {
            complete = false;
            break;
          }
        }
        if (!complete) continue;
        chapters.add(
          OfflineChapter(
            comic: Comic.fromJson(data['comic'] as Json),
            chapter: Chapter(id: '${data['id']}', title: '${data['title']}'),
            folder: folder.path,
            count: integer(data['count']),
            pdfUri: data['pdfUri'] as String?,
          ),
        );
      } on FormatException {
        continue;
      }
    }
    chapters.sort((a, b) => a.comic.title.compareTo(b.comic.title));
    return chapters;
  }
}
