import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/jm_protocol.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fixtures generated independently with Node crypto AES-256-ECB and PKCS7.
const timestamp = 1700000000;
const searchFixture =
    '+h7/rswRTHQWleI9fm/KpQoMM+AhAglAfuaRs/MEP0+dV3VxSqD0fVTG3g2PS+0F4akg2DExoDqsiEknP6c9dYj1MVa/provQHeqxdzs2YAydpl3EkjZJctaFRltgsLDhO7h5IVP0KfFoATf8Fdc4xaJMDhQOWc54vltmm/YgR7SkA2awNbrP4uAkgrR4526';
const loginFixture = 'V22OBniUVBaKvaGX4Cbc6G47J6Ubx4U/EedMQsBYS5c=';
const emptyFixture = 'rCLU9Nj7dxLLggdVirR0XQ==';
http.Response encrypted(String data) =>
    http.Response(jsonEncode({'code': 200, 'data': data}), 200);
JmClient client(Future<http.Response> Function(http.Request) handler) =>
    JmClient(
      config: const ApiConfig(
        apiHosts: ['https://one.example', 'https://two.example'],
      ),
      transport: MockClient(handler),
      now: () => timestamp,
    );

void main() {
  test('request signature matches independently generated fixture', () {
    final headers = JmProtocol.headers(
      timestamp,
      const ApiConfig(),
      token: 'secret',
    );
    expect(headers['token'], '1c6fa345eea2e10d5a30880ec2a7e0b3');
    expect(headers['tokenparam'], '1700000000,2.1.11');
    expect(headers['authorization'], 'Bearer secret');
  });
  test('AES decodes Unicode JSON and mixed ID/author types', () {
    final data =
        JmProtocol.decode(
              searchFixture,
              timestamp,
              const ApiConfig().dataSecret,
            )
            as Json;
    final page = ComicPage.fromJson(data);
    expect(page.total, 2);
    expect(page.items.first.id, '101');
    expect(page.items.first.title, '测试标题');
    expect(page.items.first.authors, ['作者']);
    expect(page.items.last.authors, ['作者甲', '作者乙']);
  });
  test(
    'search sends query parameters, decrypts and parses through public interface',
    () async {
      final api = client((request) async {
        expect(request.url.path, '/search/');
        expect(request.url.queryParameters['search_query'], '测试 & 空格');
        expect(request.url.queryParameters['page'], '2');
        expect(request.headers['tokenparam'], '$timestamp,2.1.11');
        return encrypted(searchFixture);
      });
      addTearDown(api.close);
      expect((await api.search('测试 & 空格', 2)).items.length, 2);
    },
  );
  test(
    'login does not send stale bearer and form encoding preserves password',
    () async {
      final api = client((request) async {
        expect(request.method, 'POST');
        expect(request.headers['authorization'], isNull);
        expect(request.bodyFields, {'username': 'user', 'password': 'p&= +字'});
        return encrypted(loginFixture);
      })..token = 'old';
      addTearDown(api.close);
      expect(await api.login('user', 'p&= +字'), 'session-test');
    },
  );
  test('read requests fail over on connection failures', () async {
    final hosts = <String>[];
    final api = client((request) async {
      hosts.add(request.url.host);
      if (hosts.length == 1) throw http.ClientException('offline');
      return encrypted(emptyFixture);
    });
    addTearDown(api.close);
    expect(await api.home(), isEmpty);
    expect(hosts, ['one.example', 'two.example']);
  });
  test('timed out mutations are not replayed on another host', () async {
    var calls = 0;
    final api = client((request) async {
      calls++;
      throw TimeoutException('timeout');
    });
    addTearDown(api.close);
    await expectLater(api.toggleFavorite('1'), throwsA(isA<ApiException>()));
    expect(calls, 1);
  });
  test('business errors do not trigger failover', () async {
    var calls = 0;
    final api = client((request) async {
      calls++;
      return http.Response(
        '{"code":401,"message":"登录失效"}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(api.close);
    await expectLater(
      api.home(),
      throwsA(
        isA<ApiException>().having((e) => e.unauthorized, 'unauthorized', true),
      ),
    );
    expect(calls, 1);
  });
  test('wrong encryption keys surface a readable protocol error', () async {
    final api = client((_) async => encrypted(searchFixture));
    api.config = const ApiConfig(dataSecret: 'wrong');
    addTearDown(api.close);
    await expectLater(api.search('x', 1), throwsA(isA<ApiException>()));
  });
  test('reader normalizes URL filename and orders numeric page fields', () {
    final chapter = ReaderChapter.fromJson({
      'id': '500000',
      'scramble_id': '220980',
      'images': [
        {
          'page': '10',
          'image':
              'https://old.example/media/photos/500000/00010.webp?token=abc',
        },
        {
          'page': 2,
          'image': 'https://old.example/media/photos/500000/00002.jpg',
        },
      ],
    });
    expect(chapter.pages.first.name, '00002');
    expect(chapter.pages.last.path, '/media/photos/500000/00010.webp');
    expect(chapter.scrambleId, 220980);
  });
  test('single-volume albums receive a readable chapter', () {
    final detail = ComicDetail.fromJson({
      'id': 42,
      'name': 'Book',
      'series': [],
    });
    expect(detail.chapters.single.id, '42');
  });
  test('image segment count preserves original Qt threshold behavior', () {
    expect(JmProtocol.segmentCount(100, 220980, '00001'), 0);
    expect(JmProtocol.segmentCount(220980, 220980, '00001'), 10);
    expect(JmProtocol.segmentCount(268850, 220980, '00001'), 6);
    expect(JmProtocol.segmentCount(421926, 220980, '00001'), 6);
    expect(JmProtocol.segmentCount(421927, 220980, '00001'), 8);
  });
  test('image restore reverses unequal strips without dropping rows', () {
    final source = img.Image(width: 2, height: 11);
    for (var y = 0; y < 11; y++) {
      for (var x = 0; x < 2; x++) {
        source.setPixelRgb(x, y, y * 20, x, 10);
      }
    }
    final restored = img.decodePng(
      restoreImage((Uint8List.fromList(img.encodePng(source)), 4)),
    )!;
    final expected = [6, 7, 8, 9, 10, 4, 5, 2, 3, 0, 1];
    expect(restored.height, 11);
    for (var y = 0; y < 11; y++) {
      expect(restored.getPixel(0, y).r, expected[y] * 20);
    }
  });
  test('non-scrambled image retains original bytes', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(restoreImage((bytes, 0)), bytes);
  });
  test('configuration rejects unsafe and malformed origins', () {
    for (final host in [
      'http://example.com',
      'https://u:p@example.com',
      'https://example.com/path',
      'invalid',
    ]) {
      expect(
        () => ApiConfig(apiHosts: [host]).validate(),
        throwsFormatException,
      );
    }
  });
  test(
    'history updates same book, persists across stores, preserves other books',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      await store.saveProgress(
        const ReadingProgress(
          comic: Comic(id: '1', title: 'One'),
          chapterId: '10',
          page: 3,
        ),
      );
      await store.saveProgress(
        const ReadingProgress(
          comic: Comic(id: '2', title: 'Two'),
          chapterId: '20',
          page: 1,
        ),
      );
      await store.saveProgress(
        const ReadingProgress(
          comic: Comic(id: '1', title: 'One'),
          chapterId: '11',
          page: 8,
        ),
      );
      final history = LocalStore(prefs).history;
      expect(history.length, 2);
      expect(history.first.chapterId, '11');
      expect(history.first.page, 8);
    },
  );
}
