import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'api_config.dart';
import 'comic_source.dart';
import 'jm_client.dart' show ApiException;

/// PicACG wire protocol ported from the retained tonquer/picacg-qt source.
/// Never stores passwords or logs authentication headers / response bodies.
class PicClient implements ComicSource {
  PicClient({
    this.config = defaults,
    http.Client? transport,
    int Function()? now,
    String Function()? nonce,
  }) : _http = transport ?? http.Client(),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000),
       _nonce = nonce ?? randomNonce;
  static const defaults = ApiConfig(
    apiHosts: ['https://picaapi.picacomic.com'],
    imageHost: 'https://storage1.picacomic.com',
    version: '2.2.1.3.3.4',
    tokenSecret: 'C69BAF41DA5ABD1FFEDC6D2FEA56B',
    dataSecret:
        r'~d}$Q7$eIni=V)9\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn',
  );
  static String randomNonce() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String signature(
    String path,
    int time,
    String nonce,
    String method, {
    ApiConfig config = defaults,
  }) => Hmac(sha256, utf8.encode(config.dataSecret))
      .convert(
        utf8.encode(
          '$path$time$nonce$method${config.tokenSecret}'.toLowerCase(),
        ),
      )
      .toString();

  @override
  ContentSource get source => ContentSource.pic;
  @override
  ApiConfig config;
  @override
  String? token;
  @override
  Json? userProfile;
  @override
  void Function(String)? onUnauthorized;
  @override
  void Function(String, String, int?, int)? onRequest;
  final http.Client _http;
  final int Function() _now;
  final String Function() _nonce;
  final _details = <String, ({ComicDetail value, int expires})>{};
  final _pending = <String, Future<ComicDetail>>{};
  (String?, ApiConfig)? _scope;
  void _syncScope() {
    if (_scope == (token, config)) return;
    _scope = (token, config);
    _details.clear();
    _pending.clear();
  }

  Future<Json> request(
    String path, {
    Json query = const {},
    Json? body,
    bool authenticated = true,
    String? credentialOverride,
  }) async {
    config.validate();
    final credential = authenticated ? (credentialOverride ?? token) : null;
    if (authenticated && (credential == null || credential.isEmpty)) {
      throw const ApiException('请先登录 Pic 账号', unauthorized: true);
    }
    final method = body == null ? 'GET' : 'POST';
    String failure = '无法连接 Pic 线路，请检查网络或连接设置';
    for (final host
        in body == null ? config.apiHosts : config.apiHosts.take(1)) {
      final uri = Uri.parse('$host/$path').replace(
        queryParameters: query.isEmpty
            ? null
            : query.map((k, v) => MapEntry(k, '$v')),
      );
      final relative =
          '${uri.path.substring(1)}${uri.hasQuery ? '?${uri.query}' : ''}';
      final time = _now(), nonce = _nonce();
      final headers = <String, String>{
        'api-key': config.tokenSecret,
        'accept': 'application/vnd.picacomic.com.v1+json',
        'app-channel': '3',
        'time': '$time',
        'app-uuid': 'defaultUuid',
        'nonce': nonce,
        'signature': signature(relative, time, nonce, method, config: config),
        'app-version': config.version,
        'image-quality': 'original',
        'app-platform': 'android',
        'app-build-version': '45',
        'user-agent': 'okhttp/3.8.1',
        if (body != null) 'content-type': 'application/json; charset=UTF-8',
        'authorization': ?credential,
      };
      final watch = Stopwatch()..start();
      int? status;
      try {
        final response =
            await (body == null
                    ? _http.get(uri, headers: headers)
                    : _http.post(uri, headers: headers, body: jsonEncode(body)))
                .timeout(const Duration(seconds: 18));
        status = response.statusCode;
        if (status == 401) {
          throw const ApiException('Pic 登录已过期，请重新登录', unauthorized: true);
        }
        if (status >= 500 && body == null) {
          failure = 'Pic 线路暂不可用（$status）';
          continue;
        }
        final envelope = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
        final code = integer(envelope['code'], status);
        if (code == 401) {
          throw const ApiException('Pic 登录已过期，请重新登录', unauthorized: true);
        }
        if (status < 200 || status >= 300 || code < 200 || code >= 300) {
          throw ApiException(
            'Pic 请求未成功（$status / $code）：${envelope['message'] ?? envelope['error'] ?? '请重试'}',
          );
        }
        return Map<String, dynamic>.from(envelope['data'] as Map? ?? {});
      } on ApiException catch (error) {
        if (error.unauthorized && credential != null && credential == token) {
          onUnauthorized?.call(credential);
        }
        rethrow;
      } on TimeoutException {
        failure = 'Pic 连接超时';
      } on http.ClientException {
        failure = '无法连接 Pic 线路';
      } on FormatException {
        throw const ApiException('Pic 响应格式不匹配，请检查连接设置');
      } finally {
        // Only a fixed route family reaches the log; never IDs or search text.
        onRequest?.call(
          '/pic/${path.split('/').first}',
          method,
          status,
          watch.elapsedMilliseconds,
        );
      }
    }
    throw ApiException(body == null ? failure : '$failure；请刷新确认操作结果后重试');
  }

  String media(dynamic value) {
    if (value is! Map) return '';
    final path = '${value['path'] ?? ''}'.replaceFirst(
      RegExp(r'^(?:/?static/)+'),
      '',
    );
    final host = '${value['fileServer'] ?? ''}'.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (host.isEmpty) return '';
    final base = config.imageHost == defaults.imageHost
        ? host
        : config.imageHost;
    if (path.isEmpty) return base;
    final cleanBase = base.replaceFirst(RegExp(r'/static/?$'), '');
    var uri = Uri.parse(
      '$cleanBase/static/${path.replaceFirst(RegExp(r'^/+'), '')}',
    );
    // Same legacy media aliases as DownloadBookReq in the Qt reference. These
    // are URL compatibility rules; API credentials never reach these hosts.
    const aliases = {
      'storage-b.picacomic.com': 'img.picacomic.com',
      's3.picacomic.com': 'img.picacomic.com',
      'storage1.picacomic.com': 'img.picacomic.com',
      'storage.picacomic.com': 'img.picacomic.com',
      'storage-b.diwodiwo.xyz': 'img.diwodiwo.xyz',
      's3.diwodiwo.xyz': 'img.diwodiwo.xyz',
      'storage1.diwodiwo.xyz': 'img.diwodiwo.xyz',
      'storage.tipatipa.xyz': 'img.tipatipa.xyz',
      'storage-b.tipatipa.xyz': 'img.tipatipa.xyz',
      's3.tipatipa.xyz': 'img.tipatipa.xyz',
      'storage1.tipatipa.xyz': 'img.tipatipa.xyz',
    };
    if (uri.path.startsWith('/static/tobeimg/') &&
        aliases.containsKey(uri.host)) {
      uri = uri.replace(
        host: aliases[uri.host],
        path: uri.path.replaceFirst('/static/tobeimg', ''),
      );
    } else {
      uri = uri.replace(
        path: uri.path
            .replaceFirst('/static/tobeimg/', '/static/')
            .replaceFirst('/static/tobs/', '/static/'),
      );
    }
    return uri.toString();
  }

  Comic _comic(dynamic raw) {
    final j = Map<String, dynamic>.from(raw as Map);
    return Comic(
      id: '${j['_id'] ?? j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      authors: strings(j['author']),
      tags: strings(j['tags']),
      source: source,
      cover: media(j['thumb']),
    );
  }

  ComicPage _page(Json data, {String field = 'comics'}) {
    final raw = data[field];
    if (raw is List) {
      return ComicPage(raw.map(_comic).toList(), raw.length, more: false);
    }
    final page = Map<String, dynamic>.from(raw as Map? ?? {});
    return ComicPage(
      (page['docs'] as List? ?? []).map(_comic).toList(),
      integer(page['total']),
      more: integer(page['page'], 1) < integer(page['pages'], 1),
    );
  }

  static String sort(String value) => switch (value) {
    'mr' => 'dd',
    'mv' => 'vd',
    'tf' => 'ld',
    'dd' || 'da' || 'ld' || 'vd' => value,
    _ => 'dd',
  };
  @override
  Future<List<Comic>> home() async =>
      (await homeSections()).expand((s) => s.items).toList();
  @override
  Future<List<HomeSection>> homeSections() async {
    final values = await Future.wait([
      request('collections'),
      request('comics/random'),
    ]);
    return [
      HomeSection(
        title: '随机推荐',
        type: 'pic',
        id: 'random',
        slug: '',
        filter: '',
        items: _page(values[1]).items,
      ),
      for (final value in values[0]['collections'] as List? ?? [])
        HomeSection(
          title: '${value['title'] ?? '推荐'}',
          type: 'pic',
          id: '${value['_id'] ?? ''}',
          slug: '',
          filter: '',
          items: (value['comics'] as List? ?? []).map(_comic).toList(),
        ),
    ];
  }

  @override
  Future<ComicPage> latest(int page) => category('0', page);
  @override
  Future<CategoryCatalog> categories() async {
    final data = await request('categories');
    return CategoryCatalog([
      for (final c in data['categories'] as List? ?? [])
        if (c['isWeb'] != true && c['active'] != false)
          BrowseCategory('${c['title']}', '${c['title']}', const []),
    ]);
  }

  @override
  Future<ComicPage> category(
    String slug,
    int page, {
    String sort = 'mr',
  }) async {
    if (sort.startsWith('mv')) {
      if (page > 1) return const ComicPage([], 0, more: false);
      return _page(
        await request(
          'comics/leaderboard',
          query: {
            'tt': switch (sort) {
              'mv_t' => 'H24',
              'mv_w' => 'D7',
              _ => 'D30',
            },
            'ct': 'VC',
          },
        ),
      );
    }
    return _page(
      await request(
        'comics',
        query: {
          'page': page,
          if (slug != '0' && slug.isNotEmpty) 'c': slug,
          's': PicClient.sort(sort),
        },
      ),
    );
  }

  @override
  Future<ComicPage> search(
    String text,
    int page, {
    SearchOptions options = const SearchOptions(),
  }) async => _page(
    await request(
      'comics/advanced-search',
      query: {'page': page},
      body: {
        'categories': <String>[],
        'keyword': text,
        'sort': sort(options.sort),
      },
    ),
  );

  /// A complete, ordered snapshot: an interrupted pagination never becomes a
  /// partial chapter in a download or in the detail cache.
  Future<List<Json>> _all(String path, String field) async {
    final result = <Json>[];
    var page = 1, pages = 1;
    do {
      final data = await request(path, query: {'page': page});
      final block = data[field] as Map?;
      if (block == null) throw const ApiException('Pic 分页数据缺失');
      if (integer(block['page'], page) != page) {
        throw const ApiException('Pic 分页顺序异常，请重试');
      }
      pages = integer(block['pages'], 1).clamp(1, 10000);
      final docs = List<Json>.from(block['docs'] as List? ?? []);
      if (docs.isEmpty && page < pages) {
        throw const ApiException('Pic 分页不完整，请重试');
      }
      result.addAll(docs);
      if (page == pages &&
          block['total'] != null &&
          result.length != integer(block['total'])) {
        throw const ApiException('Pic 内容数量已变化，请刷新重试');
      }
      page++;
    } while (page <= pages);
    return result;
  }

  @override
  ComicDetail? cachedDetail(String id, {bool allowStale = false}) {
    _syncScope();
    final entry = _details[id];
    if (entry == null || !allowStale && entry.expires <= _now()) return null;
    _details.remove(id);
    _details[id] = entry;
    return entry.value;
  }

  @override
  void invalidateDetail(String id) {
    _details.remove(id);
    _pending.remove(id);
  }

  @override
  Future<ComicDetail> detail(String id, {bool refresh = false}) {
    _syncScope();
    if (refresh) invalidateDetail(id);
    final cached = cachedDetail(id);
    if (cached != null) return Future.value(cached);
    if (_pending[id] case final pending?) return pending;
    late final Future<ComicDetail> operation;
    operation = () async {
      try {
        final data = await request('comics/${Uri.encodeComponent(id)}');
        final raw = Map<String, dynamic>.from(data['comic'] as Map);
        final episodes = (await _all(
          'comics/${Uri.encodeComponent(id)}/eps',
          'eps',
        )).reversed.toList();
        final detail = ComicDetail(
          comic: _comic(raw),
          description: '${raw['description'] ?? ''}',
          tags: [...strings(raw['categories']), ...strings(raw['tags'])],
          favorite: raw['isFavourite'] == true,
          likes: countLabel(raw['totalLikes'] ?? raw['likesCount']),
          chapters: [
            for (final (index, ep) in episodes.indexed)
              // The reference uses the ascending list position, NOT ep.order
              // (which may be duplicated), for the /order/{n}/pages endpoint.
              Chapter(
                id: '$id~${index + 1}~${ep['_id'] ?? index + 1}',
                title: '${ep['title'] ?? '第 ${index + 1} 章'}',
              ),
          ],
        );
        _syncScope();
        if (identical(_pending[id], operation)) {
          _details[id] = (value: detail, expires: _now() + 300);
          while (_details.length > 40) {
            _details.remove(_details.keys.first);
          }
        }
        return detail;
      } finally {
        if (identical(_pending[id], operation)) _pending.remove(id);
      }
    }();
    _pending[id] = operation;
    return operation;
  }

  @override
  Future<ReaderChapter> chapter(String id) async {
    final parts = id.split('~');
    if (parts.length != 3 || int.tryParse(parts[1]) == null) {
      throw const ApiException('Pic 章节标识无效，请从作品目录重新打开');
    }
    final pages = await _all(
      'comics/${Uri.encodeComponent(parts[0])}/order/${parts[1]}/pages',
      'pages',
    );
    if (pages.isEmpty) throw const ApiException('该 Pic 章节暂无图片');
    return ReaderChapter(
      id: id,
      source: source,
      scrambleId: 0,
      pages: [
        for (final (index, raw) in pages.indexed)
          ReaderPage(path: media(raw['media']), name: '$index'),
      ],
    );
  }

  @override
  Future<ComicPage> favorites(int page) async =>
      _page(await request('users/favourite', query: {'s': 'dd', 'page': page}));
  @override
  Future<Json> favoriteFolder(String folder, int page, String sort) async {
    final result = _page(
      await request(
        'users/favourite',
        query: {'s': PicClient.sort(sort), 'page': page},
      ),
    );
    return {
      'list': result.items.map((c) => c.toJson()).toList(),
      'total': result.total,
    };
  }

  @override
  Future<void> toggleFavorite(String id) async {
    await request('comics/${Uri.encodeComponent(id)}/favourite', body: {});
    invalidateDetail(id);
  }

  @override
  Future<String> login(String username, String password) async {
    final data = await request(
      'auth/sign-in',
      body: {'email': username, 'password': password},
      authenticated: false,
    );
    final credential = data['token'];
    if (credential is! String || credential.isEmpty) {
      throw const ApiException('Pic 登录结果缺少令牌');
    }
    userProfile = await _profile(credential);
    return credential;
  }

  Future<Json> _profile(String credential) async {
    final data = await request('users/profile', credentialOverride: credential);
    final user = Map<String, dynamic>.from(data['user'] as Map);
    return {
      'uid': '${user['_id'] ?? user['id'] ?? ''}',
      'username': '${user['name'] ?? ''}',
      'level': user['level'],
      'exp': user['exp'],
      'gender': user['gender'],
      'level_name': user['title'] ?? user['level'],
      'avatar': media(user['avatar']),
      'isPunched': user['isPunched'] == true,
    };
  }

  Future<Json> refreshProfile() async {
    final credential = token;
    if (credential == null) {
      throw const ApiException('请先登录 Pic 账号', unauthorized: true);
    }
    final profile = await _profile(credential);
    if (token != credential) {
      throw const ApiException('Pic 账号已变化，请刷新', unauthorized: true);
    }
    userProfile = profile;
    return profile;
  }

  @override
  Future<Json> daily(String uid) async {
    final profile = await refreshProfile();
    return {
      'daily_id': 'pic',
      'record': [
        {'date': DateTime.now().day, 'signed': profile['isPunched'] == true},
      ],
    };
  }

  @override
  Future<String> sign(String uid, String dailyId, {String date = ''}) async {
    if (date.isNotEmpty) throw const ApiException('Pic 不支持补签');
    await request('users/punch-in', body: {});
    await refreshProfile();
    return '签到成功';
  }

  Json _comment(Json j, String comicId) => {
    'CID': '${j['_id'] ?? j['id'] ?? ''}',
    'AID': comicId,
    'username': '${(j['_user'] as Map?)?['name'] ?? '匿名'}',
    'content': '${j['content'] ?? ''}',
    'addtime': '${j['created_at'] ?? ''}',
    'replys': <Json>[],
    'replyTotal': integer(j['commentsCount']),
  };
  @override
  Future<Json> comments(String id, int page, {String? uid}) async {
    final data = await request(
      uid == null
          ? 'comics/${Uri.encodeComponent(id)}/comments'
          : 'users/my-comments',
      query: {'page': page},
    );
    final block = Map<String, dynamic>.from(data['comments'] as Map? ?? {});
    final docs = List<Json>.from(block['docs'] as List? ?? []);
    final result = <Json>[];
    for (final raw in docs) {
      final comic = raw['_comic'];
      final comicId = comic is Map ? '${comic['_id'] ?? id}' : id;
      result.add(_comment(raw, comicId));
    }
    return {
      'list': result,
      'total': integer(block['total']),
      'more': integer(block['page'], page) < integer(block['pages'], page),
    };
  }

  Future<Json> replies(String id, int page) async {
    final data = await request(
      'comments/${Uri.encodeComponent(id)}/childrens',
      query: {'page': page},
    );
    final block = Map<String, dynamic>.from(data['comments'] as Map? ?? {});
    return {
      'list': [
        for (final raw in List<Json>.from(block['docs'] as List? ?? []))
          _comment(raw, ''),
      ],
      'more': integer(block['page'], page) < integer(block['pages'], page),
    };
  }

  @override
  Future<String> comment(String id, String content, {String reply = ''}) async {
    await request(
      reply.isEmpty
          ? 'comics/${Uri.encodeComponent(id)}/comments'
          : 'comments/${Uri.encodeComponent(reply)}',
      body: {'content': content},
    );
    return '评论已发送';
  }

  Never _unsupported() => throw const ApiException('Pic 不支持此功能');
  @override
  Future<void> editFavoriteFolder(
    String action, {
    String id = '',
    String name = '',
    String comicId = '',
  }) async => _unsupported();
  @override
  Future<ComicPage> cloudHistory(int page) async => _unsupported();
  @override
  Future<String> purchase(String id) async => _unsupported();
  @override
  Future<ComicPage> serialization(int day, String type, int page) async =>
      _unsupported();
  @override
  Future<List<Json>> weekIssues() async => _unsupported();
  @override
  Future<ComicPage> week(String id, String type, int page) async =>
      _unsupported();
  @override
  void close() {
    _details.clear();
    _pending.clear();
    _http.close();
  }
}
