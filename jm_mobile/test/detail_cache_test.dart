import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'discovery_test.dart' show response;

void main() {
  test(
    'details coalesce in-flight requests and reuse the completed value',
    () async {
      var requests = 0;
      final gate = Completer<void>();
      final api = JmClient(
        config: const ApiConfig(),
        now: () => 1700000000,
        transport: MockClient((_) async {
          requests++;
          await gate.future;
          return response({'id': '1', 'name': 'Book'});
        }),
      );
      addTearDown(api.close);
      final first = api.detail('1');
      final second = api.detail('1');
      expect(identical(first, second), true);
      gate.complete();
      final value = await first;
      expect(identical(await api.detail('1'), value), true);
      expect(identical(api.cachedDetail('1'), value), true);
      expect(requests, 1);
      await api.detail('1', refresh: true);
      expect(requests, 2);
    },
  );

  test(
    'failures are not cached and a failed refresh does not retain stale data',
    () async {
      var fail = true, requests = 0;
      final api = JmClient(
        config: const ApiConfig(),
        now: () => 1700000000,
        transport: MockClient((_) async {
          requests++;
          return fail ? http.Response('no', 400) : response({'id': '1'});
        }),
      );
      addTearDown(api.close);
      await expectLater(api.detail('1'), throwsA(isA<ApiException>()));
      fail = false;
      await api.detail('1');
      fail = true;
      await expectLater(
        api.detail('1', refresh: true),
        throwsA(isA<ApiException>()),
      );
      expect(api.cachedDetail('1'), null);
      expect(requests, 3);
    },
  );

  test(
    'expiry and LRU capacity are bounded without fetching on cache inspection',
    () async {
      var now = 1700000000, requests = 0;
      final api = JmClient(
        config: const ApiConfig(),
        now: () => now,
        transport: MockClient((request) async {
          requests++;
          // Encrypt with the same timestamp used for this request.
          return response({'id': request.url.queryParameters['id']});
        }),
      );
      addTearDown(api.close);
      for (var i = 0; i < 40; i++) {
        await api.detail('$i');
      }
      expect(api.cachedDetail('0'), isNotNull);
      await api.detail('40');
      expect(api.cachedDetail('1'), null);
      expect(api.cachedDetail('0'), isNotNull);
      now += 300;
      expect(api.cachedDetail('0'), null);
      expect(api.cachedDetail('0', allowStale: true), isNotNull);
      expect(requests, 41);
    },
  );

  test(
    'account and endpoint changes discard cached and pending old results',
    () async {
      var requests = 0;
      final gate = Completer<void>();
      final api = JmClient(
        config: const ApiConfig(),
        now: () => 1700000000,
        transport: MockClient((_) async {
          final index = ++requests;
          if (index == 1) await gate.future;
          return response({'id': '1', 'name': 'Response $index'});
        }),
      );
      addTearDown(api.close);
      api.token = 'synthetic-A';
      final old = api.detail('1');
      api.token = 'synthetic-B';
      final current = await api.detail('1');
      gate.complete();
      await old;
      expect(identical(api.cachedDetail('1'), current), true);
      api.token = null;
      expect(api.cachedDetail('1'), null);
      expect(api.cachedDetail('1', allowStale: true), null);
      await api.detail('1');
      api.config = const ApiConfig(imageHost: 'https://new.example.test');
      expect(api.cachedDetail('1'), null);
      expect(api.cachedDetail('1', allowStale: true), null);
    },
  );

  test(
    'favorite and purchase mutations invalidate the affected detail',
    () async {
      final api = JmClient(
        config: const ApiConfig(),
        now: () => 1700000000,
        transport: MockClient(
          (request) async => response(
            request.method == 'POST'
                ? {'status': 'ok', 'msg': 'OK'}
                : {'id': '1'},
          ),
        ),
      );
      addTearDown(api.close);
      await api.detail('1');
      await api.toggleFavorite('1');
      expect(api.cachedDetail('1'), null);
      await api.detail('1');
      await api.purchase('1');
      expect(api.cachedDetail('1'), null);
    },
  );
}
