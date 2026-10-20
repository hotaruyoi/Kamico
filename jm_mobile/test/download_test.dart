import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/domain/models.dart';

void main() {
  test(
    'failed chapter stays unpublished, retry resumes, offline pages survive new repository',
    () async {
      final root = await Directory.systemTemp.createTemp('jm_download_test_');
      addTearDown(() => root.delete(recursive: true));
      var fail = true;
      final fetched = <int>[];
      final repository = DownloadRepository(
        root: () async => root,
        fetchImage: (_, index) async {
          fetched.add(index);
          if (fail && index == 1) throw const HttpException('interrupted');
          return Uint8List.fromList(
            img.encodePng(img.Image(width: 4, height: 6)),
          );
        },
      );
      const comic = Comic(id: '../comic', title: 'Offline test');
      const chapter = Chapter(id: '../chapter', title: 'Chapter');
      const reader = ReaderChapter(
        id: '1',
        scrambleId: 0,
        pages: [
          ReaderPage(path: 'one', name: 'one'),
          ReaderPage(path: 'two', name: 'two'),
        ],
      );
      await expectLater(
        repository.save(comic, chapter, reader, (_, _) {}),
        throwsA(isA<HttpException>()),
      );
      expect(await repository.list(), isEmpty);
      fail = false;
      await repository.save(comic, chapter, reader, (_, _) {});
      expect(fetched, [0, 1, 1]);
      final offline = DownloadRepository(
        root: () async => root,
        fetchImage: (_, _) async => throw StateError('offline'),
      );
      final saved = (await offline.list()).single;
      expect(saved.count, 2);
      expect(img.decodeImage(await saved.page(1).readAsBytes())?.height, 6);
      expect(saved.folder.startsWith(root.path), true);
    },
  );
}
