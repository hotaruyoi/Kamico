import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/platform_files.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/domain/reader_options.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/design_system.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/ui/comments_body.dart';
import 'package:jm_mobile/ui/downloads.dart';
import 'package:jm_mobile/ui/font_picker.dart';
import 'discovery_test.dart' show apiFor;
import 'ui_design_test.dart' show capture, captureUi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (captureUi) {
      await (FontLoader('Review CJK')..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/Application/Flutter/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('kamico_ui16_');
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
      messenger.setMockMethodCallHandler(PlatformFiles.channel, null);
      await root.delete(recursive: true);
    });
  });
  test(
    'new reading default and all eight old modes migrate into exactly three choices',
    () {
      expect(ReaderMode.values.length, 3);
      expect(readerModeFromPreferences(null, null), ReaderMode.vertical);
      expect(readerModeFromPreferences('invalid', null), ReaderMode.vertical);
      for (final i in [0, 2, 6]) {
        expect(readerModeFromPreferences(null, i), ReaderMode.pages);
      }
      for (final i in [1, 3, 7]) {
        expect(readerModeFromPreferences(null, i), ReaderMode.reversePages);
      }
      for (final i in [4, 5]) {
        expect(readerModeFromPreferences(null, i), ReaderMode.vertical);
      }
      expect(
        readerModeFromPreferences('reversePages', 0),
        ReaderMode.reversePages,
      );
    },
  );
  testWidgets(
    'two tabs combine collapsible description and chapter list; compact choice persists and adapts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = LocalStore(await SharedPreferences.getInstance());
      final session = AppSession(
        store,
        client: apiFor(
          (_) => {
            'id': '1',
            'name': '目录展示示例',
            'description': List.filled(
              8,
              '这是用于检查简介展开与收起的合成文案，每一行都有内容。',
            ).join('\n'),
            'series': [
              for (var i = 1; i <= 30; i++) {'id': '$i', 'name': '第 $i 章'},
            ],
          },
        ),
      );
      final key = GlobalKey();
      var textScale = 1.0;
      var brightness = Brightness.light;
      Future<void> show() => tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppDesign.theme(
              Colors.teal,
              brightness,
              captureUi ? 'Review CJK' : null,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: DetailScreen(
              session: session,
              comic: const Comic(id: '1', title: 'Sample'),
            ),
          ),
        ),
      );
      await show();
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).tabs.length, 2);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -350));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('展开简介'));
      await tester.tap(find.text('展开简介'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      await tester.ensureVisible(find.text('收起简介'));
      await tester.tap(find.text('收起简介'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      await tester.ensureVisible(find.byTooltip('目录样式'));
      expect(find.byType(SearchBar), findsNothing);
      expect(
        tester.getCenter(find.byTooltip('目录样式')).dx,
        greaterThan(tester.getCenter(find.byTooltip('搜索章节')).dx),
      );
      await tester.tap(find.byTooltip('搜索章节'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsOneWidget);
      await tester.enterText(find.byType(TextField), '不存在章节');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配章节'), findsOneWidget);
      await tester.tap(find.byTooltip('清空章节筛选'));
      await tester.pumpAndSettle();
      expect(find.text('没有匹配章节'), findsNothing);
      await tester.enterText(find.byType(TextField), '不存在章节');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('收起章节搜索'));
      await tester.tap(find.byTooltip('收起章节搜索'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsNothing);
      expect(find.text('没有匹配章节'), findsNothing);
      await tester.tap(find.byTooltip('搜索章节'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await tester.tap(find.byTooltip('收起章节搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('目录样式'));
      await tester.pumpAndSettle();
      await capture(tester, key, 'chapter-style-menu');
      await tester.tap(find.text('紧凑短框'));
      await tester.pumpAndSettle();
      expect(store.preferences.getString('chapter_layout'), 'compact');
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.text('第 13 章'), findsNothing);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await capture(tester, key, 'detail-compact');
      await tester.ensureVisible(find.text('展开全部章节 (30)'));
      await tester.tap(find.text('展开全部章节 (30)'));
      await tester.pumpAndSettle();
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(grid.delegate.estimatedChildCount, 30);
      await capture(tester, key, 'detail-expanded');
      tester.view.physicalSize = const Size(320, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      textScale = 1.6;
      brightness = Brightness.dark;
      await show();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('搜索章节'));
      await tester.tap(find.byTooltip('搜索章节'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 6; i++) {
        final y = tester.getCenter(find.byTooltip('收起章节搜索')).dy;
        if (y > 180 && y < 600) break;
        await tester.drag(
          find.byType(NestedScrollView),
          Offset(0, y < 180 ? 180 : -180),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('收起章节搜索'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsNothing);
      textScale = 1.0;
      await tester.pumpWidget(const SizedBox());
      await show();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(
        tester
            .widget<SliverGrid>(find.byType(SliverGrid))
            .delegate
            .estimatedChildCount,
        12,
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'device font list is native, searchable, loads selected font and returns to system',
    (tester) async {
      var lists = 0, loads = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(PlatformFiles.channel, (call) async {
        if (call.method == 'systemFonts') {
          lists++;
          return [
            {'id': 'review-cjk', 'name': 'Device CJK'},
            {'id': 'another', 'name': 'Other font'},
          ];
        }
        if (call.method == 'fontBytes') {
          loads++;
          return File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync();
        }
        return null;
      });
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) => {}),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDeviceFonts(context, session),
                child: const Text('Fonts'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Fonts'));
      await tester.pumpAndSettle();
      expect(lists, 1);
      expect(loads, 0);
      expect(find.text('跟随系统'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'CJK');
      await tester.pumpAndSettle();
      expect(find.text('Other font'), findsNothing);
      await tester.tap(find.text('Device CJK'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(session.appearance['font'], 'device:review-cjk');
      await tester.tap(find.text('Fonts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统'));
      await tester.pumpAndSettle();
      expect(session.appearance['font'], 'system');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets('comment timestamp is at upper right and body is larger', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor(
        (_) => {
          'total': 1,
          'list': [
            {
              'CID': '1',
              'username': '示例用户',
              'addtime': '2026-10-19 12:34',
              'content': '评论正文现在更容易阅读。',
            },
          ],
        },
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppDesign.theme(
            Colors.teal,
            Brightness.light,
            captureUi ? 'Review CJK' : null,
          ),
          home: Scaffold(
            body: CommentsBody(session: session, id: '1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final time = find.text('2026-10-19 12:34'), user = find.text('示例用户');
    expect(tester.getCenter(time).dx, greaterThan(tester.getCenter(user).dx));
    expect(tester.getCenter(time).dy, closeTo(tester.getCenter(user).dy, 6));
    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .style!
          .fontSize,
      17,
    );
    expect(tester.widget<Text>(time).style!.color, Colors.grey.shade600);
    await capture(tester, key, 'comment-typography');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets(
    'download settings show public PDF destination with no PNG format switch',
    (tester) async {
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) => {}),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DownloadScreen(session: session)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下载设置'));
      await tester.pumpAndSettle();
      expect(find.text('PDF 下载目录'), findsOneWidget);
      expect(find.textContaining('系统 Downloads/kamico'), findsOneWidget);
      expect(find.textContaining('PNG'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
