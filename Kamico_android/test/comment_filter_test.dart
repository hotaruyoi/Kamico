import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/comment_filter.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/comments_body.dart';
import 'discovery_test.dart' show apiFor;

/// Serves one page of comments built by [items].
AppSession _session(List<Json> items, {int? total}) => AppSession(
  LocalStore(_prefs),
  client: apiFor(
    (request) => {
      'total': total ?? items.length,
      'list': items,
      'has_more': 0,
    },
  ),
);

late dynamic _prefs;

Json _comment(String id, String content) => {
  'CID': id,
  'AID': '1',
  'username': 'u$id',
  'content': content,
  'addtime': '2024-01-01',
};

/// Serves numbered pages, recording every page the body asked for.
AppSession _pagedSession(
  List<Json> Function(int page) pages, {
  required List<int> requested,
  bool Function(int page)? hasMore,
}) => AppSession(
  LocalStore(_prefs),
  client: apiFor((request) {
    final page = int.parse(request.url.queryParameters['page'] ?? '1');
    requested.add(page);
    final items = pages(page);
    final more = hasMore == null || hasMore(page);
    return {'total': 100, 'list': items, 'has_more': more ? 1 : 0};
  }),
);

/// Wraps [CommentsBody] the way the detail tab does: a nested scroll view
/// owns the absorber handle the body looks up when `nested` is set.
Widget _nested(AppSession session) => MaterialApp(
  home: Scaffold(
    body: NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverOverlapAbsorber(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          sliver: const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ),
      ],
      body: CommentsBody(session: session, id: '1', nested: true),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommentFilter', () {
    test('compile rejects broken patterns and keeps good ones', () {
      expect(CommentFilter.tryCompile('^广告'), isNotNull);
      expect(CommentFilter.tryCompile('([a-z'), isNull);
      expect(CommentFilter.validate(''), '规则不能为空');
      expect(CommentFilter.validate('['), '正则表达式无效');
      expect(CommentFilter.validate('a' * 201), '规则最多 200 个字符');
      expect(CommentFilter.validate('加群'), isNull);
    });

    test('matches plain text with case sensitivity set by the pattern', () {
      const filter = CommentFilter(enabled: true, rules: ['(?i:spam)']);
      expect(filter.blocks('SPAM here'), isTrue);
      expect(filter.blocks('spam'), isTrue);
      expect(filter.blocks('normal comment'), isFalse);
      const strict = CommentFilter(enabled: true, rules: ['spam']);
      expect(strict.blocks('SPAM here'), isFalse);
    });

    test('strips markup the way the comment bubble does', () {
      expect(
        CommentFilter.plain('加群<b>领福利</b><br/>第二行'),
        contains('领福利'),
      );
      expect(CommentFilter.plain('a<br/>b'), contains('\n'));
    });

    test('disabled or empty filters never block', () {
      expect(const CommentFilter(rules: ['a']).blocks('a'), isFalse);
      expect(const CommentFilter(enabled: true).blocks('a'), isFalse);
    });

    test('a broken stored rule is skipped instead of throwing', () {
      const filter = CommentFilter(enabled: true, rules: ['([a-z', 'ok']);
      expect(filter.blocks('ok'), isTrue);
      expect(filter.blocks('other'), isFalse);
    });

    test('round trips through the store', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      expect(CommentFilter.read(store).enabled, isFalse);
      await const CommentFilter(enabled: true, rules: ['广告', '加群']).save(store);
      final restored = CommentFilter.read(store);
      expect(restored.enabled, isTrue);
      expect(restored.rules, ['广告', '加群']);
      expect(
        jsonDecode(store.preferences.getString('comment_filters')!),
        {'enabled': true, 'rules': ['广告', '加群']},
      );
    });

    test('ignores unknown and malformed stored data', () async {
      SharedPreferences.setMockInitialValues({
        'comment_filters': '{"enabled": true, "rules": ["a", "", "  "]}',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      expect(CommentFilter.read(store).rules, ['a']);
      SharedPreferences.setMockInitialValues({'comment_filters': 'not json'});
      final reloaded = LocalStore(await SharedPreferences.getInstance());
      expect(CommentFilter.read(reloaded).enabled, isFalse);
    });
  });

  group('CommentsBody filtering', () {
    testWidgets('hides matching comments before they reach the list', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'comment_filters':
            '{"enabled": true, "rules": ["加群"], "profile": {"x": 1}}',
      });
      _prefs = await SharedPreferences.getInstance();
      final session = _session([
        _comment('1', '正常的评论'),
        _comment('2', '加群领福利'),
        _comment('3', '另一条正常的评论'),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CommentsBody(session: session, id: '1'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('正常的评论'), findsOneWidget);
      expect(find.text('另一条正常的评论'), findsOneWidget);
      expect(find.textContaining('加群领福利'), findsNothing);
      // The header still reports the upstream total; hidden comments leave no
      // trace in the count.
      expect(find.text('评论 · 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('shows the empty state when everything is filtered out', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'comment_filters': '{"enabled": true, "rules": ["广告"]}',
      });
      _prefs = await SharedPreferences.getInstance();
      final session = _session([_comment('1', '广告位招租')]);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CommentsBody(session: session, id: '1'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('已按筛选规则隐藏全部评论'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('a filter button only appears inside the detail tab', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      _prefs = await SharedPreferences.getInstance();
      final session = _session([_comment('1', 'hi')]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CommentsBody(session: session, id: '1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('筛选'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverOverlapAbsorber(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                  sliver: const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ),
              ],
              body: CommentsBody(session: session, id: '1', nested: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('筛选'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('the action row fits the narrowest phone without overflowing', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'comment_filters': '{}'});
      _prefs = await SharedPreferences.getInstance();
      final session = _session([_comment('1', 'hi')]);
      session.api.token = 'token';
      // 1080x2400 at both a 3.0 and the Redmi K50's 3.5 pixel ratio: 360dp and
      // 308dp wide. The second is the narrowest phone this app has shipped on.
      for (final ratio in [3.0, 3.5]) {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = ratio;
        await tester.pumpWidget(_nested(session));
        await tester.pumpAndSettle();
        expect(find.text('发表评论'), findsOneWidget);
        expect(find.text('筛选'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the action row overflowed at pixel ratio $ratio',
        );
      }
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('an invalid pattern is reported and never saved', (tester) async {
      SharedPreferences.setMockInitialValues({'comment_filters': '{}'});
      _prefs = await SharedPreferences.getInstance();
      final session = _session([_comment('1', 'hi')]);
      await tester.pumpWidget(_nested(session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加规则'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '[');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('正则表达式无效'), findsOneWidget);
      expect(
        CommentFilter.read(session.store).rules,
        isEmpty,
        reason: 'a pattern that does not compile must not be stored',
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('a saved pattern turns the filter button active', (tester) async {
      SharedPreferences.setMockInitialValues({'comment_filters': '{}'});
      _prefs = await SharedPreferences.getInstance();
      final session = _session([_comment('1', 'hi'), _comment('2', '加群领福利')]);
      await tester.pumpWidget(_nested(session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('启用筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加规则'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '加群');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('加群'), findsOneWidget);
      expect(
        CommentFilter.read(session.store).active,
        isTrue,
        reason: 'turning the switch on and adding a rule makes it active',
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('dismissing the sheet with back still applies the saved rules', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'comment_filters': '{}'});
      _prefs = await SharedPreferences.getInstance();
      final session = _session([_comment('1', 'hi'), _comment('2', '加群领福利')]);
      await tester.pumpWidget(_nested(session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('启用筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加规则'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '加群');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      // System back pops the sheet with a null result; the rules are already
      // written, so the list has to pick them up anyway.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('筛选'), findsOneWidget);
      expect(find.textContaining('加群领福利'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  });

  group('CommentsBody fetching', () {
    testWidgets('keeps paging until ten comments survive the filter', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'comment_filters':
            '{"enabled": true, "rules": ["广告"], "profile": {"x": 1}}',
      });
      _prefs = await SharedPreferences.getInstance();
      final requested = <int>[];
      // Page 1 is pure spam, page 2 carries four real comments.
      final session = _pagedSession((page) {
        if (page == 1) {
          return [for (var i = 1; i <= 20; i++) _comment('a$i', '广告 $i')];
        }
        return [for (var i = 1; i <= 4; i++) _comment('b$i', '正常评论 $i')];
      }, requested: requested, hasMore: (page) => page == 1);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CommentsBody(session: session, id: '1'))),
      );
      await tester.pumpAndSettle();
      expect(requested, [1, 2], reason: 'the first page had nothing visible');
      expect(find.text('正常评论 1'), findsOneWidget);
      expect(find.textContaining('广告'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('stops after the page budget and offers to keep looking', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'comment_filters': '{"enabled": true, "rules": ["广告"]}',
      });
      _prefs = await SharedPreferences.getInstance();
      final requested = <int>[];
      final session = _pagedSession(
        (page) => [_comment('a$page', '广告 $page')],
        requested: requested,
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CommentsBody(session: session, id: '1'))),
      );
      await tester.pumpAndSettle();
      expect(requested, [1, 2, 3, 4, 5], reason: 'one pass scans 5 pages');
      expect(find.text('这一页都被筛选规则隐藏了'), findsOneWidget);
      // Asking again keeps going instead of giving up on the thread.
      await tester.tap(find.text('继续查找'));
      await tester.pumpAndSettle();
      expect(requested.last, 10);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('only fetches one page while the filter is off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      _prefs = await SharedPreferences.getInstance();
      final requested = <int>[];
      final session = _pagedSession(
        (page) => [_comment('a$page', '评论 $page')],
        requested: requested,
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CommentsBody(session: session, id: '1'))),
      );
      await tester.pumpAndSettle();
      expect(requested, [1]);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('pulling up loads more when one comment fills the screen', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'comment_filters': '{"enabled": true, "rules": ["广告"]}',
      });
      _prefs = await SharedPreferences.getInstance();
      final requested = <int>[];
      final session = _pagedSession((page) {
        if (page == 1) {
          return [_comment('ok', '正常评论'), _comment('ad1', '广告 1')];
        }
        return [_comment('ad$page', '广告 $page')];
      }, requested: requested);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CommentsBody(session: session, id: '1'))),
      );
      await tester.pumpAndSettle();
      expect(requested, [1, 2, 3, 4, 5], reason: 'the pass ran out of budget');
      expect(find.text('正常评论'), findsOneWidget);
      expect(find.text('加载更多评论'), findsOneWidget);

      // A single short comment leaves the list shorter than the viewport, so
      // the pull arrives as an overscroll rather than a scroll update.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(requested.length, greaterThan(5), reason: 'overscroll must load');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('the keep-looking state still loads on scroll', (tester) async {
      SharedPreferences.setMockInitialValues({
        'comment_filters': '{"enabled": true, "rules": ["广告"]}',
      });
      _prefs = await SharedPreferences.getInstance();
      final requested = <int>[];
      final session = _pagedSession(
        (page) => [_comment('a$page', '广告 $page')],
        requested: requested,
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CommentsBody(session: session, id: '1'))),
      );
      await tester.pumpAndSettle();
      expect(requested, [1, 2, 3, 4, 5]);
      final before = requested.length;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(requested.length, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });

    testWidgets('stops early when the upstream runs out', (tester) async {
      SharedPreferences.setMockInitialValues({
        'comment_filters': '{"enabled": true, "rules": ["广告"]}',
      });
      _prefs = await SharedPreferences.getInstance();
      final requested = <int>[];
      final session = _pagedSession(
        (page) => [_comment('a$page', '广告 $page')],
        requested: requested,
        hasMore: (_) => false,
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CommentsBody(session: session, id: '1'))),
      );
      await tester.pumpAndSettle();
      expect(requested, [1]);
      expect(find.text('已按筛选规则隐藏全部评论'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  });
}
