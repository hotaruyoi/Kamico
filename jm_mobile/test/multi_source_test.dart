import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/download_repository.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/data/pic_client.dart';
import 'package:jm_mobile/data/image_repository.dart';
import 'package:jm_mobile/domain/models.dart';
import 'package:jm_mobile/ui/app.dart';
import 'package:jm_mobile/ui/detail_reader.dart';
import 'package:jm_mobile/ui/discovery.dart';
import 'package:jm_mobile/ui/library_layout.dart';

http.Response ok(Json data) => http.Response(
  jsonEncode({'code': 200, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json paged(List<Json> docs, {int page = 1, int pages = 1, int? total}) => {
  'docs': docs,
  'page': page,
  'pages': pages,
  'total': total ?? docs.length,
};
Json picComic(String id) => {
  '_id': id,
  'title': 'Pic $id',
  'author': 'Fixture',
  'thumb': {'fileServer': 'https://images.invalid', 'path': 'cover.jpg'},
};

class FixtureJm extends JmClient {
  FixtureJm() : super(config: const ApiConfig());
  final chapterCalls = <String>[];
  @override
  Future<List<HomeSection>> homeSections() async => [];
  @override
  Future<ReaderChapter> chapter(String id) async {
    chapterCalls.add(id);
    return ReaderChapter(
      id: id,
      scrambleId: 0,
      pages: const [ReaderPage(path: '', name: '0')],
    );
  }
}

class FixturePic extends PicClient {
  final chapterCalls = <String>[], detailCalls = <String>[];
  final gate = Completer<void>();
  bool waitForChapter = false;
  @override
  Future<List<HomeSection>> homeSections() async => [];
  @override
  Future<ReaderChapter> chapter(String id) async {
    chapterCalls.add(id);
    if (waitForChapter) await gate.future;
    return ReaderChapter(
      id: id,
      source: ContentSource.pic,
      scrambleId: 0,
      pages: const [ReaderPage(path: 'https://images.invalid/page', name: '0')],
    );
  }

  @override
  Future<ComicDetail> detail(String id, {bool refresh = false}) async {
    detailCalls.add(id);
    return ComicDetail(
      comic: Comic(id: id, title: 'Pic detail', source: ContentSource.pic),
      description: 'Synthetic',
      tags: [],
      favorite: false,
      chapters: [Chapter(id: '$id~1~ep', title: 'Pic chapter')],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'legacy JM data and colliding Pic IDs remain independent across restart and deletion',
    () async {
      final store = LocalStore(await SharedPreferences.getInstance());
      const jm = Comic(id: 'same', title: 'JM legacy');
      const pic = Comic(
        id: 'same',
        title: 'Pic new',
        source: ContentSource.pic,
      );
      // Exact legacy wire data has no source or cover fields.
      await store.writeMap('local_favorites', {
        'same': {
          'comic': {'id': 'same', 'name': 'JM legacy'},
          'folder': '0',
        },
      });
      await store.saveProgress(
        const ReadingProgress(comic: jm, chapterId: 'chapter', page: 4),
      );
      await store.addLocal(pic);
      await store.saveProgress(
        const ReadingProgress(comic: pic, chapterId: 'chapter', page: 8),
      );
      final restored = LocalStore(await SharedPreferences.getInstance());
      expect(restored.localFavorites.keys, containsAll(['same', 'pic|same']));
      expect(restored.chapterProgress(jm.key, 'chapter')!.page, 4);
      expect(restored.chapterProgress(pic.key, 'chapter')!.page, 8);
      expect(
        restored.history.map((p) => p.comic.source),
        containsAll(ContentSource.values),
      );
      await restored.deleteHistory([pic.key]);
      await restored.removeLocal([pic.key]);
      expect(restored.history.single.comic.source, ContentSource.jm);
      expect(restored.chapterProgress(jm.key, 'chapter')!.page, 4);
      expect(restored.chapterProgress(pic.key, 'chapter'), isNull);
      expect(restored.localFavorites.keys, ['same']);
    },
  );

  test(
    'tokens, profile, search and connection config persist per source without changing JM keys',
    () async {
      final jm = LocalStore(await SharedPreferences.getInstance());
      final pic = jm.forSource(ContentSource.pic);
      await jm.saveToken('jm-fixture');
      await pic.saveToken('pic-fixture');
      await jm.writeMap('profile', {'uid': 'same', 'username': 'JM'});
      await pic.writeMap('profile', {'uid': 'same', 'username': 'Pic'});
      await jm.rememberSearch('JM only');
      await pic.rememberSearch('Pic only');
      await pic.saveConfig(const ApiConfig(apiHosts: ['https://pic.invalid']));
      expect(await jm.readToken(), 'jm-fixture');
      expect(await pic.readToken(), 'pic-fixture');
      expect(jm.readMap('profile')['username'], 'JM');
      expect(pic.readMap('profile')['username'], 'Pic');
      expect(jm.searchHistory, ['JM only']);
      expect(pic.searchHistory, ['Pic only']);
      expect(jm.config.apiHosts, const ApiConfig().apiHosts);
      expect(pic.config.apiHosts, ['https://pic.invalid']);
      await pic.clearToken();
      expect(await jm.readToken(), 'jm-fixture');
      expect(await pic.readToken(), isNull);
    },
  );

  test(
    'Pic signed pagination preserves repeated episode order and retrieves all images',
    () async {
      final requests = <http.Request>[];
      final client = PicClient(
        now: () => 123456,
        nonce: () => 'fixture-nonce',
        transport: MockClient((request) async {
          requests.add(request);
          expect(request.headers['authorization'], 'pic-fixture');
          final relative =
              '${request.url.path.substring(1)}${request.url.hasQuery ? '?${request.url.query}' : ''}';
          expect(
            request.headers['signature'],
            PicClient.signature(
              relative,
              123456,
              'fixture-nonce',
              request.method,
            ),
          );
          switch (request.url.path) {
            case '/comics/book':
              return ok({'comic': picComic('book')});
            case '/comics/book/eps':
              return ok({
                'eps': request.url.queryParameters['page'] == '1'
                    ? paged(
                        [
                          {'_id': 'new', 'title': 'Second', 'order': 1},
                        ],
                        page: 1,
                        pages: 2,
                        total: 2,
                      )
                    : paged(
                        [
                          {'_id': 'old', 'title': 'First', 'order': 1},
                        ],
                        page: 2,
                        pages: 2,
                        total: 2,
                      ),
              });
            case '/comics/book/order/2/pages':
              final page = int.parse(request.url.queryParameters['page']!);
              return ok({
                'pages': paged(
                  [
                    {
                      'media': {
                        'fileServer': 'https://images.invalid',
                        'path': '$page.jpg',
                      },
                    },
                  ],
                  page: page,
                  pages: 2,
                  total: 2,
                ),
              });
            default:
              throw StateError('unexpected ${request.url}');
          }
        }),
      )..token = 'pic-fixture';
      addTearDown(client.close);
      final detail = await client.detail('book');
      expect(detail.chapters.map((c) => c.title), ['First', 'Second']);
      expect(detail.chapters.map((c) => c.id), ['book~1~old', 'book~2~new']);
      final chapter = await client.chapter(detail.chapters.last.id);
      expect(chapter.source, ContentSource.pic);
      expect(chapter.pages.map((p) => p.path), [
        'https://images.invalid/static/1.jpg',
        'https://images.invalid/static/2.jpg',
      ]);
      expect(requests.length, 5);
      expect(identical(client.cachedDetail('book'), detail), true);
      client.token = 'another-account';
      expect(client.cachedDetail('book', allowStale: true), isNull);
    },
  );

  test(
    'incomplete Pic pagination fails without caching or returning a truncated chapter',
    () async {
      final client = PicClient(
        transport: MockClient(
          (request) async => ok({
            'pages': paged([
              {
                'media': {
                  'fileServer': 'https://images.invalid',
                  'path': '1.jpg',
                },
              },
            ], total: 2),
          }),
        ),
      )..token = 'fixture';
      addTearDown(client.close);
      await expectLater(
        client.chapter('book~1~ep'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'Pic login uses a provisional token and never overwrites the existing token or sends passwords in GET',
    () async {
      var expired = 0;
      final client =
          PicClient(
              transport: MockClient((request) async {
                if (request.method == 'POST') {
                  expect(request.headers.containsKey('authorization'), false);
                  expect(jsonDecode(request.body), {
                    'email': 'fixture@example.invalid',
                    'password': 'synthetic',
                  });
                  return ok({'token': 'new-fixture'});
                }
                expect(request.headers['authorization'], 'new-fixture');
                expect(request.url.queryParameters, isEmpty);
                return ok({
                  'user': {'_id': 'p1', 'name': 'Pic account'},
                });
              }),
            )
            ..token = 'old-fixture'
            ..onUnauthorized = (_) => expired++;
      addTearDown(client.close);
      expect(
        await client.login('fixture@example.invalid', 'synthetic'),
        'new-fixture',
      );
      expect(client.token, 'old-fixture');
      expect(client.userProfile!['username'], 'Pic account');
      expect(expired, 0);
    },
  );

  test('Pic mutations are never replayed after a transport failure', () async {
    var calls = 0;
    final client = PicClient(
      config: const ApiConfig(
        apiHosts: ['https://first.invalid', 'https://second.invalid'],
      ),
      transport: MockClient((_) async {
        calls++;
        throw http.ClientException('synthetic');
      }),
    )..token = 'fixture';
    addTearDown(client.close);
    await expectLater(
      client.toggleFavorite('book'),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });

  test(
    'switching while Pic downloads keeps its bound client and separate disk manifests',
    () async {
      final folder = await Directory.systemTemp.createTemp('kamico_sources_');
      addTearDown(() => folder.delete(recursive: true));
      final bytes = img.encodePng(img.Image(width: 2, height: 3));
      final sources = <ContentSource>[];
      final repo = DownloadRepository(
        root: () async => folder,
        fetchImage: (chapter, index) async {
          sources.add(chapter.source);
          return bytes;
        },
      );
      final jm = FixtureJm(), pic = FixturePic()..waitForChapter = true;
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: jm,
        picClient: pic,
        repository: repo,
      );
      addTearDown(session.dispose);
      const jmComic = Comic(id: 'same', title: 'JM');
      const picComic = Comic(
        id: 'same',
        title: 'Pic',
        source: ContentSource.pic,
      );
      await session.switchSource();
      await session.queue.enqueue(picComic, [
        const Chapter(id: 'chapter', title: 'PIC chapter'),
      ]);
      await session.switchSource();
      await session.queue.enqueue(jmComic, [
        const Chapter(id: 'chapter', title: 'JM chapter'),
      ]);
      pic.gate.complete();
      await session.queue.idle;
      expect(session.activeSource, ContentSource.jm);
      expect(jm.chapterCalls, ['chapter']);
      expect(pic.chapterCalls, ['chapter']);
      final entries = await repo.list();
      expect(entries.length, 2);
      expect(entries.map((e) => e.folder).toSet().length, 2);
      expect(sources, containsAll(ContentSource.values));
    },
  );

  test(
    'source sections never interleave and preserve within-source recency',
    () {
      final rows = sourceSections([
        const Comic(id: 'p1', title: 'P1', source: ContentSource.pic),
        const Comic(id: 'j2', title: 'J2'),
        const Comic(id: 'p2', title: 'P2', source: ContentSource.pic),
        const Comic(id: 'j1', title: 'J1'),
      ], (c) => c.source);
      expect(rows.map((r) => r.item?.id), [null, 'j2', 'j1', null, 'p1', 'p2']);
    },
  );

  test(
    'Pic images use their media URL and raw bytes, cache them, and never send account tokens',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'kamico_pic_images_',
      );
      addTearDown(() => folder.delete(recursive: true));
      final api = FixturePic()..token = 'never-send-to-image-server';
      expect(
        api.media({
          'fileServer': 'https://media.invalid/static/',
          'path': 'static/static/page.jpg',
        }),
        'https://media.invalid/static/page.jpg',
      );
      expect(
        api.media({
          'fileServer': 'https://storage1.picacomic.com',
          'path': 'tobeimg/cover.jpg',
        }),
        'https://img.picacomic.com/cover.jpg',
      );
      expect(
        api.media({
          'fileServer': 'https://media.invalid',
          'path': 'tobs/page.jpg',
        }),
        'https://media.invalid/static/page.jpg',
      );
      addTearDown(api.close);
      var requests = 0;
      final bytes = img.encodePng(img.Image(width: 2, height: 3));
      final images = ImageRepository(
        api,
        temporaryDirectory: () async => folder,
        transport: MockClient((request) async {
          requests++;
          expect(
            request.url.toString(),
            'https://media.invalid/static/page.jpg',
          );
          expect(request.headers.containsKey('authorization'), false);
          expect(request.headers.containsKey('X-Requested-With'), false);
          return http.Response.bytes(bytes, 200);
        }),
      );
      addTearDown(images.close);
      const chapter = ReaderChapter(
        id: 'non-numeric~1~ep',
        source: ContentSource.pic,
        scrambleId: 0,
        pages: [
          ReaderPage(path: 'https://media.invalid/static/page.jpg', name: '0'),
        ],
      );
      expect(await images.load(chapter, 0), bytes);
      expect(await images.load(chapter, 0), bytes);
      expect(requests, 1);
    },
  );

  test(
    'a rejected Pic token clears only Pic credentials, even while JM is active',
    () async {
      final jm = FixtureJm()..token = 'jm-fixture';
      final pic = PicClient(
        transport: MockClient((_) async => http.Response('{"code":401}', 401)),
      )..token = 'pic-fixture';
      final store = LocalStore(await SharedPreferences.getInstance());
      await store.saveToken('jm-fixture');
      await store.forSource(ContentSource.pic).saveToken('pic-fixture');
      final session = AppSession(store, client: jm, picClient: pic);
      addTearDown(session.dispose);
      await expectLater(pic.categories(), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      expect(session.activeSource, ContentSource.jm);
      expect(jm.token, 'jm-fixture');
      expect(pic.token, isNull);
      expect(await store.readToken(), 'jm-fixture');
      expect(await store.forSource(ContentSource.pic).readToken(), isNull);
      expect(session.forSource(ContentSource.pic).authExpired, true);
      expect(session.authExpired, false);
    },
  );

  test(
    'a late Pic profile response cannot restore a logged out account',
    () async {
      final response = Completer<http.Response>();
      final api = PicClient(transport: MockClient((_) => response.future))
        ..token = 'fixture';
      addTearDown(api.close);
      final pending = api.refreshProfile();
      api.token = null;
      api.userProfile = null;
      response.complete(
        ok({
          'user': {'_id': 'old-account', 'name': 'Old'},
        }),
      );
      await expectLater(pending, throwsA(isA<ApiException>()));
      expect(api.userProfile, isNull);
      expect(api.token, isNull);
    },
  );

  test(
    'Pic discovery search favorites comments and sign-in map through the existing comic workflow',
    () async {
      final calls = <String>[];
      final api = PicClient(
        transport: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          switch (request.url.path) {
            case '/collections':
              return ok({
                'collections': [
                  {
                    'title': 'Featured',
                    'comics': [picComic('a')],
                  },
                ],
              });
            case '/comics/random':
              return ok({
                'comics': [picComic('b')],
              });
            case '/categories':
              return ok({
                'categories': [
                  {'title': 'Category', 'active': true},
                  {'title': 'Hidden', 'active': false},
                ],
              });
            case '/comics/advanced-search':
              expect(jsonDecode(request.body), {
                'categories': [],
                'keyword': 'synthetic search',
                'sort': 'ld',
              });
              return ok({
                'comics': paged([picComic('c')], page: 2, pages: 3, total: 3),
              });
            case '/users/favourite':
              return ok({
                'comics': paged([picComic('d')]),
              });
            case '/comics/d/favourite':
              return ok({'action': 'un_favourite'});
            case '/comics/d/comments':
              if (request.method == 'POST') {
                expect(jsonDecode(request.body), {
                  'content': 'synthetic comment',
                });
                return ok({});
              }
              return ok({
                'comments': paged([
                  {
                    '_id': 'comment',
                    '_user': {'name': 'Reader'},
                    'content': 'Text',
                    'commentsCount': 1,
                  },
                ]),
              });
            case '/comments/comment/childrens':
              return ok({
                'comments': paged([
                  {
                    '_id': 'reply',
                    '_user': {'name': 'Other'},
                    'content': 'Reply',
                  },
                ]),
              });
            case '/users/punch-in':
              return ok({});
            case '/users/profile':
              return ok({
                'user': {'_id': 'u1', 'name': 'Fixture', 'isPunched': true},
              });
            default:
              throw StateError('unexpected ${request.url}');
          }
        }),
      )..token = 'fixture';
      addTearDown(api.close);
      expect(
        (await api.homeSections()).map((s) => s.items.single.source),
        everyElement(ContentSource.pic),
      );
      expect((await api.categories()).categories.single.name, 'Category');
      expect(
        (await api.search(
          'synthetic search',
          2,
          options: const SearchOptions(sort: 'ld'),
        )).more,
        true,
      );
      final favorites = ComicPage.fromJson(
        await api.favoriteFolder('0', 1, 'mr'),
        key: 'list',
      );
      expect(favorites.items.single.source, ContentSource.pic);
      await api.toggleFavorite('d');
      final comment = (await api.comments('d', 1))['list'][0];
      expect(comment['CID'], 'comment');
      expect(comment['replyTotal'], 1);
      expect((await api.replies('comment', 1))['list'][0]['CID'], 'reply');
      await api.comment('d', 'synthetic comment');
      await api.sign('u1', 'pic');
      expect(api.userProfile!['isPunched'], true);
      expect(calls, contains('POST /users/punch-in'));
    },
  );

  testWidgets(
    'single tap switches account, stays in My, and preserves both independent sessions',
    (tester) async {
      final jm = FixtureJm()
        ..token = 'jm'
        ..userProfile = {'username': 'JM account'};
      final pic = FixturePic();
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: jm,
        picClient: pic,
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(JmApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.text('JM account'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('content-source-toggle')));
      await tester.pumpAndSettle();
      expect(session.activeSource, ContentSource.pic);
      expect(find.text('未登录'), findsOneWidget);
      expect(find.text('Pic'), findsNothing);
      expect(find.byTooltip('切换内容源 · Pic'), findsOneWidget);
      expect(jm.token, 'jm');
      pic.token = 'pic';
      pic.userProfile = {'username': 'Pic account'};
      session.forSource(ContentSource.pic).notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Pic account'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('content-source-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('JM account'), findsOneWidget);
      expect(pic.token, 'pic');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cross-source history opens Pic reader with JM still selected and returns to Pic detail',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('kamico_route_');
      addTearDown(() => folder.delete(recursive: true));
      final repo = DownloadRepository(
        root: () async => folder,
        fetchImage: (_, index) async =>
            img.encodePng(img.Image(width: 2, height: 2)),
      );
      const comic = Comic(
        id: 'book',
        title: 'Pic offline',
        source: ContentSource.pic,
      );
      const chapter = Chapter(id: 'book~1~ep', title: 'First');
      await tester.runAsync(
        () => repo.save(
          comic,
          chapter,
          const ReaderChapter(
            id: 'book~1~ep',
            scrambleId: 0,
            pages: [ReaderPage(path: '', name: '0')],
          ),
          (_, _) {},
        ),
      );
      final pic = FixturePic();
      final session = AppSession(
        LocalStore(await SharedPreferences.getInstance()),
        client: FixtureJm(),
        picClient: pic,
        repository: repo,
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openProgress(
                  context,
                  session,
                  const ReadingProgress(
                    comic: comic,
                    chapterId: 'book~1~ep',
                    page: 0,
                  ),
                ),
                child: const Text('open cross-source'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open cross-source'));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(reader.session.source, ContentSource.pic);
      expect(reader.offline, isNotNull);
      expect(session.activeSource, ContentSource.jm);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final detail = tester.widget<DetailScreen>(find.byType(DetailScreen));
      expect(detail.session.source, ContentSource.pic);
      expect(session.activeSource, ContentSource.jm);
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    },
  );
}
