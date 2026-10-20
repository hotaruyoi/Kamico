import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/pic_client.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/domain/reader_options.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/bookcase.dart';
import 'package:jm_mobile/ui/design_system.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/ui/library_layout.dart';
import 'package:jm_mobile/ui/reader_settings.dart';
import 'package:jm_mobile/ui/translations.dart';
import 'multi_source_test.dart' show FixtureJm, FixturePic, ok, paged, picComic;
import 'ui_design_test.dart' show capture, captureUi;

class HistoryJm extends FixtureJm {
  final pages = <int>[];
  Completer<ComicPage>? gate;
  @override
  Future<ComicPage> cloudHistory(int page) async {
    pages.add(page);
    if (gate case final pending?) return pending.future;
    return ComicPage(
      [Comic(id: 'cloud-$page', title: '云端样例 $page')],
      2,
      more: page < 2,
    );
  }
}

class LikesPic extends FixturePic {
  LikesPic(this.likes);
  final String? likes;
  @override
  Future<ComicDetail> detail(String id, {bool refresh = false}) async =>
      ComicDetail(
        comic: Comic(
          id: id,
          title: '合成作品 · 详情样例',
          source: ContentSource.pic,
          authors: ['示例作者'],
        ),
        description: '用于核对详情元数据的合成内容。',
        tags: ['示例标签'],
        favorite: false,
        chapters: [Chapter(id: '$id~1~ep', title: '第1话')],
        likes: likes,
      );
}

void main() {
  setUpAll(() async {
    await AppTranslations.load();
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  Future<AppSession> session({HistoryJm? jm, FixturePic? pic}) async {
    final app = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: jm ?? HistoryJm(),
      picClient: pic ?? FixturePic(),
    );
    addTearDown(app.dispose);
    return app;
  }

  void phone(WidgetTester tester, {double width = 390}) {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host(Widget body, {GlobalKey? key, double scale = 1}) =>
      RepaintBoundary(
        key: key,
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
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: body),
        ),
      );

  test('JM likes preserve counts, abbreviated values and missing data', () {
    for (final (raw, expected) in [
      (1234, '1234'),
      ('1.2万', '1.2万'),
      ('12,345', '12,345'),
      (0, '0'),
      (null, null),
      ('', null),
      ('unknown', null),
    ]) {
      expect(ComicDetail.fromJson({'likes': raw}).likes, expected);
    }
  });
  test(
    'Pic detail maps totalLikes, summary fallback, zero and absent counts',
    () async {
      for (final (fields, expected) in <(Json, String?)>[
        ({'totalLikes': 4567, 'likesCount': 12}, '4567'),
        ({'totalLikes': 0, 'likesCount': 12}, '0'),
        ({'likesCount': 123}, '123'),
        ({}, null),
      ]) {
        final api = PicClient(
          transport: MockClient(
            (request) async => request.url.path.endsWith('/eps')
                ? ok({
                    'eps': paged([
                      {'_id': 'ep', 'title': 'First'},
                    ]),
                  })
                : ok({
                    'comic': {...picComic('book'), ...fields},
                  }),
          ),
        )..token = 'synthetic';
        try {
          expect((await api.detail('book')).likes, expected);
        } finally {
          api.close();
        }
      }
    },
  );
  testWidgets('history retains local/cloud switch when Pic is active', (
    tester,
  ) async {
    phone(tester);
    final app = await session();
    await app.switchSource();
    await app.store.saveProgress(
      const ReadingProgress(
        comic: Comic(id: 'local', title: 'Pic 本地记录', source: ContentSource.pic),
        chapterId: 'ep',
        page: 2,
      ),
    );
    await tester.pumpWidget(host(HistoryScreen(session: app.active)));
    await tester.pumpAndSettle();
    expect(find.byType(AppSourceSwitch), findsOneWidget);
    expect(find.byType(LibraryBookTile), findsOneWidget);
    await tester.tap(find.text('云端历史'));
    await tester.pumpAndSettle();
    expect(find.text('Pic 暂无云端历史接口'), findsOneWidget);
    expect(find.byType(LibraryBookTile), findsNothing);
    await tester.tap(find.text('查看本地历史'));
    await tester.pumpAndSettle();
    expect(find.text('Pic 本地记录'), findsOneWidget);
    expect(app.store.history.single.page, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'JM cloud history requires login, pages the API and rejects stale source results',
    (tester) async {
      phone(tester);
      final jm = HistoryJm();
      final app = await session(jm: jm);
      Widget history() => host(HistoryScreen(session: app.active));
      await tester.pumpWidget(history());
      await tester.pumpAndSettle();
      await tester.tap(find.text('云端历史'));
      await tester.pumpAndSettle();
      expect(find.text('登录后查看云端历史'), findsOneWidget);
      expect(jm.pages, isEmpty);
      jm.token = 'synthetic';
      await tester.pumpWidget(history());
      await tester.pumpAndSettle();
      expect(jm.pages, [1]);
      expect(find.text('云端样例 1'), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(jm.pages, [1, 2]);
      expect(find.text('云端样例 2'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '下一页',
              ),
            )
            .onPressed,
        isNull,
      );
      jm.gate = Completer<ComicPage>();
      await tester.tap(find.byTooltip('上一页'));
      await tester.pump();
      await app.switchSource();
      await tester.pumpWidget(history());
      await tester.pumpAndSettle();
      jm.gate!.complete(
        const ComicPage([Comic(id: 'late', title: '过期账号结果')], 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pic 暂无云端历史接口'), findsOneWidget);
      expect(find.text('过期账号结果'), findsNothing);
      expect(find.text('Pic · 0 本'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'grouped history cards select, delete and undo colliding source IDs independently',
    (tester) async {
      phone(tester);
      final app = await session();
      const jm = Comic(id: 'same', title: 'JM 历史样例');
      const pic = Comic(
        id: 'same',
        title: 'Pic 历史样例',
        source: ContentSource.pic,
      );
      for (final comic in [jm, pic]) {
        await app.store.saveProgress(
          ReadingProgress(comic: comic, chapterId: 'ep', page: 4),
        );
      }
      final key = GlobalKey();
      await tester.pumpWidget(host(HistoryScreen(session: app), key: key));
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<LibraryBookTile>(find.byType(LibraryBookTile))
          .toList();
      expect(cards.map((c) => c.comic.source), [
        ContentSource.jm,
        ContentSource.pic,
      ]);
      expect(
        tester.getTopLeft(find.text('JM')).dy,
        lessThan(tester.getTopLeft(find.text('PIC')).dy),
      );
      await capture(tester, key, 'history-local');
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pic.title));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.byType(DetailScreen), findsNothing);
      expect(
        tester
            .widget<LibraryBookTile>(
              find.byWidgetPredicate(
                (w) =>
                    w is LibraryBookTile && w.comic.source == ContentSource.pic,
              ),
            )
            .selected,
        true,
      );
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(app.store.history.single.comic.key, jm.key);
      expect(app.store.chapterProgress(pic.key, 'ep'), isNull);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(
        app.store.history.map((p) => p.comic.key),
        containsAll([jm.key, pic.key]),
      );
      expect(app.store.chapterProgress(pic.key, 'ep')!.page, 4);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'detail shows likes beside the cover, including actual zero and unknown',
    (tester) async {
      phone(tester);
      for (final likes in ['12,345', '0', null]) {
        final app = await session(pic: LikesPic(likes));
        final key = GlobalKey();
        await tester.pumpWidget(
          host(
            DetailScreen(
              session: app.forSource(ContentSource.pic),
              comic: const Comic(
                id: 'sample',
                title: '合成作品',
                source: ContentSource.pic,
              ),
            ),
            key: key,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('detail-likes')), findsOneWidget);
        expect(
          find.text(likes == null ? '点赞数暂无数据' : '点赞 $likes'),
          findsOneWidget,
        );
        if (likes == '12,345') await capture(tester, key, 'detail-likes');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'orientation matches mode tile width and height, persists selection and fits narrow large text',
    (tester) async {
      phone(tester);
      final app = await session();
      var environments = 0;
      Widget panel({double scale = 1, GlobalKey? key}) => host(
        ReaderSettingsPanel(
          session: app,
          mode: ReaderMode.vertical,
          onMode: (_) {},
          onEnvironment: () async {
            environments++;
          },
        ),
        scale: scale,
        key: key,
      );
      final key = GlobalKey();
      await tester.pumpWidget(panel(key: key));
      await tester.pumpAndSettle();
      final orientation = find.byKey(const ValueKey('reader-orientation'));
      final mode = find.widgetWithText(ListTile, '竖向连续滑动');
      expect(tester.getSize(orientation), tester.getSize(mode));
      expect(tester.getSize(mode).height, 88);
      await capture(tester, key, 'reader-settings');
      await tester.tap(orientation);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '横屏'));
      await tester.pumpAndSettle();
      expect(
        app.store.preferences.getString('reader_orientation'),
        'landscape',
      );
      expect(environments, 1);
      tester.view.physicalSize = const Size(320, 844);
      await tester.pumpWidget(panel(scale: 1.8));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'My and Discovery use the same circular app bar source action without text',
    (tester) async {
      phone(tester);
      final app = await session();
      if (captureUi) await app.setAppearance('font', 'Review CJK');
      await app.setAppearance('theme', 'dark');
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: JmApp(session: app),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('content-source-toggle'));
      for (final tab in ['发现', '我的']) {
        if (tab == '我的') await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(
          find.ancestor(of: button, matching: find.byType(AppBar)),
          findsOneWidget,
        );
        final control = tester.widget<IconButton>(button);
        final theme = Theme.of(tester.element(button));
        expect(control.style!.shape!.resolve({}), isA<CircleBorder>());
        expect(
          control.style!.backgroundColor!.resolve({}),
          theme.navigationBarTheme.indicatorColor ??
              theme.colorScheme.secondaryContainer,
        );
        final selectedIndicator = tester
            .widgetList<NavigationIndicator>(find.byType(NavigationIndicator))
            .singleWhere((w) => w.animation.value == 1);
        expect(
          control.style!.backgroundColor!.resolve({}),
          selectedIndicator.color,
        );
        expect(tester.getSize(button), const Size(48, 48));
        expect(
          find.descendant(of: button, matching: find.byType(Text)),
          findsNothing,
        );
        final before = app.activeSource;
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(app.activeSource, isNot(before));
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          tab == '发现' ? 0 : 4,
        );
        await capture(
          tester,
          key,
          tab == '我的' ? 'my-source-action' : 'discovery-source-action',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
