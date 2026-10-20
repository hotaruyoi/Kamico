import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/download_queue.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/ui/discovery.dart';
import 'package:jm_mobile/ui/settings.dart';
import 'discovery_test.dart' show apiFor;

const comic = Comic(id: '1', title: 'Navigation fixture');
const detail = {
  'id': '1',
  'name': 'Navigation fixture',
  'series': [
    {'id': '10', 'name': 'Chapter ten'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('kamico_ui18_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await root.delete(recursive: true);
    });
  });

  testWidgets(
    'discovery hides its header when scrolling down, restores it in reverse and keeps recommendations cached',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loads = 0;
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) {
          loads++;
          return [
            for (var i = 0; i < 10; i++)
              {
                'title': 'Section $i',
                'type': 'promote',
                'content': [
                  {'id': '$i', 'name': 'Comic $i'},
                ],
              },
          ];
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DiscoveryScreen(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar).hitTestable(), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar).hitTestable(), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar).hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const PageStorageKey('discovery-shortcuts:jm')),
        const Offset(-260, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('周刊推荐'), findsOneWidget);
      expect(find.byType(SearchBar).hitTestable(), findsOneWidget);
      expect(loads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'discovery content follows a held drag without extra motion from header collapse',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor(
          (_) => [
            for (var i = 0; i < 10; i++)
              {
                'title': 'Section $i',
                'type': 'promote',
                'content': [
                  {'id': '$i', 'name': 'Comic $i'},
                ],
              },
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DiscoveryScreen(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      final anchor = find.text('Section 0');
      final before = tester.getTopLeft(anchor).dy;
      final viewport = find.byType(CustomScrollView);
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
      );
      final heightBefore = tester.getSize(viewport).height;
      final gesture = await tester.startGesture(const Offset(195, 500));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
      final duringDrag = tester.getTopLeft(anchor).dy;
      await tester.pump(const Duration(milliseconds: 200));
      final whileHeld = tester.getTopLeft(anchor).dy;
      final offsetWhileHeld = scroll.position.pixels;
      final heightWhileHeld = tester.getSize(viewport).height;
      await gesture.up();
      await tester.pumpAndSettle();
      final reverse = await tester.startGesture(const Offset(195, 500));
      await reverse.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
      final reverseDrag = tester.getTopLeft(anchor).dy;
      await tester.pump(const Duration(milliseconds: 200));
      final reverseHeld = tester.getTopLeft(anchor).dy;
      await reverse.up();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      expect(
        whileHeld - duringDrag,
        closeTo(0, 1),
        reason:
            'Holding a stationary finger must not move content: before=$before, after drag=$duringDrag, while held=$whileHeld; scroll offset=$offsetWhileHeld; viewport=$heightBefore->$heightWhileHeld',
      );
      expect(duringDrag - before, closeTo(-40, 1));
      expect(heightWhileHeld, heightBefore);
      expect(reverseHeld - reverseDrag, closeTo(0, 1));
    },
  );

  testWidgets(
    'favorite destination defaults to cloud when signed in and switching never writes',
    (tester) async {
      var writes = 0;
      final api = apiFor((request) {
        if (request.url.path == '/favorite/') {
          writes++;
          return {'status': 'ok'};
        }
        return detail;
      })..token = 'fixture';
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: api,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(session: session, comic: comic),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('detail-primary-actions'));
      final actions = find.descendant(
        of: row,
        matching: find.byType(FilledButton),
      );
      expect(actions, findsOneWidget);
      final download = find.byKey(const ValueKey('detail-download'));
      final favorite = find.byKey(const ValueKey('detail-favorite'));
      expect(
        tester.getSize(download).width,
        closeTo(tester.getSize(row).width * .15, .1),
      );
      expect(tester.getSize(favorite).width, tester.getSize(download).width);
      expect(find.descendant(of: row, matching: find.text('下载')), findsNothing);
      expect(
        tester.getRect(favorite).right,
        lessThan(tester.getRect(row).right),
      );
      await tester.tap(favorite);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );
      await tester.tap(find.text('本地收藏'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('加入收藏'));
      await tester.pumpAndSettle();
      expect(session.store.localFavorites.containsKey('1'), isTrue);
      expect(writes, 0);
      await tester.tap(favorite);
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入收藏'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'detail caches reentry and uses large artwork and downloaded badges in both chapter layouts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      final store = LocalStore(await SharedPreferences.getInstance());
      final session = AppSession(
        store,
        client: apiFor((_) {
          requests++;
          return {
            'id': '1',
            'name': 'Artwork fixture',
            'series': [
              {'id': '10', 'name': 'Chapter one'},
              {'id': '20', 'name': 'Chapter two'},
            ],
          };
        }),
      );
      session.queue.jobs['1:20'] = DownloadJob(
        comic: comic,
        chapter: const Chapter(id: '20', title: 'Chapter two'),
        state: 'done',
      );
      await store.saveProgress(
        const ReadingProgress(comic: comic, chapterId: '10', page: 2),
      );
      Widget screen() => MaterialApp(
        home: DetailScreen(session: session, comic: comic),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('detail-cover-metadata'));
      final cover = find.descendant(
        of: header,
        matching: find.byType(ClipRRect),
      );
      expect(tester.getSize(cover).width, greaterThan(140));
      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(
        find.byKey(const ValueKey('detail-shared-backdrop')),
        findsOneWidget,
      );
      final backdrop = find.byKey(const ValueKey('detail-shared-backdrop'));
      final artwork = tester.widget<RawImage>(
        find.descendant(of: backdrop, matching: find.byType(RawImage)),
      );
      expect(artwork.fit, BoxFit.fitWidth);
      expect(artwork.alignment, Alignment.topCenter);
      expect(
        find.descendant(of: backdrop, matching: find.byType(Transform)),
        findsNothing,
      );
      expect(
        find.descendant(of: header, matching: find.text('2 章')),
        findsNothing,
      );
      expect(find.text('从头阅读'), findsNothing);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -450));
      await tester.pumpAndSettle();
      final badge = find.byKey(const ValueKey('downloaded-chapter:20'));
      expect(badge, findsOneWidget);
      expect(find.textContaining('未下载'), findsNothing);
      expect(find.byKey(const ValueKey('downloaded-chapter:10')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await store.preferences.setString('chapter_layout', 'compact');
      await tester.pumpWidget(screen());
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compact-chapter:20')), findsOneWidget);
      expect(badge, findsOneWidget);
      expect(requests, 1);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'detail resume label uses the saved chapter number, falls back to order and fits narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = LocalStore(await SharedPreferences.getInstance());
      final session = AppSession(
        store,
        client: apiFor(
          (_) => {
            'id': '1',
            'name': 'Resume fixture',
            'series': [
              {'id': '10', 'name': 'Opening'},
              {'id': '20', 'name': '第42话 · A long chapter title'},
              {'id': '30', 'name': 'Special chapter'},
            ],
          },
        ),
      );
      for (final entry in {
        '20': '继续 第42话',
        '30': '继续 第3话',
        'missing': '开始阅读',
      }.entries) {
        await store.saveProgress(
          ReadingProgress(comic: comic, chapterId: entry.key, page: 1),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: DetailScreen(session: session, comic: comic),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('detail-download'))).width,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'continue reading returns to its own detail and system back does not reopen reader',
    (tester) async {
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor(
          (request) => request.url.path == '/album/'
              ? detail
              : {'id': '10', 'images': [], 'scramble_id': 0},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openProgress(
                  context,
                  session,
                  const ReadingProgress(comic: comic, chapterId: '10', page: 0),
                ),
                child: const Text('resume'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('resume'));
      for (
        var i = 0;
        i < 30 && find.byType(ReaderScreen).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).chapter.title,
        'Chapter ten',
      );
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsOneWidget);
      expect(find.byType(ReaderScreen), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('resume'), findsOneWidget);
      await tester.tap(find.text('resume'));
      for (
        var i = 0;
        i < 30 && find.byType(ReaderScreen).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsOneWidget);
      expect(find.byType(ReaderScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'reader home exits the resume route and selects discovery instead of the originating tab',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor(
          (request) => request.url.path == '/promote/'
              ? []
              : {'id': '10', 'images': [], 'scramble_id': 0},
        ),
      );
      await tester.pumpWidget(JmApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4,
      );
      JmApp.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            session: session,
            comic: comic,
            chapter: const Chapter(id: '10', title: 'Ten'),
            chapters: const [],
            returnToComic: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回首页'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'long account identity and four matching shortcuts fit narrow large-text layout',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = apiFor((_) => {})
        ..token = 'fixture'
        ..userProfile = {
          'uid': '42',
          'username': 'A very long account identifier for layout testing',
        };
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: api,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(body: SettingsScreen(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已登录'), findsNothing);
      expect(
        find.text('A very long account identifier for layout testing'),
        findsOneWidget,
      );
      final shortcuts = find.descendant(
        of: find.byKey(const ValueKey('account-shortcuts')),
        matching: find.byType(FilledButton),
      );
      expect(shortcuts, findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
