import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/discovery.dart';

http.Response response(dynamic data, {int timestamp = 1700000000}) {
  final key = Uint8List.fromList(
    utf8.encode(
      md5
          .convert(utf8.encode('$timestamp${const ApiConfig().dataSecret}'))
          .toString(),
    ),
  );
  final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
    ..init(
      true,
      PaddedBlockCipherParameters<KeyParameter, Null>(KeyParameter(key), null),
    );
  return http.Response(
    jsonEncode({
      'code': 200,
      'data': base64Encode(
        cipher.process(Uint8List.fromList(utf8.encode(jsonEncode(data)))),
      ),
    }),
    200,
  );
}

JmClient apiFor(dynamic Function(http.Request) handler) => JmClient(
  config: const ApiConfig(),
  now: () => 1700000000,
  transport: MockClient((request) async => response(handler(request))),
);

void main() {
  test(
    'promote preserves group membership and metadata, skips non-comic sections',
    () async {
      final api = apiFor(
        (_) => [
          {
            'title': '推荐一',
            'type': 'promote',
            'id': 26,
            'filter_val': '26',
            'content': [
              {'id': 1, 'name': 'A'},
            ],
          },
          {
            'title': '推荐二',
            'type': 'category_id',
            'slug': 'hanman',
            'content': [
              {'id': 1, 'name': 'A'},
            ],
          },
          {'title': '书库', 'type': 'library', 'content': []},
          {'title': '小说', 'type': 'novels', 'content': []},
        ],
      );
      addTearDown(api.close);
      final groups = await api.homeSections();
      expect(groups.map((e) => e.title), ['推荐一', '推荐二']);
      expect(groups.first.filter, '26');
      expect(groups[1].items.single.id, groups[0].items.single.id);
    },
  );
  test(
    'discovery endpoint parameters match Qt, including zero-based latest/week',
    () async {
      final api = apiFor((request) {
        final q = request.url.queryParameters;
        switch (request.url.path) {
          case '/latest/':
            expect(q['page'], '1');
            return [];
          case '/search/':
            expect(q['search_type'], 'author');
            expect(q['y'], '2025');
            expect(q['m'], '7');
            expect(q['o'], 'tf');
            return {'total': 0, 'content': []};
          case '/categories/filter/':
            expect(q['c'], 'doujin_chinese');
            expect(q['o'], 'mv_w');
            return {'total': 0, 'content': []};
          case '/serialization/':
            expect(q['date'], '3');
            expect(q['type'], 'hanman');
            expect(q['page'], '2');
            return {'total': 0, 'list': []};
          case '/week/filter/':
            expect(q['page'], '1');
            expect(q['id'], '9');
            return {'list': []};
          default:
            throw StateError('Unexpected path');
        }
      });
      addTearDown(api.close);
      expect((await api.latest(2)).more, false);
      await api.search(
        '作者',
        1,
        options: const SearchOptions(
          sort: 'tf',
          type: 'author',
          year: '2025',
          month: '7',
        ),
      );
      await api.category('doujin_chinese', 1, sort: 'mv_w');
      await api.serialization(3, 'hanman', 2);
      expect((await api.week('9', 'manga', 2)).more, false);
    },
  );
  test(
    'JM direct IDs accept bare digits and an optional JM prefix, and history persists in most-recent order',
    () async {
      expect(SearchOptions.directId('123'), '123');
      expect(SearchOptions.directId(' 123456 '), '123456');
      expect(SearchOptions.directId('00123'), '123');
      expect(SearchOptions.directId('jm123'), '123');
      expect(SearchOptions.directId('JM123'), '123');
      expect(SearchOptions.directId('１２３'), '123');
      expect(SearchOptions.directId('JM１２３'), '123');
      expect(SearchOptions.directId('abc123'), isNull);
      expect(SearchOptions.directId('123 title'), isNull);
      expect(SearchOptions.directId('abcJM123'), isNull);
      expect(SearchOptions.directId('JM123 title'), isNull);
      expect(SearchOptions.directId('12.3'), isNull);
      expect(SearchOptions.directId('１２３ title'), isNull);
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      await store.rememberSearch('A');
      await store.rememberSearch('B');
      await store.rememberSearch('A');
      expect(store.searchHistory, ['A', 'B']);
      await store.clearSearchHistory();
      expect(store.searchHistory, isEmpty);
    },
  );
  testWidgets('home renders distinct sections and opens their complete list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor(
        (_) => [
          {'title': '本周推荐', 'type': 'promote', 'id': 1, 'content': []},
          {'title': '连载更新', 'type': 'promote', 'id': 2, 'content': []},
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiscoveryScreen(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本周推荐'), findsOneWidget);
    expect(find.text('连载更新'), findsOneWidget);
    await tester.tap(find.text('查看全部').first);
    await tester.pumpAndSettle();
    expect(find.text('本周推荐'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
