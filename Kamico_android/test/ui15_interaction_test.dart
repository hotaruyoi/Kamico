import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_queue.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/platform_files.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/bookcase.dart';
import 'package:jm_mobile/ui/chapter_download_sheet.dart';
import 'package:jm_mobile/ui/comments_body.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/ui/downloads.dart';
import 'package:jm_mobile/ui/library_layout.dart';
import 'package:jm_mobile/ui/design_system.dart';
import 'discovery_test.dart' show apiFor;

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('jm_ui15_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PlatformFiles.channel,
          (call) async =>
              call.method == 'storageInfo' ? {'available': 1073741824} : null,
        );
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await root.delete(recursive: true);
  });
  Future<void> io(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), true, reason: 'Asynchronous local storage should finish');
    await tester.pumpAndSettle();
  }

  Json detail(int count) => {
    'id': '1',
    'name': 'Demo',
    'description': 'About this comic',
    'series': [
      for (var i = 0; i < count; i++) {'id': '$i', 'name': 'Chapter $i'},
    ],
  };

  testWidgets(
    'detail comments are lazy, swipeable, kept alive and stay on the current route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var comments = 0;
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((r) {
          if (r.url.path == '/album/') return detail(200);
          if (r.url.path == '/forum/') {
            comments++;
            return {
              'total': 1,
              'list': [
                {'CID': '1', 'username': 'Reader', 'content': 'Hello'},
              ],
            };
          }
          throw StateError('Unexpected request ${r.url.path}');
        }),
      );
      final routes = _Routes();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: DetailScreen(
            session: session,
            comic: const Comic(id: '1', title: 'Demo'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(comments, 0);
      expect(find.text('Chapter 199'), findsNothing);
      expect(find.byTooltip('下载章节'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.widgetWithText(Tab, '评论'));
      await tester.pumpAndSettle();
      expect(comments, 1);
      expect(routes.pushes, 1);
      expect(find.text('Hello'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, '详情'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(TabBarView), const Offset(-380, 0));
      await tester.pumpAndSettle();
      expect(comments, 1);
      await tester.drag(find.byType(TabBarView), const Offset(-380, 0));
      await tester.pumpAndSettle();
      expect(comments, 1);
      expect(find.text('Hello'), findsOneWidget);
      expect(routes.pushes, 1);
      await tester.tap(find.widgetWithText(Tab, '详情'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, '开始阅读').hitTestable(),
        findsNothing,
      );
      expect(find.byType(TabBar).hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(TabBar)).dy,
        closeTo(tester.getBottomLeft(find.byType(AppBar)).dy, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'comments append pages, retain existing content on failure and retry the same page',
    (tester) async {
      var attempts = 0;
      final pages = <int>[];
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((r) {
          final page = int.parse(r.url.queryParameters['page']!);
          pages.add(page);
          if (page == 2 && attempts++ == 0) throw const ApiException('模拟下一页失败');
          return {
            'total': 4,
            'list': [
              for (var i = (page - 1) * 2; i < page * 2; i++)
                {'CID': '$i', 'content': 'Comment $i'},
            ],
          };
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentsBody(session: session, id: '1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('加载更多评论'));
      await tester.pumpAndSettle();
      expect(find.text('Comment 0'), findsOneWidget);
      expect(find.text('Comment 1'), findsOneWidget);
      await tester.ensureVisible(find.text('重试'));
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(pages, [1, 2, 2]);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Comment 3'), findsOneWidget);
      expect(find.text('已显示全部评论'), findsOneWidget);
      expect(find.text('加载更多评论'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  for (final downloads in [false, true]) {
    testWidgets(
      '${downloads ? 'download' : 'bookcase'} controls scroll away and rows stay lazy',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = LocalStore(await SharedPreferences.getInstance());
        final session = AppSession(
          store,
          client: apiFor((_) => throw StateError('No network needed')),
        );
        for (var i = 0; i < 80; i++) {
          final comic = Comic(
            id: '$i',
            title: 'Book $i',
            authors: const ['Author'],
          );
          if (downloads) {
            final job = DownloadJob(
              comic: comic,
              chapter: Chapter(id: '$i', title: 'Chapter'),
              state: 'paused',
            );
            session.queue.jobs[job.id] = job;
          } else {
            await store.addLocal(comic);
          }
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Library')),
              body: downloads
                  ? DownloadScreen(session: session)
                  : BookcaseScreen(session: session),
              bottomNavigationBar: const SizedBox(height: 80),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SearchBar).hitTestable(), findsOneWidget);
        expect(find.text('Book 79'), findsNothing);
        expect(find.byType(LibraryBookTile).evaluate().length, lessThan(20));
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(find.byType(SearchBar).hitTestable(), findsNothing);
        expect(find.byType(LibraryBookTile).evaluate().length, lessThan(20));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await session.queue.idle;
        session.dispose();
      },
    );
  }

  testWidgets(
    'management and detail remain scrollable in a narrow window with large system text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = LocalStore(await SharedPreferences.getInstance());
      for (var i = 0; i < 4; i++) {
        await store.addLocal(Comic(id: '$i', title: '长标题漫画示例 $i'));
      }
      final session = AppSession(store, client: apiFor((_) => detail(20)));
      for (final page in [
        BookcaseScreen(session: session),
        DownloadScreen(session: session),
        DetailScreen(
          session: session,
          comic: const Comic(id: '1', title: 'Demo'),
        ),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme(Colors.teal, Brightness.light, 'sans-serif'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: page),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.runtimeType} after scrolling',
        );
      }
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'one download entry defaults to missing chapters; cancel does not enqueue and confirmation respects selection',
    (tester) async {
      final store = LocalStore(await SharedPreferences.getInstance());
      var chapterRequests = 0;
      final session = AppSession(
        store,
        client: apiFor((r) {
          if (r.url.path == '/album/') return detail(6);
          if (r.url.path == '/comic_read/') {
            chapterRequests++;
            return {
              'id': r.url.queryParameters['id'],
              'scramble_id': 0,
              'images': [],
            };
          }
          throw StateError('Unexpected request');
        }),
      );
      final repo = DownloadRepository(
        root: () async => root,
        fetchImage: (_, _) async =>
            Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 6))),
      );
      const comic = Comic(id: '1', title: 'Demo');
      await tester.runAsync(
        () => repo.save(
          comic,
          const Chapter(id: '0', title: 'Chapter 0'),
          const ReaderChapter(
            id: '0',
            scrambleId: 0,
            pages: [ReaderPage(path: '', name: '0')],
          ),
          (_, _) {},
        ),
      );
      final queued = DownloadJob(
        comic: comic,
        chapter: const Chapter(id: '1', title: 'Chapter 1'),
      );
      session.queue.jobs[queued.id] = queued;
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(session: session, comic: comic),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下载'));
      await tester.pump();
      await io(tester, () => find.text('加入下载队列 (4)').evaluate().isNotEmpty);
      expect(find.byType(ChapterDownloadSheet), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(chapterRequests, 0);
      expect(session.queue.jobs.keys, ['1:1']);
      await tester.tap(find.byTooltip('下载'));
      await tester.pump();
      await io(tester, () => find.text('加入下载队列 (4)').evaluate().isNotEmpty);
      await tester.tap(find.text('清空选择'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(CheckboxListTile, 'Chapter 3'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ChapterDownloadSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Chapter 3'));
      await tester.pump();
      await tester.tap(find.text('加入下载队列 (1)'));
      await io(tester, () => session.queue.jobs.containsKey('1:3'));
      expect(session.queue.jobs.keys.toSet(), {'1:1', '1:3'});
      await session.queue.idle;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
