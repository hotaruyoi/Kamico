import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/domain/reader_options.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/reader.dart';

import 'package:jm_mobile/ui/reading_navigation.dart';
import 'discovery_test.dart' show apiFor, response;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'old progress migrates and within-image fraction survives serialization',
    () {
      const comic = Comic(id: '1', title: 'One');
      final old = ReadingProgress.fromJson({
        'comic': comic.toJson(),
        'chapterId': '2',
        'page': 3,
      });
      expect(old.fraction, 0);
      final next = ReadingProgress(
        comic: comic,
        chapterId: '2',
        page: 3,
        fraction: .45,
      );
      expect(ReadingProgress.fromJson(next.toJson()).fraction, .45);
      expect(
        const AppTextScaler(TextScaler.linear(2), 1.2).scale(14),
        closeTo(33.6, .001),
      );
    },
  );
  test(
    'expired authenticated requests invalidate once without replaying POST; stale tokens cannot log out new sessions',
    () async {
      var requests = 0;
      final api = JmClient(
        config: const ApiConfig(),
        transport: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode({'code': 401}), 200);
        }),
      );
      SharedPreferences.setMockInitialValues({});
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: api,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null,
          );
      api.token = 'expired';
      await expectLater(
        api.request('/favorite', form: {'aid': '1'}),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 1);
      expect(session.loggedIn, false);
      expect(session.authExpired, true);
      api.token = 'new';
      api.onUnauthorized!('expired');
      expect(api.token, 'new');
      session.dispose();
    },
  );
  test(
    'a late rejection of the old token cannot invalidate login while secure storage is writing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final oldResponse = Completer<http.Response>(),
          saving = Completer<void>(),
          saved = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              if (call.method == 'write') {
                saving.complete();
                await saved.future;
              }
              return null;
            },
          );
      final api = JmClient(
        config: const ApiConfig(),
        now: () => 1700000000,
        transport: MockClient(
          (request) async => request.url.path == '/login/'
              ? response({'jwttoken': 'new', 'uid': '42'})
              : oldResponse.future,
        ),
      )..token = 'old';
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: api,
      );
      final old = api.request('/watch_list');
      final login = session.login('user', 'password');
      await saving.future;
      oldResponse.complete(http.Response('{"code":401}', 200));
      await expectLater(old, throwsA(isA<ApiException>()));
      saved.complete();
      await login;
      expect(api.token, 'new');
      expect(api.userProfile?['uid'], '42');
      expect(session.authExpired, false);
      session.dispose();
    },
  );
  testWidgets(
    'tab switching retains a visited search field and does not recreate discovery request',
    (tester) async {
      var homeRequests = 0;
      SharedPreferences.setMockInitialValues({});
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((request) {
          if (request.url.path == '/promote/') {
            homeRequests++;
            return [];
          }
          return {'list': [], 'total': 0};
        }),
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(session: session)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('历史').last);
      await tester.pumpAndSettle();
      final field = find.byType(SearchBar);
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        '保留筛选',
      );
      await tester.tap(find.text('发现').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('历史').last);
      await tester.pumpAndSettle();
      expect(find.text('保留筛选'), findsOneWidget);
      expect(homeRequests, 1);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  for (final mode in [ReaderMode.vertical]) {
    testWidgets(
      '$mode long image restores a measured within-image position and saves scrolling',
      (tester) async {
        final root = Directory.systemTemp.createTempSync('jm_progress_');
        addTearDown(() => root.deleteSync(recursive: true));
        final file = File(
          '${root.path}/0.img',
        )..writeAsBytesSync(img.encodePng(img.Image(width: 400, height: 2400)));
        SharedPreferences.setMockInitialValues({'reader_layout': mode.name});
        final session = AppSession(
          LocalStore(await SharedPreferences.getInstance()),
          client: apiFor((_) => throw StateError('network')),
        );
        const comic = Comic(id: '1', title: 'One');
        const chapter = Chapter(id: '2', title: 'Two');
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.runAsync(
          () => precacheImage(
            FileImage(file),
            tester.element(find.byType(SizedBox).first),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(
              session: session,
              comic: comic,
              chapter: chapter,
              initialFraction: .4,
              offline: OfflineChapter(
                comic: comic,
                chapter: chapter,
                folder: root.path,
                count: 1,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byType(RawImage));
        final top = tester.getRect(find.byType(InteractiveViewer).first).top;
        expect((top - rect.top) / rect.height, closeTo(.4, .01));
        await tester.drag(
          find.byType(InteractiveViewer).first,
          const Offset(0, -150),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        expect(session.store.history.single.fraction, greaterThan(.4));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        session.dispose();
      },
    );
  }
  testWidgets(
    'a shared chapter opener uses completed offline files without chapter API calls',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('jm_resolve_');
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await root.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => root.path,
          );
      SharedPreferences.setMockInitialValues({});
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) => throw StateError('unexpected network')),
      );
      const comic = Comic(id: '1', title: 'One'),
          chapter = Chapter(id: '2', title: 'Two');
      final repository = DownloadRepository(
        fetchImage: (_, _) async =>
            img.encodePng(img.Image(width: 20, height: 20)),
        root: () async => root,
      );
      await tester.runAsync(
        () => repository.save(
          comic,
          chapter,
          const ReaderChapter(
            id: '2',
            scrambleId: 0,
            pages: [ReaderPage(path: '', name: '0')],
          ),
          (_, _) {},
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() async {
        await repository.save(
          comic,
          const Chapter(id: '3', title: 'Three'),
          const ReaderChapter(
            id: '3',
            scrambleId: 0,
            pages: [ReaderPage(path: '', name: '0')],
          ),
          (_, _) {},
        );
        for (final local in await repository.list()) {
          await precacheImage(
            FileImage(local.page(0)),
            tester.element(find.byType(SizedBox).first),
          );
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openChapter(
                context,
                session,
                comic,
                chapter,
                chapters: const [
                  chapter,
                  Chapter(id: '3', title: 'Three'),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).offline,
        isNotNull,
      );
      await tester.tap(find.text('继续下一章'));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await session.savedProgress;
      expect(
        session.store.history.single.chapterId,
        '3',
        reason:
            'Disposing the previous reader must not overwrite the new chapter progress',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      session.dispose();
    },
  );
}
