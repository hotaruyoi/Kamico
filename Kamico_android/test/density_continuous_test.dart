import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/domain/reader_options.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/discovery.dart';
import 'package:jm_mobile/ui/reader.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  testWidgets('在线章节的已缓存图片也按原比例无缝连接', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('jm_online_strip_');
    addTearDown(() => root.deleteSync(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => root.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({
      'reader_layout': ReaderMode.vertical.name,
    });
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor(
        (_) => {
          'id': '1',
          'scramble_id': 0,
          'images': [
            for (var i = 0; i < 3; i++)
              {'page': i, 'image': 'https://example.invalid/$i.png'},
          ],
        },
      ),
    );
    Directory('${root.path}/reader_cache').createSync();
    for (final entry in [120, 200, 1000].indexed) {
      final key = md5.convert(
        utf8.encode(
          '${session.api.config.imageHost}:1:0:/media/photos/1/${entry.$1}.png',
        ),
      );
      File('${root.path}/reader_cache/$key.png').writeAsBytesSync(
        img.encodePng(img.Image(width: 400, height: entry.$2)),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          session: session,
          comic: const Comic(id: '1', title: 'book'),
          chapter: const Chapter(id: '1', title: 'chapter'),
        ),
      ),
    );
    for (var attempt = 0; attempt < 60; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final ready = find
          .byType(RawImage)
          .evaluate()
          .map((e) => e.renderObject)
          .whereType<RenderImage>()
          .where((r) => r.image != null)
          .length;
      if (ready >= 3) break;
    }
    final images = find.byType(Image);
    expect(images, findsNWidgets(3));
    final first = tester.getRect(images.at(0)),
        second = tester.getRect(images.at(1));
    expect(first.height, closeTo(120, .01));
    expect(second.height, closeTo(200, .01));
    expect(second.top - first.bottom, closeTo(0, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('所有卡片档位在窄屏、平板与大字体下保持可读且无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor(
        (_) => [
          {
            'title': '推荐',
            'type': 'promote',
            'content': [
              for (var i = 0; i < 12; i++)
                {
                  'id': '$i',
                  'name': '较长标题用于检查小卡片的文字换行 $i',
                  'author': ['较长的作者名称'],
                },
            ],
          },
        ],
      ),
    );
    await session.setAppearance('scale', 1.4);
    await session.setAppearance('lines', 4);
    for (final width in [320.0, 390.0, 600.0, 900.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final density in ['large', 'medium', 'compact']) {
        await session.setAppearance('card_density', density);
        await tester.pumpWidget(JmApp(session: session));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width $density 1.4x');
      }
    }
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  test('小卡片按可用宽度响应排布，常见手机达到 4–5 列', () async {
    SharedPreferences.setMockInitialValues({
      'appearance': jsonEncode({'card_density': 'compact'}),
    });
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor((_) => []),
    );
    addTearDown(session.dispose);
    for (final entry in {
      320.0: 4,
      360.0: 4,
      390.0: 5,
      430.0: 5,
      600.0: 7,
      900.0: 11,
    }.entries) {
      final delegate = comicGridDelegate(session, entry.key - 24);
      expect(
        delegate.crossAxisCount,
        entry.value,
        reason: 'window=${entry.key}',
      );
    }
  });
  testWidgets('首页直接选择卡片密度并记住设置', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor(
        (_) => [
          {
            'title': '推荐',
            'type': 'promote',
            'content': [
              for (var i = 0; i < 12; i++)
                {
                  'id': '$i',
                  'name': '标题 $i',
                  'author': ['作者'],
                },
            ],
          },
        ],
      ),
    );
    await tester.pumpWidget(JmApp(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('卡片大小'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小卡片'));
    await tester.pumpAndSettle();
    expect(session.appearance['card_density'], 'compact');
    final delegate =
        tester.widget<SliverGrid>(find.byType(SliverGrid).first).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 5);
    expect(session.store.readMap('appearance')['card_density'], 'compact');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('竖向连续阅读按原比例撑开图片，相邻图片零间隔', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('jm_continuous_gap_');
    addTearDown(() => root.deleteSync(recursive: true));
    for (final entry in [120, 200, 1000].indexed) {
      File('${root.path}/${entry.$1}.img').writeAsBytesSync(
        img.encodePng(img.Image(width: 400, height: entry.$2)),
      );
    }
    SharedPreferences.setMockInitialValues({
      'reader_layout': ReaderMode.vertical.name,
    });
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor((_) {
        throw StateError('unexpected network');
      }),
    );
    const comic = Comic(id: '1', title: 'book'),
        chapter = Chapter(id: '1', title: 'chapter');
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
    final startingTop = tester.getRect(find.byType(Image).first).top;
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    final images = find.byType(Image);
    expect(images, findsAtLeastNWidgets(2));
    final first = tester.getRect(images.at(0)),
        second = tester.getRect(images.at(1));
    expect(
      first.top,
      lessThan(startingTop),
      reason: 'one-finger vertical scrolling must still work',
    );
    expect(
      second.top - first.bottom,
      closeTo(0, .01),
      reason: 'image gap should be zero',
    );
    expect(first.width, closeTo(400, .01));
    expect(first.height, closeTo(120, .01));
    expect(second.width, closeTo(400, .01));
    expect(second.height, closeTo(200, .01));
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
