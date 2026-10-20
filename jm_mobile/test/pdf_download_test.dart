import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/chapter_pdf.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/download_queue.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/platform_files.dart';
import 'package:jm_mobile/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'PDF publication fails without publishing offline manifest, retries from cached images and uses page order',
    () async {
      final root = await Directory.systemTemp.createTemp('kamico_pdf_');
      addTearDown(() => root.delete(recursive: true));
      var fetches = 0, publications = 0;
      final repo = DownloadRepository(
        root: () async => root,
        fetchImage: (_, i) async {
          fetches++;
          final picture = img.Image(width: 120, height: i == 0 ? 240 : 360);
          img.fill(
            picture,
            color: i == 0
                ? img.ColorRgb8(233, 91, 145)
                : img.ColorRgb8(70, 120, 200),
          );
          return Uint8List.fromList(img.encodePng(picture));
        },
        publishPdf: (path, book, chapter) async {
          publications++;
          expect(await File(path).exists(), true);
          expect(book, 'Sample_1');
          expect(chapter, 'First_2');
          if (publications == 1) throw const FileSystemException('disk full');
          return 'content://media/external/downloads/123';
        },
      );
      const comic = Comic(id: '1', title: 'Sample');
      const chapter = Chapter(id: '2', title: 'First');
      const reader = ReaderChapter(
        id: '2',
        scrambleId: 0,
        pages: [
          ReaderPage(path: '', name: '0'),
          ReaderPage(path: '', name: '1'),
        ],
      );
      await expectLater(
        repo.save(comic, chapter, reader, (_, _) {}),
        throwsA(isA<FileSystemException>()),
      );
      expect(await repo.list(), isEmpty);
      await repo.save(comic, chapter, reader, (_, _) {});
      expect(fetches, 2);
      expect(publications, 2);
      final saved = (await repo.list()).single;
      expect(saved.pdfUri, 'content://media/external/downloads/123');
      final pdf = String.fromCharCodes(await saved.pdf.readAsBytes());
      expect(pdf.startsWith('%PDF-1.4'), true);
      expect(pdf, contains('/PageLayout /OneColumn'));
      expect(pdf, contains('/Count 2'));
      expect(
        pdf.indexOf('/MediaBox [0 0 720 1440.0000]'),
        lessThan(pdf.indexOf('/MediaBox [0 0 720 2160.0000]')),
      );
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await Directory('docs/previews/0.16.0').create(recursive: true);
        await saved.pdf.copy('docs/previews/0.16.0/sample-chapter.pdf');
      }
      await repo.delete(saved);
      expect(await repo.list(), isEmpty);
      expect(
        publications,
        2,
        reason: 'Removing private cache does not delete the public PDF',
      );
    },
  );

  test(
    'corrupt image cannot replace an existing PDF with a partial file',
    () async {
      final root = await Directory.systemTemp.createTemp('kamico_pdf_bad_');
      addTearDown(() => root.delete(recursive: true));
      final target = File('${root.path}/chapter.pdf')
        ..writeAsStringSync('previous completed PDF');
      final bad = File('${root.path}/bad.img')..writeAsBytesSync([1, 2, 3]);
      await expectLater(
        writeChapterPdf(target, [bad]),
        throwsA(isA<FormatException>()),
      );
      expect(await target.readAsString(), 'previous completed PDF');
      expect(await File('${target.path}.part').exists(), false);
    },
  );

  test(
    'denied storage permission fails once and preserves resumable image cache',
    () async {
      SharedPreferences.setMockInitialValues({'download_retries': 5});
      final store = LocalStore(await SharedPreferences.getInstance());
      final root = await Directory.systemTemp.createTemp(
        'kamico_pdf_permission_',
      );
      addTearDown(() => root.delete(recursive: true));
      var permissionRequests = 0;
      final repo = DownloadRepository(
        root: () async => root,
        fetchImage: (_, _) async =>
            Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 3))),
        publishPdf: (_, _, _) async {
          permissionRequests++;
          throw PlatformException(code: 'permission_denied');
        },
      );
      final queue = DownloadQueue(
        store: store,
        repository: repo,
        loadChapter: (id) async => ReaderChapter(
          id: id,
          scrambleId: 0,
          pages: const [ReaderPage(path: '', name: '0')],
        ),
      );
      await queue.enqueue(const Comic(id: '1', title: 'Book'), [
        const Chapter(id: '2', title: 'One'),
      ]);
      await queue.idle;
      expect(permissionRequests, 1);
      expect(queue.jobs['1:2']!.state, 'failed');
      expect(await repo.list(), isEmpty);
      queue.dispose();
    },
  );

  test(
    'platform PDF bridge passes paths, names and optional directory without image-format options',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformFiles.channel, (call) async {
            calls.add(call);
            return 'content://pdf';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(PlatformFiles.channel, null),
      );
      await PlatformFiles.publishPdf(
        '/private/chapter.pdf',
        'Book_1',
        'Chapter_2',
      );
      expect(calls.single.arguments, {
        'path': '/private/chapter.pdf',
        'book': 'Book_1',
        'chapter': 'Chapter_2',
        'source': 'JM',
      });
      expect(calls.single.method, 'publishPdf');
      await PlatformFiles.publishPdf(
        '/private/pic.pdf',
        'Book',
        'Chapter',
        source: 'PIC',
        tree: 'content://selected',
      );
      expect(calls.last.arguments, {
        'path': '/private/pic.pdf',
        'book': 'Book',
        'chapter': 'Chapter',
        'source': 'PIC',
        'tree': 'content://selected',
      });
    },
  );
}
