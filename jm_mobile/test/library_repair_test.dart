import 'package:image/image.dart' as img;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_queue.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/bookcase.dart';
import 'package:jm_mobile/ui/library_layout.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  test(
    'enqueue feedback reflects queued, resumed and on-disk chapters even without job records',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('jm_feedback_');
      addTearDown(() => root.delete(recursive: true));
      final store = LocalStore(await SharedPreferences.getInstance());
      final ready = Completer<ReaderChapter>();
      final repo = DownloadRepository(
        root: () async => root,
        fetchImage: (_, _) async =>
            Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 6))),
      );
      final queue = DownloadQueue(
        store: store,
        repository: repo,
        loadChapter: (_) => ready.future,
      );
      const comic = Comic(id: '1', title: 'One'),
          chapter = Chapter(id: '2', title: 'Two');
      expect((await queue.enqueue(comic, [chapter])).added, 1);
      expect((await queue.enqueue(comic, [chapter])).existing, 1);
      queue.pause('1:2');
      expect((await queue.enqueue(comic, [chapter])).resumed, 1);
      ready.complete(
        const ReaderChapter(
          id: '2',
          scrambleId: 0,
          pages: [ReaderPage(path: 'a', name: 'a')],
        ),
      );
      await queue.idle;
      queue.remove('1:2');
      expect((await queue.enqueue(comic, [chapter])).completed, 1);
      expect(queue.jobs, isEmpty);
      expect(await repo.bytes, greaterThan(0));
      queue.dispose();
    },
  );
  test(
    'per-chapter reading positions survive switching chapters while recent history remains one book',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      const comic = Comic(id: '1', title: 'One');
      await store.saveProgress(
        const ReadingProgress(
          comic: comic,
          chapterId: '1',
          page: 8,
          fraction: .6,
        ),
      );
      await store.saveProgress(
        const ReadingProgress(comic: comic, chapterId: '2', page: 1),
      );
      expect(store.history.single.chapterId, '2');
      expect(store.chapterProgress('1', '1')!.fraction, .6);
    },
  );
  testWidgets(
    'bookcase defaults to device bookmarks and changing filter clears selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      await store.addLocal(const Comic(id: '1', title: 'Alpha'));
      await store.addLocal(const Comic(id: '2', title: 'Beta'));
      final session = AppSession(
        store,
        client: apiFor((_) => throw StateError('cloud should not load')),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BookcaseScreen(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('已选 1'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(TextField),
        ),
        'Beta',
      );
      await tester.pump();
      expect(find.text('已选 1'), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(LibraryBookTile),
          matching: find.text('Beta'),
        ),
        findsOneWidget,
      );
      expect(store.localFavorites.length, 2);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
