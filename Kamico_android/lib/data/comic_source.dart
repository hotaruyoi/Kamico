import '../domain/models.dart';
import 'api_config.dart';

/// The shared comic workflow. Each adapter owns authentication and wire formats.
abstract interface class ComicSource {
  ContentSource get source;
  ApiConfig get config;
  set config(ApiConfig value);
  String? get token;
  set token(String? value);
  Json? get userProfile;
  set userProfile(Json? value);
  set onUnauthorized(void Function(String)? value);
  set onRequest(void Function(String, String, int?, int)? value);
  Future<List<Comic>> home();
  Future<List<HomeSection>> homeSections();
  Future<ComicPage> latest(int page);
  Future<CategoryCatalog> categories();
  Future<ComicPage> category(String slug, int page, {String sort = 'mr'});
  Future<ComicPage> search(
    String text,
    int page, {
    SearchOptions options = const SearchOptions(),
  });
  Future<ComicPage> serialization(int day, String type, int page);
  Future<List<Json>> weekIssues();
  Future<ComicPage> week(String id, String type, int page);
  ComicDetail? cachedDetail(String id, {bool allowStale = false});
  void invalidateDetail(String id);
  Future<ComicDetail> detail(String id, {bool refresh = false});
  Future<ReaderChapter> chapter(String id);
  Future<ComicPage> favorites(int page);
  Future<Json> favoriteFolder(String folder, int page, String sort);
  Future<void> editFavoriteFolder(
    String action, {
    String id = '',
    String name = '',
    String comicId = '',
  });
  Future<ComicPage> cloudHistory(int page);
  Future<void> toggleFavorite(String id);
  Future<String> login(String username, String password);
  Future<Json> daily(String uid);
  Future<String> sign(String uid, String dailyId, {String date = ''});
  Future<String> purchase(String id);
  Future<Json> comments(String id, int page, {String? uid});
  Future<String> comment(String id, String content, {String reply = ''});
  void close();
}
