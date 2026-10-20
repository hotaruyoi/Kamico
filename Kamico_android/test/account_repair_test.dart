import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/platform_files.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/account.dart';
import 'package:jm_mobile/ui/comment_editor.dart';
import 'package:jm_mobile/ui/comic_browser.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/ui/settings.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  testWidgets(
    'failed comment stays editable and draft reopens for the same recipient; success clears only its draft',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var sends = 0;
      final api =
          apiFor((_) {
              sends++;
              if (sends == 1) throw const ApiException('模拟失败');
              return {'msg': 'ok', 'err': ''};
            })
            ..token = 'fixture'
            ..userProfile = {'uid': '42'};
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: api,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CommentEditor(
                    session: session,
                    aid: '1',
                    reply: '2',
                    recipient: 'Reader',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('回复 @Reader'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '第一行\n第二行');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.textContaining('草稿已保留'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '第一行\n第二行',
      );
      await tester.tap(find.text('保存草稿并关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '第一行\n第二行',
      );
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentEditor), findsNothing);
      expect(
        session.store.preferences.getString('comment_draft:42:1:2'),
        isNull,
      );
      expect(sends, 2);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets('one comment with known total cannot request a second page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor(
        (_) => {
          'total': 1,
          'list': [
            {'CID': '1', 'content': 'One'},
          ],
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CommentsScreen(session: session, id: '1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('加载更多评论'), findsNothing);
    expect(find.text('已显示全部评论'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  test(
    'private reading keeps old history and does not persist a new position',
    () async {
      SharedPreferences.setMockInitialValues({'privacy_no_history': true});
      final store = LocalStore(await SharedPreferences.getInstance());
      const comic = Comic(id: '1', title: 'One');
      await store.saveProgress(
        const ReadingProgress(comic: comic, chapterId: '2', page: 1),
      );
      final session = AppSession(store, client: apiFor((_) => []));
      session.progress(
        const ReadingProgress(comic: comic, chapterId: '2', page: 9),
      );
      await session.savedProgress;
      expect(store.history.single.page, 1);
      session.dispose();
    },
  );
  testWidgets(
    'wide browser switches detail in place and preserves the selected comic when narrowed',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final ids = <String>[];
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((r) {
          final id = r.url.queryParameters['id']!;
          ids.add(id);
          return {'id': id, 'name': 'Comic $id'};
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ComicBrowser(
            session: session,
            selected: const Comic(id: '1', title: 'One'),
            items: const [Comic(id: '2', title: 'Two')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Two'));
      await tester.pumpAndSettle();
      expect(ids.last, '2');
      expect(
        tester.widget<DetailScreen>(find.byType(DetailScreen)).comic.id,
        '2',
      );
      expect(find.byType(VerticalDivider), findsOneWidget);
      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpAndSettle();
      expect(find.byType(VerticalDivider), findsNothing);
      expect(
        tester.widget<DetailScreen>(find.byType(DetailScreen)).comic.id,
        '2',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'browser failure leaves a persistent copyable registration link and return action',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformFiles.channel,
            (_) async => throw PlatformException(code: 'browser_missing'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(PlatformFiles.channel, null),
      );
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) => []),
      );
      await tester.pumpWidget(MaterialApp(home: LoginScreen(session: session)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('注册账号'));
      await tester.tap(find.text('注册账号'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      await tester.tap(find.text('返回登录'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
