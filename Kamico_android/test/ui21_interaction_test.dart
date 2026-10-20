import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/domain/reader_options.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/bookcase.dart';
import 'package:jm_mobile/ui/cover_image.dart';
import 'package:jm_mobile/ui/design_system.dart';
import 'package:jm_mobile/ui/discovery.dart';
import 'package:jm_mobile/ui/filled_select.dart';
import 'package:jm_mobile/ui/library_layout.dart';
import 'package:jm_mobile/ui/motion.dart';
import 'package:jm_mobile/ui/reader_settings.dart';
import 'package:jm_mobile/ui/translations.dart';
import 'discovery_test.dart' show apiFor;
import 'ui_design_test.dart' show capture, captureUi;

Finder select(String label) =>
    find.byWidgetPredicate((w) => w is FilledSelect && w.label == label);

Future<void> choose(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(select(label));
  await tester.pumpAndSettle();
  await tester.tap(select(label));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, value));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await AppTranslations.load();
    if (captureUi) {
      for (final entry in {
        'Review CJK': 'C:/Windows/Fonts/msyh.ttc',
        'MaterialIcons':
            'D:/Application/Flutter/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              File(
                entry.value,
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            ))
            .load();
      }
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppSession> session({
    void Function(String, Map<String, String>)? request,
  }) async => AppSession(
    LocalStore(await SharedPreferences.getInstance()),
    client: apiFor((r) {
      request?.call(r.url.path, r.url.queryParameters);
      switch (r.url.path) {
        case '/week/':
          return {
            'categories': [
              {'id': '1', 'time': '2026 第261期 10.16—10.22'},
              {'id': '2', 'time': '2026 第260期'},
            ],
          };
        case '/categories/':
          return {
            'categories': [
              {
                'name': '原创',
                'slug': 'original',
                'sub_categories': [
                  {'name': '中文', 'slug': 'chinese'},
                ],
              },
            ],
          };
        default:
          return {
            'content': [
              for (var i = 0; i < 60; i++)
                {
                  'id': '$i',
                  'name': '阅读样例 $i',
                  'author': ['示例作者'],
                },
            ],
            'list': [],
            'total': 60,
          };
      }
    }),
  );
  Widget host(
    Widget body, {
    GlobalKey? captureKey,
    bool reduceMotion = false,
    double scale = 1,
  }) => RepaintBoundary(
    key: captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppDesign.theme(
        const Color(0xff607db8),
        Brightness.dark,
        captureUi ? 'Review CJK' : null,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(body: body),
    ),
  );
  void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'weekly controls share a row; menu selection changes the actual request',
    (tester) async {
      phone(tester);
      final calls = <Map<String, String>>[];
      final app = await session(
        request: (p, q) {
          if (p == '/week/filter/') calls.add(q);
        },
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        host(ScheduleScreen(session: app, weekly: true), captureKey: key),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(select('档期')).dy,
        tester.getTopLeft(select('类型')).dy,
      );
      expect(
        tester.getSize(select('档期')).width,
        greaterThan(tester.getSize(select('类型')).width),
      );
      await tester.tap(select('档期'));
      await tester.pumpAndSettle();
      await capture(tester, key, 'weekly-menu');
      await tester.tap(find.widgetWithText(MenuItemButton, '2026 第260期'));
      await tester.pumpAndSettle();
      expect(calls.last['id'], '2');
      await choose(tester, '类型', '韩漫');
      expect(calls.last['type'], 'hanman');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'category drafts cancel without requests, apply includes dependent subcategory',
    (tester) async {
      phone(tester);
      final calls = <Map<String, String>>[];
      final app = await session(
        request: (p, q) {
          if (p == '/categories/filter/') calls.add(q);
        },
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        host(CatalogScreen(session: app), captureKey: key),
      );
      await tester.pumpAndSettle();
      final before = calls.length;
      final viewport = tester.getSize(find.byType(CustomScrollView));
      await tester.tap(find.text('筛选和排序'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getSize(find.byType(CustomScrollView)), viewport);
      await choose(tester, '分类', '原创');
      await choose(tester, '子分类', '中文');
      await choose(tester, '排序', '周排行');
      expect(calls.length, before);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1200));
      await tester.pumpAndSettle();
      await capture(tester, key, 'category-inline');
      await tester.ensureVisible(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls.length, before);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1200));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('筛选和排序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选和排序'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledSelect>(select('分类')).value, '0');
      await choose(tester, '分类', '原创');
      await choose(tester, '子分类', '中文');
      await choose(tester, '排序', '周排行');
      await tester.ensureVisible(find.text('应用筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(calls.length, before + 1);
      expect(calls.last['c'], 'original_chinese');
      expect(calls.last['o'], 'mv_w');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'multi-select preserves cover element, puts checkbox after title and leaves last row accessible',
    (tester) async {
      phone(tester);
      final app = await session();
      for (var i = 0; i < 20; i++) {
        await app.store.addLocal(Comic(id: '$i', title: '阅读样例 $i'));
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        host(BookcaseScreen(session: app), captureKey: key),
      );
      await tester.pumpAndSettle();
      final first = find.byType(LibraryBookTile).first;
      final cover = find.descendant(
        of: first,
        matching: find.byType(CoverImage),
      );
      final element = tester.element(cover);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(identical(tester.element(cover), element), isTrue);
      final checkbox = find.descendant(
        of: first,
        matching: find.byType(Checkbox),
      );
      expect(
        tester.getCenter(checkbox).dx,
        greaterThan(tester.getCenter(cover).dx),
      );
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('已选 1'), findsOneWidget);
      await capture(tester, key, 'bookcase-selection');
      final barTop = tester.getTopLeft(find.byType(LibrarySelectionBar)).dy;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byType(LibraryBookTile).last).dy,
        lessThanOrEqualTo(barTop),
      );
      await tester.tap(find.text('完成选择'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'reader slider previews do not write preferences until release or reset the reader',
    (tester) async {
      phone(tester);
      final app = await session();
      var modeChanges = 0, environmentChanges = 0;
      final key = GlobalKey();
      await tester.pumpWidget(
        host(
          ReaderSettingsPanel(
            session: app,
            mode: ReaderMode.vertical,
            onMode: (_) => modeChanges++,
            onEnvironment: () async {
              environmentChanges++;
            },
          ),
          captureKey: key,
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'reader-settings');
      final seconds = find.byType(Slider).first;
      await tester.ensureVisible(seconds);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(seconds));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(app.store.preferences.getInt('reader_seconds'), isNull);
      expect(modeChanges, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(app.store.preferences.getInt('reader_seconds'), isNotNull);
      await choose(tester, '屏幕方向', '横屏');
      expect(environmentChanges, 1);
      expect(
        app.store.preferences.getString('reader_orientation'),
        'landscape',
      );
      await tester.ensureVisible(find.text(ReaderMode.vertical.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ReaderMode.vertical.label));
      await tester.pumpAndSettle();
      expect(
        modeChanges,
        0,
        reason: 'Re-selecting the current mode must keep existing controllers',
      );
      await tester.ensureVisible(find.text(ReaderMode.reversePages.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ReaderMode.reversePages.label));
      await tester.pumpAndSettle();
      expect(modeChanges, 1);
      expect(
        app.store.preferences.getString('reader_layout'),
        ReaderMode.reversePages.name,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'reduced motion and rapid menu toggles settle without idle frames',
    (tester) async {
      phone(tester);
      var value = 'a';
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Column(
                children: [
                  FilledSelect(
                    label: '测试',
                    value: value,
                    choices: const {'a': '选项 A', 'b': '选项 B'},
                    onChanged: (v) => update(() => value = v),
                  ),
                  const AppReveal(visible: true, child: Text('内容')),
                ],
              );
            },
          ),
          reduceMotion: true,
        ),
      );
      expect(
        tester.widget<MenuAnchor>(find.byType(MenuAnchor)).animated,
        isFalse,
      );
      expect(
        tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
        Duration.zero,
      );
      for (var i = 0; i < 5; i++) {
        await tester.tap(select('测试'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, '选项 B'));
        await tester.pumpAndSettle();
      }
      expect(value, 'b');
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reader settings and wide selectors remain operable at large text in both themes',
    (tester) async {
      phone(tester, size: const Size(320, 640));
      final app = await session();
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppDesign.theme(Colors.blue, brightness, null),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ReaderSettingsPanel(
                session: app,
                mode: ReaderMode.vertical,
                onMode: (_) {},
                onEnvironment: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await choose(tester, '屏幕方向', '竖屏');
        await tester.ensureVisible(find.byType(Slider).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Slider).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpWidget(
        host(
          FilledSelect(
            label: '宽屏选择',
            value: 'a',
            choices: const {'a': '一个完整显示的长选项，用于检查菜单的宽度约束与换行', 'b': '其他选项'},
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(select('宽屏选择'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, '其他选项'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'paged grid scrolling preserves visible card widgets and menu animation never changes viewport',
    (tester) async {
      phone(tester);
      final app = await session();
      await tester.pumpWidget(host(CatalogScreen(session: app)));
      await tester.pumpAndSettle();
      final first = find.byType(ComicCard).first;
      final before = tester.widget<ComicCard>(first);
      final viewport = tester.getSize(find.byType(CustomScrollView));
      final gesture = await tester.startGesture(const Offset(195, 450));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
      expect(identical(tester.widget<ComicCard>(first), before), isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选和排序'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getSize(find.byType(CustomScrollView)), viewport);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
