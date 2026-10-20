import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/platform_files.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/downloads.dart';
import 'package:jm_mobile/ui/library_layout.dart';
import 'package:jm_mobile/ui/reader.dart';
import 'multi_source_test.dart' show FixtureJm, FixturePic;

class OfflineFixture extends DownloadRepository {
  OfflineFixture() : super(fetchImage: (_, _) async => Uint8List(0));
  @override
  Future<List<OfflineChapter>> list() async => const [
    OfflineChapter(
      comic: Comic(id: 'fixture', title: 'Synthetic offline book'),
      chapter: Chapter(id: 'one', title: 'Chapter one'),
      folder: 'synthetic',
      count: 2,
    ),
  ];
  @override
  Future<int> get bytes async => 128;
}

void main() {
  final systemBars = <bool>[];
  setUp(() {
    systemBars.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformFiles.channel, (call) async {
          if (call.method == 'readerSystemBars') {
            systemBars.add((call.arguments as Map)['visible'] as bool);
          }
          return call.method == 'storageInfo' ? {'available': 1048576} : null;
        });
  });

  testWidgets(
    'mid-page reader keeps geometry and uses stable native bar visibility',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('kamico_reader_bars_');
      addTearDown(() => root.deleteSync(recursive: true));
      final bytes = img.encodePng(img.Image(width: 120, height: 300));
      for (var i = 0; i < 3; i++) {
        File('${root.path}/$i.img').writeAsBytesSync(bytes);
      }
      final app = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: FixtureJm(),
        picClient: FixturePic(),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() async {
        for (var i = 0; i < 3; i++) {
          await precacheImage(
            FileImage(File('${root.path}/$i.img')),
            tester.element(find.byType(SizedBox).first),
          );
        }
      });
      const comic = Comic(id: 'local', title: 'Synthetic reader');
      const chapter = Chapter(id: 'local', title: 'Chapter');
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            session: app,
            comic: comic,
            chapter: chapter,
            initialFraction: .35,
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
      final surface = find.byKey(const ValueKey('reader-tap-surface'));
      final bounds = tester.getRect(surface);
      final image = tester.getRect(find.byType(RawImage).first);
      await tester.tapAt(bounds.center);
      await tester.pumpAndSettle();
      expect(systemBars, contains(false));
      expect(tester.getRect(surface), bounds);
      expect(tester.getRect(find.byType(RawImage).first), image);
      await tester.tapAt(bounds.center);
      await tester.pumpAndSettle();
      expect(systemBars.last, true);
      expect(tester.getRect(find.byType(RawImage).first), image);
      await tester.pumpWidget(const SizedBox());
    },
  );
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformFiles.channel, null);
  });

  testWidgets(
    'offline selection stays visible, toggles and clears old choices',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: FixtureJm(),
        picClient: FixturePic(),
        repository: OfflineFixture(),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadScreen(session: app, initialLibrary: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(CustomScrollView));
      final tile = tester.element(find.byType(LibraryBookTile));
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(find.text('选择'), findsOneWidget);
      expect(tester.getRect(find.byType(CustomScrollView)), bounds);
      expect(tester.element(find.byType(LibraryBookTile)), same(tile));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('已选 1'), findsOneWidget);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(find.byType(LibrarySelectionBar), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      await tester.tap(find.text('完成选择'));
      await tester.pumpAndSettle();
      expect(find.text('选择'), findsOneWidget);
      expect(find.byType(LibrarySelectionBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('discovery title is bold and follows the selected source', (
    tester,
  ) async {
    final app = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: FixtureJm(),
      picClient: FixturePic(),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(JmApp(session: app));
    await tester.pumpAndSettle();
    expect(find.text('Kamico · JM'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Kamico · JM')).style?.fontWeight,
      FontWeight.bold,
    );
    await tester.tap(find.byType(ContentSourceButton));
    await tester.pumpAndSettle();
    expect(find.text('Kamico · Pic'), findsOneWidget);
    await tester.tap(find.byType(ContentSourceButton));
    await tester.pumpAndSettle();
    expect(find.text('Kamico · JM'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
