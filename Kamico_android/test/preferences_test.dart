import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/app_log.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/preferences.dart';
import 'package:jm_mobile/ui/translations.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('语言支持完整句子和参数化文案，保留未翻译内容', () async {
    await AppTranslations.load();
    expect(
      AppTranslations.translate('外观与语言', const Locale('en')),
      'Appearance and language',
    );
    expect(
      AppTranslations.translate('第 2 页 · 共 80 本', const Locale('en')),
      'Page 2 · 80 comics',
    );
    expect(AppTranslations.translate('字体缩放', const Locale('zh', 'TW')), '字體縮放');
    expect(AppTranslations.translate('未知漫画标题', const Locale('en')), '未知漫画标题');
  });
  test('日志数量上限、持久化和清空', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final logs = AppLog(store);
    for (var i = 0; i < 310; i++) {
      logs.record('API', 'GET /album', status: 200, milliseconds: i);
    }
    await logs.saved;
    expect(logs.entries.length, 300);
    expect(logs.entries.first['ms'], 10);
    final restored = AppLog(store);
    expect(restored.entries.length, 300);
    await logs.clear();
    expect(store.readMap('logs')['items'], isEmpty);
    logs.dispose();
    restored.dispose();
  });
  test('API 日志排除账号口令、响应正文及查询内容', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final session = AppSession(
      store,
      client: apiFor(
        (r) => {
          'jwttoken': 'private-token',
          'uid': '42',
          'username': 'private-user',
        },
      ),
    );
    await session.api.login('private-user', 'private-password');
    await session.logs.saved;
    final text = session.logs.export(session.logs.entries);
    expect(text, contains('POST /login'));
    expect(text, contains('status=200'));
    for (final secret in [
      'private-token',
      'private-user',
      'private-password',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    session.dispose();
  });
  testWidgets('主题与语言即时生效，较大字体设置页没有布局异常', (tester) async {
    await tester.runAsync(AppTranslations.load);
    SharedPreferences.setMockInitialValues({});
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor((r) => []),
    );
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(JmApp(session: session));
    await tester.pumpAndSettle();
    await session.setAppearance('language', 'en');
    await session.setAppearance('theme', 'dark');
    await session.setAppearance('scale', 1.4);
    await tester.pumpAndSettle();
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('My'), findsOneWidget);
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.themeMode, ThemeMode.dark);
    final nav = Navigator.of(tester.element(find.byType(NavigationBar)));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => AppearanceScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Appearance and language'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await session.setAppearance('language', 'zh_TW');
    await tester.pumpAndSettle();
    expect(find.text('外觀與語言'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
