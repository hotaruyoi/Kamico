import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/domain/reader_options.dart';
import 'package:jm_mobile/domain/discovery_shortcut.dart';
import 'package:jm_mobile/data/app_licenses.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/bookcase.dart';
import 'package:jm_mobile/ui/design_system.dart';
import 'package:jm_mobile/ui/library_layout.dart';
import 'package:jm_mobile/ui/reader.dart';
import 'package:jm_mobile/ui/discovery.dart';
import 'package:jm_mobile/ui/discovery_shortcut_order.dart';
import 'package:jm_mobile/ui/app_licenses.dart';
import 'package:jm_mobile/ui/preferences.dart';
import 'multi_source_test.dart' show FixtureJm, FixturePic;
import 'discovery_test.dart' show apiFor;
import 'ui_design_test.dart' show capture, captureUi;

Future<AppSession> releaseSession() async => AppSession(
  LocalStore(await SharedPreferences.getInstance()),
  client: FixtureJm(),
  picClient: FixturePic(),
);

Widget releaseHost(Widget child, {GlobalKey? key, double scale = 1}) =>
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppDesign.theme(
          const Color(0xff607db8),
          Brightness.dark,
          captureUi ? 'Review CJK' : null,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUpAll(() async {
    // Share completed asset futures across widget tests, outside their fake async zones.
    await Future.wait(
      [
        'LICENSE',
        'third_party/jmcomic.LICENSE',
        'third_party/GPL-3.0.txt',
      ].map(rootBundle.loadString),
    );
    if (!captureUi) return;
    for (final entry in {
      'Review CJK': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          'D:/Application/Flutter/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'license page shows relevant components and keeps the original notice readable',
    (tester) async {
      LicenseRegistry.reset();
      final notices = (await tester.runAsync(
        () => applicationLicenses().toList(),
      ))!;
      LicenseRegistry.addLicense(() => Stream.fromIterable(notices));
      LicenseRegistry.addLicense(
        () => Stream.value(
          LicenseEntryWithLineBreaks([
            'flutter_test',
            'test_api',
          ], 'Synthetic unused notice'),
        ),
      );
      await tester.pumpWidget(releaseHost(const AppLicensesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('flutter_test'), findsNothing);
      expect(find.text('test_api'), findsNothing);
      await tester.tap(find.text('kamico'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              (w.data?.contains('GNU LESSER GENERAL PUBLIC LICENSE') ?? false),
        ),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'appearance reorder applies to the existing discovery screen on return',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await releaseSession();
      addTearDown(app.dispose);
      await tester.pumpWidget(JmApp(session: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观与语言'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('发现页入口排序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发现页入口排序'));
      await tester.pumpAndSettle();
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(2, 0);
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(DiscoveryShortcutOrderScreen)),
      ).pop();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(AppearanceScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('发现').last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('shortcut-latest'))).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('shortcut-category'))).dx,
        ),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'shortcut IDs survive old/malformed preferences and filter source capabilities',
    () {
      expect(discoveryShortcutOrder(null), DiscoveryShortcut.values);
      final order = discoveryShortcutOrder([
        'weekly',
        'unknown',
        'latest',
        'weekly',
      ]);
      expect(order, [
        DiscoveryShortcut.weekly,
        DiscoveryShortcut.latest,
        DiscoveryShortcut.category,
        DiscoveryShortcut.ranking,
        DiscoveryShortcut.serial,
      ]);
      expect(order.where((item) => item.supports(ContentSource.pic)), [
        DiscoveryShortcut.latest,
        DiscoveryShortcut.category,
        DiscoveryShortcut.ranking,
      ]);
    },
  );

  testWidgets(
    'license display deduplicates LGPL while preserving both source credits and MIT/GPL',
    (tester) async {
      final entries = (await tester.runAsync(
        () => applicationLicenses().toList(),
      ))!;
      expect(entries.length, 3);
      final shared = entries.first.paragraphs.map((p) => p.text).join('\n');
      expect(shared, contains('tonquer / JMComic-qt'));
      expect(shared, contains('tonquer / picacg-qt'));
      expect(shared, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
      expect(
        entries[1].paragraphs.map((p) => p.text).join('\n'),
        contains('hect0x7'),
      );
      expect(
        entries[2].paragraphs.map((p) => p.text).join('\n'),
        contains('GNU GENERAL PUBLIC LICENSE'),
      );
    },
  );

  test(
    'license scope removes dev-only and duplicate root packages but retains shared runtime notices',
    () async {
      final entries = await relevantLicenses(
        Stream.fromIterable([
          LicenseEntryWithLineBreaks(['flutter_test', 'test_api'], 'unused'),
          LicenseEntryWithLineBreaks(['jm_mobile'], 'duplicate'),
          LicenseEntryWithLineBreaks([
            'flutter',
            'leak_tracker_testing',
          ], 'runtime text'),
          LicenseEntryWithLineBreaks(['image', 'zlib', 'kamico'], 'retained'),
        ]),
      ).toList();
      expect(entries.expand((e) => e.packages), [
        'flutter',
        'image',
        'zlib',
        'kamico',
      ]);
      expect(entries.first.paragraphs.single.text, 'runtime text');
    },
  );

  testWidgets(
    'drag handle reorders, persists across sources/reopen, and resets',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await releaseSession();
      addTearDown(app.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        releaseHost(DiscoveryShortcutOrderScreen(session: app), key: key),
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'discovery-order');
      final handle = find.byKey(const ValueKey('drag-weekly'));
      final start = tester.getCenter(handle),
          target = Offset(
            tester.getCenter(handle).dx,
            tester.getTopLeft(find.byKey(const ValueKey('category'))).dy + 4,
          );
      final drag = await tester.startGesture(start);
      await drag.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 100));
      for (var step = 1; step <= 12; step++) {
        await drag.moveTo(
          Offset.lerp(start + const Offset(0, -30), target, step / 12)!,
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        (app.appearance['discovery_shortcut_order'] as List).first,
        'weekly',
      );
      await app.switchSource();
      expect(
        (app.active.appearance['discovery_shortcut_order'] as List).first,
        'weekly',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        releaseHost(DiscoveryShortcutOrderScreen(session: app.active)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('weekly'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('category'))).dy),
      );
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(
        app.appearance['discovery_shortcut_order'],
        DiscoveryShortcut.values.map((s) => s.name).toList(),
      );
      tester.view.physicalSize = const Size(320, 844);
      await tester.pumpWidget(
        releaseHost(DiscoveryShortcutOrderScreen(session: app), scale: 1.6),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reordered labels stay bound to actual routes and Pic uses the shared relative order',
    (tester) async {
      final calls = <String>[];
      final app = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((r) {
          calls.add(r.url.path);
          return r.url.path == '/promote/'
              ? []
              : {'categories': [], 'content': [], 'list': [], 'total': 0};
        }),
        picClient: FixturePic(),
      );
      addTearDown(app.dispose);
      await app.setAppearance('discovery_shortcut_order', [
        'weekly',
        'latest',
        'ranking',
        'category',
        'serial',
      ]);
      await tester.pumpWidget(releaseHost(DiscoveryScreen(session: app)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shortcut-weekly')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ScheduleScreen>(find.byType(ScheduleScreen)).weekly,
        true,
      );
      Navigator.of(tester.element(find.byType(ScheduleScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shortcut-latest')));
      await tester.pumpAndSettle();
      expect(calls, contains('/latest/'));
      Navigator.of(tester.element(find.byType(PagedComics))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shortcut-ranking')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CatalogScreen>(find.byType(CatalogScreen)).initialSort,
        'mv',
      );
      Navigator.of(tester.element(find.byType(CatalogScreen))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        releaseHost(
          DiscoveryScreen(
            key: const ValueKey('pic'),
            session: app.forSource(ContentSource.pic),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shortcut-weekly')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('shortcut-latest'))).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('shortcut-ranking'))).dx,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('shortcut-ranking'))).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('shortcut-category'))).dx,
        ),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final history in [false, true]) {
    testWidgets(
      '${history ? 'history' : 'bookcase'} selection button stays and toggles without resizing the list',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = await releaseSession();
        addTearDown(app.dispose);
        const comic = Comic(id: '1', title: 'Synthetic');
        await app.store.addLocal(comic);
        await app.store.saveProgress(
          const ReadingProgress(comic: comic, chapterId: '10', page: 2),
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          releaseHost(
            history
                ? HistoryScreen(session: app)
                : BookcaseScreen(session: app),
            key: key,
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byType(CustomScrollView);
        final bounds = tester.getRect(list);
        await tester.tap(find.text('选择'));
        await tester.pumpAndSettle();
        expect(find.text('选择'), findsOneWidget);
        expect(tester.getRect(list), bounds);
        await capture(
          tester,
          key,
          history ? 'history-selection' : 'bookcase-selection',
        );
        await tester.tap(find.text('Synthetic'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<LibraryBookTile>(find.byType(LibraryBookTile)).selected,
          true,
        );
        await tester.tap(find.text('选择'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<LibraryBookTile>(find.byType(LibraryBookTile)).selected,
          isNull,
        );
        expect(find.byType(LibrarySelectionBar), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final mode in ReaderMode.values) {
    testWidgets(
      '${mode.name} menu preserves image bounds, reader viewport and controller',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await SharedPreferences.getInstance().then(
          (p) => p.setString('reader_layout', mode.name),
        );
        final root = Directory.systemTemp.createTempSync('kamico_menu_');
        addTearDown(() => root.deleteSync(recursive: true));
        final bytes = img.encodePng(img.Image(width: 120, height: 300));
        for (var i = 0; i < 3; i++) {
          File('${root.path}/$i.img').writeAsBytesSync(bytes);
        }
        final app = await releaseSession();
        addTearDown(app.dispose);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.runAsync(() async {
          for (var i = 0; i < 3; i++) {
            await precacheImage(
              FileImage(File('${root.path}/$i.img')),
              tester.element(find.byType(SizedBox).first),
            );
          }
        });
        const comic = Comic(id: '1', title: 'Synthetic'),
            chapter = Chapter(id: '10', title: 'Chapter');
        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(
              session: app,
              comic: comic,
              chapter: chapter,
              chapters: const [chapter],
              offline: OfflineChapter(
                comic: comic,
                chapter: chapter,
                folder: root.path,
                count: 3,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = find.byKey(const ValueKey('reader-tap-surface'));
        final bounds = tester.getRect(surface),
            imageBounds = tester.getRect(find.byType(RawImage).first);
        final imageElement = tester.element(find.byType(RawImage).first);
        final controller = mode.scrolling
            ? null
            : tester.widget<PageView>(find.byType(PageView)).controller;
        await tester.tapAt(bounds.center);
        await tester.pumpAndSettle();
        expect(tester.getRect(surface), bounds);
        expect(tester.getRect(find.byType(RawImage).first), imageBounds);
        expect(
          identical(tester.element(find.byType(RawImage).first), imageElement),
          true,
        );
        await tester.tapAt(bounds.center);
        await tester.pumpAndSettle();
        expect(tester.getRect(surface), bounds);
        if (controller != null) {
          expect(
            identical(
              tester.widget<PageView>(find.byType(PageView)).controller,
              controller,
            ),
            true,
          );
        }
        expect(find.text('1/3'), findsOneWidget);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await tester.pumpAndSettle();
        expect(tester.getRect(surface), bounds);
        expect(tester.getRect(find.byType(RawImage).first), imageBounds);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
