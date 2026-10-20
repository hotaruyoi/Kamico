import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'jm_protocol.dart';
import '../domain/models.dart';
import 'comic_source.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

class JmClient implements ComicSource {
  @override
  ContentSource get source => ContentSource.jm;
  JmClient({required this.config, http.Client? transport, int Function()? now})
    : _http = transport ?? http.Client(),
      _now = now ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);
  @override
  ApiConfig config;
  @override
  String? token;
  @override
  Json? userProfile;
  @override
  void Function(String token)? onUnauthorized;
  void Function(String path, String method, int? status, int milliseconds)?
  onRequest;
  final http.Client _http;
  final int Function() _now;
  // Session-only, bounded LRU. Account/connection changes cannot reuse details.
  final _details = <String, ({ComicDetail value, int expires})>{};
  final _detailRequests = <String, Future<ComicDetail>>{};
  (String?, ApiConfig)? _detailScope;

  void _syncDetailScope() {
    final scope = (token, config);
    if (_detailScope == scope) return;
    _detailScope = scope;
    _details.clear();
    _detailRequests.clear();
  }

  @override
  ComicDetail? cachedDetail(String id, {bool allowStale = false}) {
    _syncDetailScope();
    final entry = _details[id];
    if (entry == null || !allowStale && entry.expires <= _now()) return null;
    _details.remove(id);
    _details[id] = entry;
    return entry.value;
  }

  @override
  void invalidateDetail(String id) {
    _details.remove(id);
    _detailRequests.remove(id);
  }

  Future<dynamic> request(
    String path, {
    Json query = const {},
    Json? form,
    bool authenticated = true,
  }) async {
    config.validate();
    final requestToken = authenticated ? token : null;
    String lastError = '无可用线路';
    // Only GET requests may fail over: a timed-out POST may already have succeeded.
    final hosts = form == null ? config.apiHosts : config.apiHosts.take(1);
    for (final host in hosts) {
      final timestamp = _now();
      final uri = Uri.parse(host).replace(
        path: '$path/',
        queryParameters: query.isEmpty
            ? null
            : query.map((k, v) => MapEntry(k, '$v')),
      );
      final headers = JmProtocol.headers(
        timestamp,
        config,
        token: requestToken,
      );
      final stopwatch = Stopwatch()..start();
      int? status;
      try {
        final response =
            await (form == null
                    ? _http.get(uri, headers: headers)
                    : _http.post(
                        uri,
                        headers: headers,
                        body: form.map((k, v) => MapEntry(k, '$v')),
                      ))
                .timeout(const Duration(seconds: 18));
        status = response.statusCode;
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw ApiException(
            '认证失效或线路拒绝访问（${response.statusCode}）',
            unauthorized: response.statusCode == 401,
          );
        }
        if (response.statusCode != 200) {
          if (response.statusCode >= 500 && form == null) {
            lastError = '线路暂不可用（${response.statusCode}）';
            continue;
          }
          throw ApiException('请求失败（HTTP ${response.statusCode}）');
        }
        final envelope = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
        if (integer(envelope['code']) != 200) {
          throw ApiException(
            '${envelope['errorMsg'] ?? envelope['message'] ?? '上游接口拒绝请求'}',
            unauthorized: integer(envelope['code']) == 401,
          );
        }
        final data = envelope['data'];
        if (data is! String) throw const FormatException('上游响应不是预期的加密数据');
        return JmProtocol.decode(data, timestamp, config.dataSecret);
      } on ApiException catch (error) {
        if (error.unauthorized && requestToken?.isNotEmpty == true) {
          onUnauthorized?.call(requestToken!);
        }
        rethrow;
      } on TimeoutException {
        lastError = '连接超时，请检查网络或切换线路';
      } on http.ClientException {
        lastError = '无法连接线路，请检查网络设置';
      } on FormatException {
        throw const ApiException('响应格式或解密参数不匹配，请检查设置中的协议参数');
      } on ArgumentError {
        throw const ApiException('响应解密失败，请检查协议参数');
      } finally {
        onRequest?.call(
          RegExp(r'^/[a-z_]+$').hasMatch(path) ? path : '/other',
          form == null ? 'GET' : 'POST',
          status,
          stopwatch.elapsedMilliseconds,
        );
      }
    }
    throw ApiException(form == null ? lastError : '$lastError；请刷新确认操作结果后重试');
  }

  @override
  Future<List<Comic>> home() async {
    final blocks =
        await request('/promote', query: {'page': 0, 'lang': 'CN'}) as List;
    final byId = <String, Comic>{};
    for (final block in blocks) {
      for (final item in block['content'] as List? ?? []) {
        final comic = Comic.fromJson(item as Json);
        byId[comic.id] = comic;
      }
    }
    return byId.values.toList();
  }

  @override
  Future<ComicPage> search(
    String text,
    int page, {
    SearchOptions options = const SearchOptions(),
  }) async => ComicPage.fromJson(
    await request('/search', query: options.query(text, page)) as Json,
  );
  @override
  Future<List<HomeSection>> homeSections() async =>
      (await request('/promote', query: {'page': 0, 'lang': 'CN'}) as List)
          .map((e) => HomeSection.fromJson(e as Json))
          .where((e) => !['novels', 'library'].contains(e.type))
          .toList();
  @override
  Future<ComicPage> latest(int page) async {
    final data =
        await request('/latest', query: {'page': page - 1, 'lang': 'CN'})
            as List;
    final items = data.map((e) => Comic.fromJson(e as Json)).toList();
    return ComicPage(items, 0, more: items.isNotEmpty);
  }

  @override
  Future<CategoryCatalog> categories() async => CategoryCatalog.fromJson(
    await request('/categories', query: {'lang': 'CN'}) as Json,
  );
  @override
  Future<ComicPage> category(
    String slug,
    int page, {
    String sort = 'mr',
  }) async => ComicPage.fromJson(
    await request(
          '/categories/filter',
          query: {'c': slug, 'page': page, 'o': sort, 'lang': 'CN'},
        )
        as Json,
  );
  @override
  Future<ComicPage> serialization(int day, String type, int page) async =>
      ComicPage.fromJson(
        await request(
              '/serialization',
              query: {'date': day, 'type': type, 'page': page, 'lang': 'CN'},
            )
            as Json,
        key: 'list',
      );
  @override
  Future<List<Json>> weekIssues() async => List<Json>.from(
    (await request('/week', query: {'page': 0, 'lang': 'CN'})
                as Json)['categories']
            as List? ??
        [],
  );
  @override
  Future<ComicPage> week(String id, String type, int page) async {
    final data =
        await request(
              '/week/filter',
              query: {'id': id, 'type': type, 'page': page - 1, 'lang': 'CN'},
            )
            as Json;
    final items = ComicPage.fromJson(data, key: 'list');
    return ComicPage(
      items.items,
      integer(data['total']),
      more: data['total'] == null ? items.items.isNotEmpty : null,
    );
  }

  @override
  Future<ComicDetail> detail(String id, {bool refresh = false}) {
    _syncDetailScope();
    if (refresh) invalidateDetail(id);
    final cached = cachedDetail(id);
    if (cached != null) return Future.value(cached);
    if (_detailRequests[id] case final pending?) return pending;
    late final Future<ComicDetail> pending;
    pending = () async {
      try {
        final value = ComicDetail.fromJson(
          await request(
                '/album',
                query: {'id': id, 'comicName': '', 'lang': 'CN'},
              )
              as Json,
        );
        _syncDetailScope();
        if (identical(_detailRequests[id], pending)) {
          _details[id] = (value: value, expires: _now() + 300);
          while (_details.length > 40) {
            _details.remove(_details.keys.first);
          }
        }
        return value;
      } finally {
        if (identical(_detailRequests[id], pending)) _detailRequests.remove(id);
      }
    }();
    _detailRequests[id] = pending;
    return pending;
  }

  @override
  Future<ReaderChapter> chapter(String id) async {
    final chapter = ReaderChapter.fromJson(
      await request('/comic_read', query: {'id': id, 'lang': 'CN'}) as Json,
    );
    if (chapter.scrambleId < 0) {
      throw const ApiException('章节缺少 scramble_id，无法安全恢复图片顺序');
    }
    return chapter;
  }

  @override
  Future<ComicPage> favorites(int page) async => ComicPage.fromJson(
    await request(
          '/favorite',
          query: {'page': page, 'folder_id': '0', 'o': 'mr', 'lang': 'CN'},
        )
        as Json,
    key: 'list',
  );
  @override
  Future<Json> favoriteFolder(String folder, int page, String sort) async =>
      await request(
            '/favorite',
            query: {'folder_id': folder, 'page': page, 'o': sort, 'lang': 'CN'},
          )
          as Json;
  @override
  Future<void> editFavoriteFolder(
    String action, {
    String id = '',
    String name = '',
    String comicId = '',
  }) async {
    final result =
        await request(
              '/favorite_folder',
              form: {
                'type': action,
                if (action == 'add') 'folder_name': name,
                if (action != 'add') 'folder_id': id,
                if (action == 'move') 'aid': comicId,
              },
            )
            as Json;
    if (result['status'] != 'ok') {
      throw ApiException('${result['msg'] ?? '收藏夹操作失败'}');
    }
  }

  @override
  Future<ComicPage> cloudHistory(int page) async => ComicPage.fromJson(
    await request('/watch_list', query: {'page': page}) as Json,
    key: 'list',
  );
  @override
  Future<void> toggleFavorite(String id) async {
    final result = await request('/favorite', form: {'aid': id}) as Json;
    if (result['status'] != 'ok') {
      throw ApiException('${result['msg'] ?? '收藏操作失败'}');
    }
    invalidateDetail(id);
  }

  @override
  Future<String> login(String username, String password) async {
    final result =
        await request(
              '/login',
              form: {'username': username, 'password': password},
              authenticated: false,
            )
            as Json;
    final value = result['jwttoken'];
    if (value is! String || value.isEmpty) throw const ApiException('登录结果缺少令牌');
    userProfile = {
      for (final key in [
        'uid',
        'username',
        'level_name',
        'level',
        'coin',
        'gender',
        'album_favorites',
        'album_favorites_max',
        'exp',
        'nextLevelExp',
      ])
        if (result.containsKey(key)) key: result[key],
    };
    return value;
  }

  @override
  Future<Json> daily(String uid) async =>
      await request('/daily', query: {'user_id': uid}) as Json;
  @override
  Future<String> sign(String uid, String dailyId, {String date = ''}) async =>
      _actionMessage(
        await request(
          '/daily_chk',
          form: {
            'user_id': uid,
            'daily_id': dailyId,
            if (date.isNotEmpty) 'date': date,
          },
        ),
      );
  @override
  Future<String> purchase(String id) async {
    final message = _actionMessage(
      await request('/coin_buy_comics', form: {'id': id}),
    );
    invalidateDetail(id);
    return message;
  }

  @override
  Future<Json> comments(String id, int page, {String? uid}) async =>
      await request(
            '/forum',
            query: {
              'mode': uid == null ? 'manhua' : 'undefined',
              if (id.isNotEmpty) 'aid': id,
              'uid': ?uid,
              'page': page,
              'lang': 'CN',
            },
          )
          as Json;
  @override
  Future<String> comment(
    String id,
    String content, {
    String reply = '',
  }) async => _actionMessage(
    await request(
      '/comment',
      form: {
        'aid': id,
        'comment': content,
        if (reply.isNotEmpty) 'comment_id': reply,
      },
    ),
  );
  String _actionMessage(dynamic data) {
    final result = data as Json;
    if (result['status'] != null && result['status'] != 'ok') {
      throw ApiException('${result['msg'] ?? '操作未成功'}');
    }
    return '${result['msg'] ?? '操作成功'}';
  }

  @override
  void close() {
    _details.clear();
    _detailRequests.clear();
    _http.close();
  }
}
