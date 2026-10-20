import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'offline reader turns pages and records progress without network',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('jm_reader_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      final bytes = img.encodePng(img.Image(width: 2, height: 2));
      for (var index = 0; index < 2; index++) {
        File('${root.path}/$index.img').writeAsBytesSync(bytes);
      }
      SharedPreferences.setMockInitialValues({'reader_layout': 'pages'});
      var requests = 0;
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: JmClient(
          config: const ApiConfig(),
          transport: MockClient((_) async {
            requests++;
            throw http.ClientException('Offline');
          }),
        ),
      );
      const comic = Comic(id: '1', title: 'Offline Book');
      const chapter = Chapter(id: '10', title: 'Offline chapter');
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            session: session,
            comic: comic,
            chapter: chapter,
            offline: OfflineChapter(
              comic: comic,
              chapter: chapter,
              folder: root.path,
              count: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(session.store.history.single.page, 1);
      expect(requests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'mobile shell navigates settings, history, login and API error retry',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: JmClient(
          config: const ApiConfig(),
          transport: MockClient(
            (_) async => http.Response(
              jsonEncode({'code': 403, 'message': '测试线路不可用'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
      );
      await tester.pumpWidget(JmApp(session: session));
      await tester.pumpAndSettle();
      expect(find.text('测试线路不可用'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
      expect(find.text('阅读后会在这里保留进度'), findsOneWidget);
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('云端').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录后查看收藏'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      expect(find.text('请输入账号和密码'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('连接设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
