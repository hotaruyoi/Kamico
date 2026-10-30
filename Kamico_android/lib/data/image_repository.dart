import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';
import 'jm_protocol.dart';
import 'jm_client.dart';
import 'comic_source.dart';
import 'image_size.dart';

class ImageRepository {
  ImageRepository(
    this.api, {
    http.Client? transport,
    Future<Directory> Function()? temporaryDirectory,
  }) : _http = transport ?? http.Client(),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;
  final ComicSource api;
  final http.Client _http;
  final Future<Directory> Function() _temporaryDirectory;
  final _pending = <String, Future<Uint8List>>{};
  final _aspects = <String, double>{};
  /// Bumped whenever a page's height/width ratio becomes known, so the reader
  /// can reserve the page extent before its bitmap decodes.
  final aspectRevision = ValueNotifier<int>(0);
  int _active = 0;
  Future<void> _maintenance = Future.value();
  final _waiting = <Completer<void>>[];

  String _aspectKey(ReaderChapter chapter, int index) =>
      '${chapter.source.id}:${chapter.id}:$index';

  double? aspectFor(ReaderChapter chapter, int index) =>
      _aspects[_aspectKey(chapter, index)];

  /// Average height/width ratio of the pages already seen in this chapter.
  /// Unknown pages use it as a placeholder that is close to their real extent.
  double averageAspect(ReaderChapter chapter) {
    final prefix = '${chapter.source.id}:${chapter.id}:';
    var total = 0.0, count = 0;
    for (final entry in _aspects.entries) {
      if (entry.key.startsWith(prefix)) {
        total += entry.value;
        count++;
      }
    }
    return count == 0 ? 1.45 : (total / count).clamp(0.4, 4.0);
  }

  void _rememberAspect(ReaderChapter chapter, int index, Uint8List bytes) {
    final aspect = imageAspectFromBytes(bytes);
    if (aspect == null || aspect <= 0) return;
    final key = _aspectKey(chapter, index);
    final previous = _aspects[key];
    if (previous != null && (previous - aspect).abs() < .001) return;
    _aspects[key] = aspect;
    aspectRevision.value++;
  }
  Future<void> _acquire() async {
    if (_active < 3) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  void prefetch(ReaderChapter chapter, int index, {int radius = 2}) {
    for (var delta = 1; delta <= radius; delta++) {
      for (final next in [index + delta, index - delta]) {
        if (next >= 0 && next < chapter.pages.length) {
          unawaited(
            load(chapter, next).then<void>((_) {}).catchError((Object _) {}),
          );
        }
      }
    }
  }

  Future<Uint8List> load(ReaderChapter chapter, int index) {
    final page = chapter.pages[index];
    final host = api.config.imageHost;
    final key = md5
        .convert(
          utf8.encode(
            '${chapter.source == ContentSource.pic ? 'pic:' : ''}$host:${chapter.id}:${chapter.scrambleId}:${page.path}',
          ),
        )
        .toString();
    return _pending.putIfAbsent(key, () async {
      await _acquire();
      try {
        final root = await _temporaryDirectory();
        final cache = Directory('${root.path}/reader_cache');
        await cache.create(recursive: true);
        final file = File('${cache.path}/$key.png');
        if (await file.exists()) {
          await file.setLastModified(DateTime.now());
          final cached = await file.readAsBytes();
          _rememberAspect(chapter, index, cached);
          return cached;
        }
        final response = await _http
            .get(
              chapter.source == ContentSource.pic
                  ? Uri.parse(page.path)
                  : Uri.parse(host).resolve(page.path),
              headers: chapter.source == ContentSource.pic
                  ? const {}
                  : {
                      'Referer': api.config.apiHosts.first,
                      'X-Requested-With': 'com.JMComic3.app',
                    },
            )
            .timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) {
          throw const ApiException('图片加载失败，可点击重试或切换图片线路');
        }
        final result = chapter.source == ContentSource.pic
            ? response.bodyBytes
            : await compute(restoreImage, (
                response.bodyBytes,
                JmProtocol.segmentCount(
                  int.parse(chapter.id),
                  chapter.scrambleId,
                  page.name,
                ),
              ));
        await file.writeAsBytes(result, flush: true);
        _rememberAspect(chapter, index, result);
        _maintenance = _maintenance
            .then((_) => _trim(cache))
            .catchError((Object _) {});
        await _maintenance;
        return result;
      } finally {
        _release();
        _pending.remove(key);
      }
    });
  }

  Future<void> _trim(Directory cache) async {
    final files = <(File, FileStat)>[];
    var bytes = 0;
    await for (final entry in cache.list()) {
      if (entry is File) {
        final stat = await entry.stat();
        bytes += stat.size;
        files.add((entry, stat));
      }
    }
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (bytes <= 256 * 1024 * 1024) break;
      if (await file.exists()) await file.delete();
      bytes -= stat.size;
    }
  }

  Future<void> clearCache() async {
    final root = await _temporaryDirectory();
    final cache = Directory('${root.path}/reader_cache');
    if (await cache.exists()) await cache.delete(recursive: true);
  }

  void close() => _http.close();
}
