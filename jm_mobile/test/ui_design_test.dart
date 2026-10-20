import 'package:jm_mobile/ui/filled_select.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/platform_files.dart';
import 'package:jm_mobile/data/site_links.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/settings.dart';
import 'package:jm_mobile/ui/account.dart';
import 'package:jm_mobile/ui/comic_browser.dart';
import 'package:jm_mobile/data/download_queue.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/ui/library_layout.dart';
import 'package:jm_mobile/ui/chapter_download_sheet.dart';
import 'package:image/image.dart' as img;
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/ui/design_system.dart';
import 'package:jm_mobile/ui/preferences.dart';
import 'package:jm_mobile/ui/translations.dart';
import 'discovery_test.dart' show apiFor;
import 'package:jm_mobile/app_version.dart';

const captureUi = bool.fromEnvironment('CAPTURE_UI');
Future<AppSession> fixtureSession() async {
  SharedPreferences.setMockInitialValues({
    'appearance': jsonEncode({'font': captureUi ? 'Review CJK' : 'sans-serif'}),
  });
  return AppSession(
    LocalStore(await SharedPreferences.getInstance()),
    client: apiFor((request) {
      switch (request.url.path) {
        case '/promote/':
          return [
            {
              'title': '精选推荐',
              'type': 'category',
              'id': '1',
              'slug': 'all',
              'filter_val': '',
              'content': [
                for (var i = 1; i <= 12; i++)
                  {
                    'id': '$i',
                    'name': '阅读样例 $i',
                    'author': ['示例作者'],
                  },
              ],
            },
          ];
        case '/album/':
          return {
            'id': '1',
            'name': '阅读样例',
            'description': '这是用于检查界面排版的合成测试内容。',
            'author': ['示例作者'],
            'tags': ['示例标签'],
            'series': [
              {'id': '1', 'name': '第一章'},
              {'id': '2', 'name': '第二章'},
            ],
          };
        case '/daily/':
          return {
            'daily_id': 1,
            'record': [
              [
                for (var i = 1; i <= 28; i++) {'date': i, 'signed': i < 18},
              ],
            ],
            'makeup_limit': 3,
            'makeup_used': 0,
          };
        case '/favorite/':
          return {'list': [], 'total': 0, 'folder_list': []};
        case '/forum/':
          return {
            'list': [
              {
                'CID': '1',
                'AID': '1',
                'username': '示例用户',
                'addtime': '2026-10-18',
                'content': '用于检查评论卡片和回复操作。',
                'replys': [],
              },
            ],
            'total': 1,
          };
        default:
          return {'content': [], 'total': 0};
      }
    }),
  );
}

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!captureUi) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await Directory(
      'docs/previews/$appVersion',
    ).create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppTranslations.load();
    if (captureUi) {
      final loader = FontLoader('Review CJK')
        ..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            'D:/Application/Flutter/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
    }
  });
  setUp(() {
    final root = Directory.systemTemp.createTempSync('jm_design_test_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (call) async => root.path);
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });
  testWidgets('小卡片在两种手机宽度呈现四列和五列', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await fixtureSession();
    await session.setAppearance('card_density', 'compact');
    final key = GlobalKey();
    for (final entry in {360.0: 4, 390.0: 5}.entries) {
      viewport(tester, Size(entry.key, 844));
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: JmApp(session: session),
        ),
      );
      await tester.pumpAndSettle();
      final grid =
          tester.widget<SliverGrid>(find.byType(SliverGrid).first).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(grid.crossAxisCount, entry.value);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'compact-${entry.value}-columns');
    }
    await tester.tap(find.byTooltip('卡片大小'));
    await tester.pumpAndSettle();
    await capture(tester, key, 'card-size-menu');
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('登录仅保留登录和外站注册，注册不打开应用内表单', (tester) async {
    viewport(tester, const Size(390, 844));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await fixtureSession();
    final key = GlobalKey();
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PlatformFiles.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PlatformFiles.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppDesign.theme(
            const Color(0xff296b5c),
            Brightness.light,
            captureUi ? 'Review CJK' : 'sans-serif',
          ),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: LoginScreen(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('找回密码'), findsNothing);
    expect(find.text('验证邮箱'), findsNothing);
    expect(find.text('重发验证邮件'), findsNothing);
    expect(find.text('验证码'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    await capture(tester, key, 'login');
    await tester.ensureVisible(find.text('注册账号'));
    await tester.tap(find.text('注册账号'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'openWeb');
    expect(calls.single.arguments, {'url': officialRegistrationUrl});
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      false,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('主导航与分段切换适配手机和平板，页面无溢出', (tester) async {
    viewport(tester, const Size(390, 844));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await fixtureSession();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: JmApp(session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await capture(tester, key, 'discovery');
    for (final name in ['书架', '历史', '下载', '我的']) {
      await tester.tap(find.widgetWithText(NavigationDestination, name));
      await tester.pumpAndSettle();
      if (name == '书架') {
        expect(find.byType(SegmentedButton<bool>), findsOneWidget);
        await tester.tap(find.text('本地'));
        await tester.pumpAndSettle();
      }
      if (name == '下载') {
        expect(find.byType(SegmentedButton<bool>), findsOneWidget);
        await tester.tap(find.text('本地书库'));
        await tester.pumpAndSettle();
      }
      await capture(
        tester,
        key,
        {
          '书架': 'favorites',
          '历史': 'history',
          '下载': 'downloads',
          '我的': 'settings',
        }[name]!,
      );
      expect(tester.takeException(), isNull, reason: name);
    }
    viewport(tester, const Size(900, 900));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
    await capture(tester, key, 'tablet-settings');
    await session.setAppearance('theme', 'dark');
    await tester.pumpAndSettle();
    await capture(tester, key, 'tablet-dark-settings');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('详情、账号、评论与维护页采用统一布局', (tester) async {
    viewport(tester, const Size(390, 844));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await fixtureSession();
    session.api.token = 'fixture';
    session.api.userProfile = {
      'uid': '42',
      'username': '示例账号',
      'coin': 100,
      'level': 3,
      'exp': 400,
    };
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: JmApp(session: session),
      ),
    );
    await tester.pumpAndSettle();
    final nav = Navigator.of(tester.element(find.byType(NavigationBar)));
    for (final entry in <String, Widget>{
      'detail': DetailScreen(
        session: session,
        comic: const Comic(id: '1', title: '阅读样例'),
      ),
      'account': AccountScreen(session: session),
      'comments': CommentsScreen(session: session, id: '1'),
      'appearance': AppearanceScreen(session: session),
      'maintenance': MaintenanceScreen(session: session),
    }.entries) {
      nav.push(MaterialPageRoute<void>(builder: (_) => entry.value));
      await tester.pumpAndSettle();
      await capture(tester, key, entry.key);
      expect(tester.takeException(), isNull, reason: entry.key);
      nav.pop();
      await tester.pumpAndSettle();
    }
    viewport(tester, const Size(1200, 900));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ComicBrowser(
          session: session,
          selected: const Comic(id: '1', title: '阅读样例'),
          items: const [Comic(id: '2', title: '另一作品')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, key, 'tablet-comic-browser');
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(tester.takeException(), isNull);
    nav.pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('管理页与详情同页面板的合成内容预览', (tester) async {
    viewport(tester, const Size(390, 844));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await fixtureSession();
    session.api.token = 'fixture';
    session.api.userProfile = {'uid': '42'};
    const titles = ['午后阅读笔记', '小城故事', '旅途中的一页', '星空下的约定', '花开时节', '远方来信'];
    for (var i = 0; i < titles.length; i++) {
      final comic = Comic(
        id: '${i + 1}',
        title: titles[i],
        authors: const ['示例作者'],
      );
      await session.store.addLocal(comic);
      final job = DownloadJob(
        comic: comic,
        chapter: Chapter(id: 'c$i', title: '第一章'),
        state: i == 0
            ? 'running'
            : i == 1
            ? 'failed'
            : 'paused',
        done: i == 0 ? 12 : 0,
        total: 24,
      );
      session.queue.jobs[job.id] = job;
    }
    await session.store.saveProgress(
      ReadingProgress(
        comic: Comic(id: '1', title: titles.first),
        chapterId: 'c0',
        page: 1,
      ),
    );
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 20, height: 30)),
    );
    await tester.runAsync(() async {
      final directory = await session.downloads.directory;
      final repository = DownloadRepository(
        root: () async => directory.parent,
        fetchImage: (_, _) async => png,
      );
      for (var i = 0; i < 3; i++) {
        await repository.save(
          Comic(id: '${i + 1}', title: titles[i]),
          Chapter(id: 'saved$i', title: '离线章节'),
          ReaderChapter(
            id: 'saved$i',
            scrambleId: 0,
            pages: const [ReaderPage(path: '', name: '0')],
          ),
          (_, _) {},
          checkpoint: () {},
        );
      }
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: JmApp(session: session),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '书架'));
    await tester.pumpAndSettle();
    await capture(tester, key, 'favorites-populated');
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    await capture(tester, key, 'favorites-scrolled');
    await tester.tap(find.widgetWithText(NavigationDestination, '下载'));
    await tester.pumpAndSettle();
    await capture(tester, key, 'download-tasks');
    await tester.tap(find.text('本地书库'));
    await tester.pump();
    for (
      var i = 0;
      i < 60 && find.byType(LibraryBookTile).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await capture(tester, key, 'downloads-populated');
    final nav = Navigator.of(tester.element(find.byType(NavigationBar)));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          session: session,
          comic: const Comic(id: '1', title: '阅读样例'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '评论'));
    await tester.pumpAndSettle();
    await capture(tester, key, 'detail-comments');
    await tester.drag(find.byType(TabBarView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await capture(tester, key, 'detail-comments-scrolled');
    await tester.tap(find.widgetWithText(Tab, '详情'));
    await tester.pumpAndSettle();
    await capture(tester, key, 'detail-about');
    await tester.drag(find.byType(NestedScrollView), const Offset(0, 800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('下载'));
    await tester.tap(find.byTooltip('下载'));
    await tester.pump();
    for (
      var i = 0;
      i < 60 && find.byType(CheckboxListTile).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await capture(tester, key, 'detail-download-sheet');
    expect(find.byType(ChapterDownloadSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('窄屏大字体下登录、筛选与设置仍可操作', (tester) async {
    viewport(tester, const Size(360, 800));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await fixtureSession();
    await session.setAppearance('scale', 1.4);
    await session.setAppearance('language', 'en');
    await tester.pumpWidget(JmApp(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'My'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final nav = Navigator.of(tester.element(find.byType(NavigationBar)));
    nav.push(
      MaterialPageRoute<void>(builder: (_) => LoginScreen(session: session)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Register account'));
    expect(tester.takeException(), isNull);
    nav.pop();
    await tester.pumpAndSettle();
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => AppearanceScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FilledSelect), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
