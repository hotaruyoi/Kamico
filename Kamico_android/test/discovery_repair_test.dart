import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/discovery.dart';
import 'package:jm_mobile/ui/filled_select.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  testWidgets(
    'reset filters applies to the displayed query, draft editing is explicit and clear returns history',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final queries = <Map<String, String>>[];
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((request) {
          queries.add(request.url.queryParameters);
          return {'content': [], 'total': 0};
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            session: session,
            initialText: 'old',
            initialType: 'author',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(queries.last['search_type'], 'author');
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(TextField),
        ),
        'draft',
      );
      await tester.pump();
      expect(find.textContaining('当前结果：old'), findsOneWidget);
      expect(find.textContaining('输入已修改'), findsOneWidget);
      await tester.tap(find.text('重置筛选'));
      await tester.pumpAndSettle();
      expect(queries.last['search_query'], 'old');
      expect(queries.last['search_type'], 'site');
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(find.byType(PagedComics), findsNothing);
      expect(find.text('搜索历史 / 输入提示'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'inline filters remain scrollable with large text and cancelling does not apply edits',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      var requests = 0;
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) {
          requests++;
          return {'content': [], 'total': 0};
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SearchScreen(session: session, initialText: 'fixture'),
        ),
      );
      await tester.pumpAndSettle();
      final before = requests;
      await tester.tap(find.text('筛选和排序'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final year = find.byWidgetPredicate(
        (w) => w is FilledSelect && w.label == '年份',
      );
      await tester.ensureVisible(year);
      await tester.pumpAndSettle();
      await tester.tap(year);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '2024'));
      await tester.pumpAndSettle();
      expect(requests, before);
      await tester.ensureVisible(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(requests, before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets('a blocked grid explains why and offers access to device rules', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'blocked_words': ['hidden'],
    });
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor((_) => []),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicGrid(
            session: session,
            items: const [Comic(id: '1', title: 'hidden')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前内容已被屏蔽'), findsOneWidget);
    expect(find.text('调整屏蔽规则'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
