import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/ui/cover_image.dart';
import 'package:jm_mobile/ui/cover_image_provider.dart';
import 'discovery_test.dart' show apiFor, response;

Future<void> finishImage(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (PaintingBinding.instance.imageCache.pendingImageCount == 0 &&
        coverImageCache.pendingImageCount == 0) {
      return;
    }
  }
  fail('Synthetic image decode did not finish');
}

void expectSharedFrame(WidgetTester tester) {
  final cover = find.descendant(
    of: find.byKey(const ValueKey('detail-cover-metadata')),
    matching: find.byType(RawImage),
  );
  final background = find.descendant(
    of: find.byKey(const ValueKey('detail-shared-backdrop')),
    matching: find.byType(RawImage),
  );
  final image = tester.widget<RawImage>(cover).image;
  expect(image, isNotNull);
  expect(
    identical(image, tester.widget<RawImage>(background).image),
    isTrue,
    reason:
        'Both views must paint the same decoded frame in the same widget update',
  );
}

class _Images extends Fake implements HttpClient {
  _Images(this.bytes);
  final Uint8List bytes;
  final requests = <_Request>[];
  bool respond = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final request = _Request();
    requests.add(request);
    if (respond) request.result.complete(_Response(bytes));
    return request;
  }
}

class _Request extends Fake implements HttpClientRequest {
  final result = Completer<HttpClientResponse>();
  @override
  Future<HttpClientResponse> close() => result.future;
}

class _Response extends Fake implements HttpClientResponse {
  _Response(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('kamico_artwork_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    addTearDown(() async {
      debugNetworkImageHttpClientProvider = null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      coverImageCache.clear();
      coverImageCache.clearLiveImages();
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await root.delete(recursive: true);
    });
  });

  testWidgets('reader pages do not evict cached home and other detail covers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cache = PaintingBinding.instance.imageCache;
    final originalLimit = cache.maximumSizeBytes;
    cache.maximumSizeBytes = 2 * 1024 * 1024;
    addTearDown(() => cache.maximumSizeBytes = originalLimit);
    final images = _Images(
      Uint8List.fromList(img.encodePng(img.Image(width: 600, height: 800))),
    );
    debugNetworkImageHttpClientProvider = () => images;
    final store = LocalStore(await SharedPreferences.getInstance());
    await store.preferences.setString('reader_layout', 'pages');
    final session = AppSession(
      store,
      client: apiFor((_) => {'id': '2', 'name': 'Other cached book'}),
    );
    final url = '${session.api.config.imageHost}/media/albums/2_3x4.jpg';
    Widget home() => MaterialApp(
      home: Center(
        child: SizedBox(width: 100, height: 134, child: CoverImage(url: url)),
      ),
    );
    await tester.pumpWidget(home());
    await finishImage(tester);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          session: session,
          comic: const Comic(id: '2', title: 'Other cached book'),
        ),
      ),
    );
    await tester.pump();
    await finishImage(tester);
    expectSharedFrame(tester);
    await tester.pumpWidget(const SizedBox());
    final beforeReading = images.requests.length;
    late Directory pages;
    await tester.runAsync(() async {
      pages = await session.downloads.directory;
      final bytes = img.encodePng(img.Image(width: 320, height: 640));
      for (var i = 0; i < 3; i++) {
        await File('${pages.path}/$i.img').writeAsBytes(bytes);
      }
    });
    const readingComic = Comic(id: '1', title: 'Reading book');
    const chapter = Chapter(id: '10', title: 'Chapter 1');
    final offline = OfflineChapter(
      comic: readingComic,
      chapter: chapter,
      folder: pages.path,
      count: 3,
    );
    for (var page = 0; page < 3; page++) {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            key: ValueKey(page),
            session: session,
            comic: readingComic,
            chapter: chapter,
            initialPage: page,
            offline: offline,
            chapters: const [chapter],
          ),
        ),
      );
      await tester.pump();
      await finishImage(tester);
      expect(find.byType(RawImage), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.pumpWidget(home());
    await finishImage(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          session: session,
          comic: const Comic(id: '2', title: 'Other cached book'),
        ),
      ),
    );
    await tester.pump();
    await finishImage(tester);
    expectSharedFrame(tester);
    expect(
      images.requests.length,
      beforeReading,
      reason:
          'Reading another book must not force home and cached detail artwork to download again',
    );
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets(
    'expired details stay visible while refreshing and after a refresh error',
    (tester) async {
      var now = 1700000000, requests = 0;
      var refresh = Completer<http.Response>();
      final images = _Images(
        Uint8List.fromList(img.encodePng(img.Image(width: 60, height: 80))),
      );
      debugNetworkImageHttpClientProvider = () => images;
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: JmClient(
          config: const ApiConfig(),
          now: () => now,
          transport: MockClient((_) async {
            requests++;
            return requests == 1
                ? response({'id': '1', 'name': 'Saved details'})
                : refresh.future;
          }),
        ),
      );
      Widget screen() => MaterialApp(
        home: DetailScreen(
          session: session,
          comic: const Comic(id: '1', title: 'Saved details'),
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pump();
      await finishImage(tester);
      await tester.pumpWidget(const SizedBox());
      now += 300;
      await tester.pumpWidget(screen());
      await tester.pump();
      expect(
        find.text('Saved details'),
        findsOneWidget,
        reason:
            'Expiry must refresh in the background instead of hiding cached artwork and metadata',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expectSharedFrame(tester);
      expect(requests, 2);
      refresh.complete(http.Response('Synthetic failure', 400));
      await tester.pumpAndSettle();
      expect(find.text('Saved details'), findsOneWidget);
      expect(find.text('详情更新失败，显示上次内容'), findsOneWidget);
      refresh = Completer<http.Response>();
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.text('Saved details'), findsOneWidget);
      refresh.complete(
        response({'id': '1', 'name': 'Updated details'}, timestamp: now),
      );
      await tester.pumpAndSettle();
      expect(find.text('Updated details'), findsOneWidget);
      expect(find.text('详情更新失败，显示上次内容'), findsNothing);
      expect(images.requests.length, 1);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      debugNetworkImageHttpClientProvider = null;
    },
  );

  testWidgets(
    'cover reservation stays bounded and releases reusable images on memory pressure',
    (tester) async {
      final global = PaintingBinding.instance.imageCache;
      final oldBytes = global.maximumSizeBytes;
      final oldCount = coverImageCache.maximumSize;
      addTearDown(() {
        global.maximumSizeBytes = oldBytes;
        coverImageCache.maximumSize = oldCount;
      });
      configureImageCaching();
      expect(
        global.maximumSizeBytes + coverImageCache.maximumSizeBytes,
        100 * 1024 * 1024,
      );
      expect(coverImageCache.maximumSize, 96);
      coverImageCache.maximumSize = 2;
      final images = _Images(
        Uint8List.fromList(img.encodePng(img.Image(width: 60, height: 80))),
      );
      debugNetworkImageHttpClientProvider = () => images;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox).first);
      final providers = [
        for (var i = 0; i < 3; i++)
          CoverImageProvider('https://covers.example.test/$i.jpg', 128),
      ];
      for (final provider in providers) {
        await tester.runAsync(() => precacheImage(provider, context));
        await tester.pump();
      }
      expect(coverImageCache.currentSize, 2);
      expect(
        (await providers.first.obtainCacheStatus(
          configuration: ImageConfiguration.empty,
        ))?.keepAlive,
        false,
      );
      expect(
        (await providers.last.obtainCacheStatus(
          configuration: ImageConfiguration.empty,
        ))?.keepAlive,
        true,
      );
      tester.binding.handleMemoryPressure();
      expect(coverImageCache.currentSizeBytes, 0);
      expect(coverImageCache.currentSize, 0);
      await tester.pumpWidget(const SizedBox());
      debugNetworkImageHttpClientProvider = null;
    },
  );

  testWidgets(
    'cold image waits for detail metadata and both surfaces appear from one frame',
    (tester) async {
      final images = _Images(
        Uint8List.fromList(img.encodePng(img.Image(width: 60, height: 80))),
      )..respond = false;
      debugNetworkImageHttpClientProvider = () => images;
      final metadata = Completer<http.Response>();
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: JmClient(
          config: const ApiConfig(),
          now: () => 1700000000,
          transport: MockClient((_) => metadata.future),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(
            session: session,
            comic: const Comic(id: '1', title: 'Cold artwork'),
          ),
        ),
      );
      await tester.pump();
      expect(images.requests.length, 1);
      images.requests.single.result.complete(_Response(images.bytes));
      await finishImage(tester);
      final background = find.descendant(
        of: find.byKey(const ValueKey('detail-shared-backdrop')),
        matching: find.byType(RawImage),
      );
      expect(
        tester.widget<RawImage>(background).image,
        null,
        reason:
            'An early background must not appear alone while metadata still hides the portrait',
      );
      metadata.complete(response({'id': '1', 'name': 'Cold artwork'}));
      await tester.pumpAndSettle();
      expectSharedFrame(tester);
      expect(images.requests.length, 1);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      debugNetworkImageHttpClientProvider = null;
    },
  );

  testWidgets('one retry restores both images after a failed download', (
    tester,
  ) async {
    final images = _Images(
      Uint8List.fromList(img.encodePng(img.Image(width: 60, height: 80))),
    )..respond = false;
    debugNetworkImageHttpClientProvider = () => images;
    final session = AppSession(
      LocalStore(await SharedPreferences.getInstance()),
      client: apiFor((_) => {'id': '1', 'name': 'Retry artwork'}),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          session: session,
          comic: const Comic(id: '1', title: 'Retry artwork'),
        ),
      ),
    );
    await tester.pump();
    images.requests.single.result.completeError(
      const HttpException('Synthetic failure'),
    );
    await finishImage(tester);
    final retry = find.byTooltip('封面加载失败，点击重试');
    expect(retry, findsOneWidget);
    images.respond = true;
    await tester.tap(retry);
    await tester.pump();
    await finishImage(tester);
    expectSharedFrame(tester);
    expect(images.requests.length, 2);
    expect(retry, findsNothing);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets(
    'cached cover and background show the same ready frame without a second download',
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final images = _Images(
        Uint8List.fromList(img.encodePng(img.Image(width: 60, height: 80))),
      );
      debugNetworkImageHttpClientProvider = () => images;
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: apiFor((_) => {'id': '1', 'name': 'Synthetic artwork'}),
      );
      await session.api.detail('1');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final url = '${session.api.config.imageHost}/media/albums/1_3x4.jpg';
      await tester.runAsync(
        () => precacheImage(
          CoverImageProvider(url, 400),
          tester.element(find.byType(SizedBox).first),
        ),
      );
      expect(images.requests.length, 1);
      images.respond = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(
            session: session,
            comic: const Comic(id: '1', title: 'Synthetic artwork'),
          ),
        ),
      );
      await tester.pump();
      final cover = find.descendant(
        of: find.byKey(const ValueKey('detail-cover-metadata')),
        matching: find.byType(RawImage),
      );
      final background = find.descendant(
        of: find.byKey(const ValueKey('detail-shared-backdrop')),
        matching: find.byType(RawImage),
      );
      final coverFrame = tester.widget<RawImage>(cover).image;
      final backgroundFrame = tester.widget<RawImage>(background).image;
      expect(coverFrame, isNotNull);
      expect(
        backgroundFrame,
        isNotNull,
        reason:
            'A ready cover must not leave its blurred background waiting on a separate image load',
      );
      expect(
        images.requests.length,
        1,
        reason: 'Both surfaces must reuse the decoded cover',
      );
      expectSharedFrame(tester);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      debugNetworkImageHttpClientProvider = null;
    },
  );
}
