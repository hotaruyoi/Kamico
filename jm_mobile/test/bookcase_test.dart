import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jm_mobile/data/local_store.dart';
import 'package:jm_mobile/domain/models.dart';
import 'discovery_test.dart' show apiFor;

void main() {
  test(
    'local groups survive restart and deleting a group preserves its comics',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      await store.createLocalFolder('待读');
      final folder = store.localFolders.keys.singleWhere((id) => id != '0');
      await store.addLocal(const Comic(id: '1', title: 'One'));
      await store.moveLocal(['1'], folder);
      expect(LocalStore(prefs).localFavorites['1']!['folder'], folder);
      await store.deleteLocalFolder(folder);
      expect(store.localFavorites['1']!['folder'], '0');
      expect(store.localFolders.keys, ['0']);
      await store.removeLocal(['1']);
      expect(store.localFavorites, isEmpty);
    },
  );
  test(
    'history supports deletion without touching remaining progress',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      await store.saveProgress(
        const ReadingProgress(
          comic: Comic(id: '1', title: 'One'),
          chapterId: '10',
          page: 4,
        ),
      );
      await store.saveProgress(
        const ReadingProgress(
          comic: Comic(id: '2', title: 'Two'),
          chapterId: '20',
          page: 8,
        ),
      );
      await store.deleteHistory(['1']);
      expect(store.history.single.page, 8);
    },
  );
  test('title and provided tags are filtered independently', () async {
    SharedPreferences.setMockInitialValues({
      'blocked_words': ['WORD'],
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.visible(const Comic(id: '1', title: 'a word')), false);
    expect(
      store.visible(const Comic(id: '2', title: 'safe', tags: ['word'])),
      false,
    );
    await store.preferences.setBool('block_title', false);
    expect(store.visible(const Comic(id: '1', title: 'a word')), true);
    expect(
      store.visible(const Comic(id: '2', title: 'safe', tags: ['word'])),
      false,
    );
  });
  test(
    'favorite folder operations preserve exact form fields, history uses GET query',
    () async {
      final api = apiFor((request) {
        if (request.url.path == '/watch_list/') {
          expect(request.url.queryParameters['page'], '2');
          return {'total': 0, 'list': []};
        }
        expect(request.method, 'POST');
        expect(request.url.path, '/favorite_folder/');
        expect(request.bodyFields, {
          'type': 'move',
          'folder_id': '9',
          'aid': '42',
        });
        return {'status': 'ok', 'msg': 'ok'};
      });
      addTearDown(api.close);
      await api.editFavoriteFolder('move', id: '9', comicId: '42');
      await api.cloudHistory(2);
    },
  );
}
