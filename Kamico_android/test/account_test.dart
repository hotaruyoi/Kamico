import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  testWidgets('购买必须确认，取消不提交，成功后显示已购买', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var purchases = 0;
    final api = apiFor((r) {
      if (r.url.path == '/album/') {
        return {
          'id': '123',
          'name': '测试漫画',
          'price': 10,
          'purchased': purchases > 0,
        };
      }
      if (r.url.path == '/coin_buy_comics/') {
        purchases++;
        return {'status': 'ok', 'msg': '购买成功'};
      }
      return <String, dynamic>{};
    })..token = 'fixture';
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: api,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          session: session,
          comic: const Comic(id: '123', title: '测试漫画'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('购买 · 10 金币'));
    await tester.pumpAndSettle();
    expect(purchases, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(purchases, 0);
    await tester.tap(find.text('购买 · 10 金币'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(purchases, 1);
    expect(find.text('已购买'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  test('账号操作遵循原 API 字段且登录资料不含令牌', () async {
    final requests = <String, Map<String, String>>{};
    final api = apiFor((r) {
      requests[r.url.path] = r.method == 'POST'
          ? Uri.splitQueryString(r.body)
          : r.url.queryParameters;
      if (r.url.path == '/login/') {
        return {
          'jwttoken': 'secret',
          'uid': '42',
          'username': 'user',
          'password': 'bad',
          'coin': 12,
        };
      }
      if (r.url.path == '/forum/') return {'list': [], 'total': 0};
      if (r.url.path == '/daily/') return {'daily_id': 9};
      return {'status': 'ok', 'msg': 'ok'};
    });
    addTearDown(api.close);
    expect(await api.login('user', 'pass'), 'secret');
    expect(api.userProfile, {'uid': '42', 'username': 'user', 'coin': 12});
    await api.daily('42');
    expect(requests['/daily/']?['user_id'], '42');
    await api.sign('42', '9', date: '2026-10-01');
    expect(requests['/daily_chk/'], {
      'user_id': '42',
      'daily_id': '9',
      'date': '2026-10-01',
    });
    await api.purchase('123');
    expect(requests['/coin_buy_comics/'], {'id': '123'});
    await api.comments('123', 2);
    expect(requests['/forum/']?['mode'], 'manhua');
    await api.comments('', 1, uid: '42');
    expect(requests['/forum/']?['uid'], '42');
    await api.comment('123', 'hello', reply: '8');
    expect(requests['/comment/'], {
      'aid': '123',
      'comment': 'hello',
      'comment_id': '8',
    });
  });
}
