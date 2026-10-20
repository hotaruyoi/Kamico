import 'package:image/image.dart' as img;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_queue.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';

ReaderChapter chapter(String id) => ReaderChapter(
  id: id,
  scrambleId: 0,
  pages: const [ReaderPage(path: 'one', name: 'one')],
);
void main() {
  test(
    'queue bounds concurrency, pauses at page checkpoints, persists and resumes',
    () async {
      SharedPreferences.setMockInitialValues({
        'download_concurrency': 2,
        'download_retries': 0,
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      final root = await Directory.systemTemp.createTemp('jm_queue_');
      addTearDown(() => root.delete(recursive: true));
      final started = Completer<void>(), release = Completer<void>();
      var count = 0;
      final repository = DownloadRepository(
        root: () async => root,
        fetchImage: (chapter, index) async {
          count++;
          if (count == 2) started.complete();
          await release.future;
          return Uint8List.fromList(
            img.encodePng(img.Image(width: 4, height: 6)),
          );
        },
      );
      final queue = DownloadQueue(
        store: store,
        repository: repository,
        loadChapter: (id) async => chapter(id),
      );
      const book = Comic(id: '1', title: 'One');
      await queue.enqueue(book, const [
        Chapter(id: '10', title: 'A'),
        Chapter(id: '11', title: 'B'),
        Chapter(id: '12', title: 'C'),
      ]);
      await started.future;
      expect(count, 2);
      queue.pause('1:10');
      release.complete();
      await queue.idle;
      expect(queue.jobs['1:10']!.state, 'paused');
      expect(queue.jobs['1:11']!.state, 'done');
      expect(queue.jobs['1:12']!.state, 'done');
      expect((await repository.list()).length, 2);
      queue.dispose();
      final restored = DownloadQueue(
        store: store,
        repository: repository,
        loadChapter: (id) async => chapter(id),
      );
      await restored.restore();
      expect(restored.jobs['1:10']!.state, 'paused');
      restored.resume('1:10');
      await restored.idle;
      expect((await repository.list()).length, 3);
      expect(restored.jobs['1:10']!.state, 'done');
      restored.dispose();
    },
  );
  test(
    'transient page failure retries finitely and process-interrupted tasks recover',
    () async {
      SharedPreferences.setMockInitialValues({'download_retries': 1});
      final store = LocalStore(await SharedPreferences.getInstance());
      final root = await Directory.systemTemp.createTemp('jm_retry_');
      addTearDown(() => root.delete(recursive: true));
      var attempts = 0;
      final repository = DownloadRepository(
        root: () async => root,
        fetchImage: (_, _) async {
          attempts++;
          if (attempts == 1) throw const HttpException('transient');
          return Uint8List.fromList(
            img.encodePng(img.Image(width: 4, height: 6)),
          );
        },
      );
      final job = DownloadJob(
        comic: const Comic(id: '1', title: 'One'),
        chapter: const Chapter(id: '10', title: 'A'),
        state: 'running',
      );
      await store.writeMap('download_jobs', {job.id: job.toJson()});
      final queue = DownloadQueue(
        store: store,
        repository: repository,
        loadChapter: (id) async => chapter(id),
      );
      await queue.restore();
      await queue.idle;
      expect(attempts, 2);
      expect(queue.jobs[job.id]!.state, 'done');
      expect(queue.jobs[job.id]!.attempts, 1);
      queue.dispose();
    },
  );
  test(
    'chapter deletion refuses a folder outside managed download root',
    () async {
      final root = await Directory.systemTemp.createTemp('jm_delete_');
      addTearDown(() => root.delete(recursive: true));
      final other = await Directory.systemTemp.createTemp('jm_other_');
      addTearDown(() => other.delete(recursive: true));
      final repository = DownloadRepository(
        root: () async => root,
        fetchImage: (_, _) async => Uint8List(0),
      );
      final offline = OfflineChapter(
        comic: const Comic(id: '1', title: 'One'),
        chapter: const Chapter(id: '10', title: 'A'),
        folder: other.path,
        count: 1,
      );
      await expectLater(
        repository.delete(offline),
        throwsA(isA<FileSystemException>()),
      );
      expect(await other.exists(), true);
    },
  );
}
