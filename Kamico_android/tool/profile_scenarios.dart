// Synthetic device harness, compiled only when explicitly passed as --target.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/pic_client.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/cover_image_provider.dart';
import 'package:jm_mobile/ui/design_system.dart';
import 'package:jm_mobile/ui/downloads.dart';
import 'package:jm_mobile/ui/reader.dart';
import 'package:jm_mobile/ui/translations.dart';

http.Client blockedTransport() => MockClient(
  (_) async => http.Response('{"code":403,"message":"Offline fixture"}', 200),
);

class ProfileJm extends JmClient {
  ProfileJm(this.items)
    : super(config: const ApiConfig(), transport: blockedTransport());
  final List<Comic> items;
  @override
  Future<List<HomeSection>> homeSections() async => [
    for (var group = 0; group < 8; group++)
      HomeSection(
        title: '合成分组 ${group + 1}',
        type: '',
        id: '$group',
        slug: '',
        filter: '',
        items: items.skip(group * 12).take(12).toList(),
      ),
  ];
}

class ProfileDownloads extends DownloadRepository {
  ProfileDownloads(this.entries)
    : super(fetchImage: (_, _) async => throw StateError('Offline fixture'));
  final List<OfflineChapter> entries;
  @override
  Future<List<OfflineChapter>> list() async => entries;
  @override
  Future<int> get bytes async => 104857600;
}

Map<String, Object?> readerLayout() {
  final boxes = <Map<String, Object?>>[];
  final scrolls = <Map<String, Object?>>[];
  Map<String, double>? surface;
  Map<String, double> rect(RenderBox box) {
    final offset = box.localToGlobal(Offset.zero);
    return {
      'x': offset.dx,
      'y': offset.dy,
      'width': box.size.width,
      'height': box.size.height,
    };
  }

  void visit(Element element) {
    final widget = element.widget;
    if (widget.key == const ValueKey('reader-tap-surface')) {
      surface = rect(element.findRenderObject()! as RenderBox);
    }
    if (widget is RawImage) {
      final render = element.findRenderObject();
      if (render is RenderBox && render.hasSize && render.size.height > 30) {
        boxes.add({'element': identityHashCode(element), ...rect(render)});
      }
    }
    if (element is StatefulElement && element.state is ScrollableState) {
      final position = (element.state as ScrollableState).position;
      scrolls.add({
        'state': identityHashCode(element.state),
        'pixels': position.pixels,
        'viewport': position.viewportDimension,
      });
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  final view = ui.PlatformDispatcher.instance.views.first;
  return {
    'surface': surface,
    'images': boxes,
    'scrolls': scrolls,
    'physicalWidth': view.physicalSize.width,
    'physicalHeight': view.physicalSize.height,
    'paddingTop': view.padding.top,
    'paddingBottom': view.padding.bottom,
    'viewPaddingTop': view.viewPadding.top,
    'viewPaddingBottom': view.viewPadding.bottom,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureImageCaching();
  await AppTranslations.load();
  // In-memory preferences ensure no existing debug credentials or progress are read.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'appearance': jsonEncode({'theme': 'dark'}),
    'reader_layout': 'vertical',
  });
  final picture = img.Image(width: 720, height: 1100);
  img.fill(picture, color: img.ColorRgb8(232, 214, 239));
  for (var line = 0; line < 16; line++) {
    img.fillRect(
      picture,
      x1: 25,
      y1: 25 + line * 65,
      x2: 695,
      y2: 65 + line * 65,
      color: img.ColorRgb8(85 + line * 7, 100, 155 + line * 3),
    );
  }
  final png = img.encodePng(picture);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response.headers.contentType = ContentType('image', 'png');
    request.response.add(png);
    unawaited(request.response.close());
  });
  final folder = await Directory(
    '${(await getTemporaryDirectory()).path}/kamico_profile_1_0_1',
  ).create(recursive: true);
  for (var page = 0; page < 20; page++) {
    await File('${folder.path}/$page.img').writeAsBytes(png);
  }
  final items = [
    for (var i = 0; i < 96; i++)
      Comic(
        id: '${i + 1}',
        title: '合成作品 ${(i + 1).toString().padLeft(3, '0')}',
        authors: const ['本地样本'],
        cover: 'http://127.0.0.1:${server.port}/$i.png',
      ),
  ];
  final entries = [
    for (final comic in items)
      OfflineChapter(
        comic: comic,
        chapter: const Chapter(id: 'local', title: '离线章节'),
        folder: folder.path,
        count: 20,
      ),
  ];
  final session = AppSession(
    LocalStore(await SharedPreferences.getInstance()),
    client: ProfileJm(items),
    picClient: PicClient(transport: blockedTransport()),
    repository: ProfileDownloads(entries),
  );
  final scene = ValueNotifier('home');
  final samples = <Map<String, double>>[];
  var collecting = false;
  WidgetsBinding.instance.addTimingsCallback((timings) {
    if (!collecting) return;
    for (final timing in timings) {
      samples.add({
        'buildMs': timing.buildDuration.inMicroseconds / 1000,
        'rasterMs': timing.rasterDuration.inMicroseconds / 1000,
        'totalMs': timing.totalSpan.inMicroseconds / 1000,
      });
    }
  });
  dev.registerExtension('ext.kamico.profile', (_, params) async {
    final op = params['op'];
    if (op == 'scene') scene.value = params['name']!;
    if (op == 'start') {
      samples.clear();
      collecting = true;
    }
    if (op == 'stop') collecting = false;
    return dev.ServiceExtensionResponse.result(
      jsonEncode({
        'scene': scene.value,
        'mode': kProfileMode ? 'profile' : 'debug',
        'refreshHz':
            ui.PlatformDispatcher.instance.views.first.display.refreshRate,
        if (op == 'stop') 'frames': samples,
        if (op == 'snapshot') 'layout': readerLayout(),
      }),
    );
  });
  runApp(
    ValueListenableBuilder(
      valueListenable: scene,
      builder: (context, value, _) => value == 'home'
          ? JmApp(key: ValueKey(value), session: session)
          : MaterialApp(
              key: ValueKey(value),
              debugShowCheckedModeBanner: false,
              theme: AppDesign.theme(
                const Color(0xff607db8),
                Brightness.dark,
                null,
              ),
              home: value == 'reader'
                  ? ReaderScreen(
                      session: session,
                      comic: items.first,
                      chapter: entries.first.chapter,
                      offline: entries.first,
                    )
                  : Scaffold(
                      appBar: AppBar(title: const Text('离线下载')),
                      body: DownloadScreen(
                        session: session,
                        initialLibrary: true,
                      ),
                    ),
            ),
    ),
  );
}
