import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/platform_files.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/domain/reader_options.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/reader.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  testWidgets(
    'reader hides and restores chrome, jumps precisely and stops auto at chapter end',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('jm_controls_');
      addTearDown(() => root.deleteSync(recursive: true));
      final bytes = img.encodePng(img.Image(width: 20, height: 60));
      for (var i = 0; i < 3; i++) {
        File('${root.path}/$i.img').writeAsBytesSync(bytes);
      }
      SharedPreferences.setMockInitialValues({
        'reader_seconds': 2,
        'reader_layout': 'pages',
      });
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) => throw StateError('unexpected network')),
      );
      const comic = Comic(id: '1', title: 'One'),
          chapter = Chapter(id: '10', title: 'Chapter');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() async {
        for (var i = 0; i < 3; i++) {
          await precacheImage(
            FileImage(File('${root.path}/$i.img')),
            tester.element(find.byType(SizedBox).first),
          );
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            session: session,
            comic: comic,
            chapter: chapter,
            chapters: const [
              chapter,
              Chapter(id: '11', title: 'Next'),
            ],
            offline: OfflineChapter(
              comic: comic,
              chapter: chapter,
              folder: root.path,
              count: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RawImage).first);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      final surface = find.byKey(const ValueKey('reader-tap-surface'));
      final bounds = tester.getRect(surface);
      await tester.tapAt(bounds.topLeft + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.tapAt(bounds.center);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      await tester.tap(find.text('1/3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('继续下一章'), findsOneWidget);
      await tester.tap(find.byTooltip('自动翻页'));
      await tester.pump();
      expect(find.textContaining('自动阅读中'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('已到章末，自动阅读停止'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      session.dispose();
    },
  );
  for (final mode in ReaderMode.values) {
    testWidgets('${mode.name} renders an offline chapter without network', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('jm_mode_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      final bytes = img.encodePng(img.Image(width: 20, height: 60));
      for (var i = 0; i < 3; i++) {
        File('${root.path}/$i.img').writeAsBytesSync(bytes);
      }
      SharedPreferences.setMockInitialValues({'reader_layout': mode.name});
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) {
          throw StateError('unexpected network');
        }),
      );
      const comic = Comic(id: '1', title: 'One'),
          chapter = Chapter(id: '10', title: 'Chapter');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() async {
        for (var index = 0; index < 3; index++) {
          await precacheImage(
            FileImage(File('${root.path}/$index.img')),
            tester.element(find.byType(SizedBox).first),
          );
        }
      });
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
              count: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(
        find.text('2/3'),
        findsOneWidget,
        reason:
            'Recorded page: ${session.store.history.single.page}; labels: ${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).where((e) => e?.contains("/3") == true).join(",")}',
      );
      expect(tester.takeException(), isNull);
      final controller = mode == ReaderMode.vertical
          ? null
          : tester.widget<PageView>(find.byType(PageView)).controller;
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(mode.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode.label));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      if (controller != null) {
        expect(
          identical(
            tester.widget<PageView>(find.byType(PageView)).controller,
            controller,
          ),
          isTrue,
          reason:
              'Opening settings and keeping the same mode must not recreate the reader controller',
        );
      }
      if (mode != ReaderMode.vertical) {
        await tester.drag(
          find.byType(PageView),
          Offset(mode.reversed ? 550 : -550, 0),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('3/3'),
          findsOneWidget,
          reason: 'The advertised finger direction must advance the page',
        );
      }
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  }
  test(
    'platform export passes image bytes and detected MIME without real sharing',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformFiles.channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(PlatformFiles.channel, null),
      );
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 1, height: 1)),
      );
      expect(await PlatformFiles.image('saveImage', png, 'page'), true);
      expect(calls.single.arguments['mime'], 'image/png');
      expect(calls.single.arguments['bytes'], png);
    },
  );
}
