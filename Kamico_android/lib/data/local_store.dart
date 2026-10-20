import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';
import 'api_config.dart';
import 'pic_client.dart';

class LocalStore {
  LocalStore(
    this.preferences, {
    FlutterSecureStorage? secure,
    this.source = ContentSource.jm,
  }) : secure = secure ?? const FlutterSecureStorage();
  final SharedPreferences preferences;
  final FlutterSecureStorage secure;
  final ContentSource source;
  LocalStore forSource(ContentSource value) => value == source
      ? this
      : LocalStore(preferences, secure: secure, source: value);
  String prefKey(String key) => source.preference(key);
  String _mapKey(String key) =>
      ['profile', 'search_options'].contains(key) ? prefKey(key) : key;
  String? _favoritesRaw, _historyRaw, _chaptersRaw;
  Map<String, Json> _favorites = const {};
  List<ReadingProgress> _history = const [];
  Map<String, ReadingProgress> _recent = const {}, _chapters = const {};
  Json readMap(String key, [Json fallback = const {}]) {
    try {
      return jsonDecode(
            preferences.getString(_mapKey(key)) ?? jsonEncode(fallback),
          )
          as Json;
    } catch (_) {
      return Map.of(fallback);
    }
  }

  Future<void> writeMap(String key, Json data) async {
    await preferences.setString(_mapKey(key), jsonEncode(data));
  }

  Map<String, String> get localFolders =>
      readMap('local_folders', {'0': '默认收藏夹'}).map((k, v) => MapEntry(k, '$v'));
  Map<String, Json> get localFavorites {
    final raw = preferences.getString('local_favorites') ?? '{}';
    if (raw != _favoritesRaw) {
      try {
        _favorites = Map.unmodifiable(
          (jsonDecode(raw) as Json).map(
            (k, v) => MapEntry(k, Map<String, dynamic>.unmodifiable(v as Map)),
          ),
        );
      } catch (_) {
        _favorites = const {};
      }
      _favoritesRaw = raw;
    }
    return _favorites;
  }

  bool hasRead(String comic) => recentProgress(comic) != null;
  ReadingProgress? recentProgress(String comic) {
    history;
    return _recent[comic];
  }

  Future<void> addLocal(Comic comic, {String folder = '0'}) async {
    final items = Map<String, Json>.of(localFavorites);
    items[comic.key] = {'comic': comic.toJson(), 'folder': folder};
    await writeMap('local_favorites', items);
  }

  Future<void> removeLocal(Iterable<String> ids) async {
    final items = Map<String, Json>.of(localFavorites);
    for (final id in ids) {
      items.remove(id);
    }
    await writeMap('local_favorites', items);
  }

  Future<void> moveLocal(Iterable<String> ids, String folder) async {
    if (!localFolders.containsKey(folder)) {
      throw const FormatException('收藏夹不存在');
    }
    final items = localFavorites.map(
      (k, v) => MapEntry(k, Map<String, dynamic>.of(v)),
    );
    for (final id in ids) {
      if (items[id] != null) items[id]!['folder'] = folder;
    }
    await writeMap('local_favorites', items);
  }

  Future<void> createLocalFolder(String name) async {
    final folders = localFolders;
    folders['${DateTime.now().microsecondsSinceEpoch}'] = name;
    await writeMap('local_folders', folders);
  }

  Future<void> deleteLocalFolder(String id) async {
    if (id == '0') return;
    await moveLocal(
      localFavorites.entries
          .where((e) => e.value['folder'] == id)
          .map((e) => e.key),
      '0',
    );
    final folders = localFolders..remove(id);
    await writeMap('local_folders', folders);
  }

  List<String> get blockedWords =>
      preferences.getStringList('blocked_words') ?? [];
  bool visible(Comic comic) {
    final title = preferences.getBool('block_title') ?? true;
    final tags = preferences.getBool('block_tags') ?? true;
    final text =
        '${title ? comic.title : ''} ${tags ? comic.tags.join(' ') : ''}'
            .toLowerCase();
    return !blockedWords.any(
      (word) => word.isNotEmpty && text.contains(word.toLowerCase()),
    );
  }

  Future<void> deleteHistory(Iterable<String> ids) async {
    final remove = ids.toSet();
    final chapters = readMap('chapter_progress')
      ..removeWhere(
        (key, value) =>
            remove.contains(ReadingProgress.fromJson(value as Json).comic.key),
      );
    await writeMap('chapter_progress', chapters);
    await preferences.setString(
      'history',
      jsonEncode(
        history
            .where((e) => !remove.contains(e.comic.key))
            .map((e) => e.toJson())
            .toList(),
      ),
    );
  }

  ApiConfig get config {
    final raw = preferences.getString(prefKey('api_config'));
    final defaults = source == ContentSource.pic
        ? PicClient.defaults
        : const ApiConfig();
    if (raw == null) return defaults;
    try {
      final config = ApiConfig.fromJson(jsonDecode(raw) as Json)..validate();
      return config;
    } catch (_) {
      return defaults;
    }
  }

  Future<void> saveConfig(ApiConfig config) async {
    config.validate();
    await preferences.setString(
      prefKey('api_config'),
      jsonEncode(config.toJson()),
    );
  }

  Future<String?> readToken() => secure.read(key: prefKey('session_token'));
  Future<void> saveToken(String token) =>
      secure.write(key: prefKey('session_token'), value: token);
  Future<void> clearToken() => secure.delete(key: prefKey('session_token'));
  List<String> get searchHistory =>
      preferences.getStringList(prefKey('search_history')) ?? [];
  Future<void> rememberSearch(String text) async {
    if (text.trim().isEmpty) return;
    await preferences.setStringList(
      prefKey('search_history'),
      [
        text.trim(),
        ...searchHistory.where((e) => e != text.trim()),
      ].take(30).toList(),
    );
  }

  Future<void> clearSearchHistory() async {
    await preferences.remove(prefKey('search_history'));
  }

  List<ReadingProgress> get history {
    final raw = preferences.getString('history') ?? '[]';
    if (raw != _historyRaw) {
      try {
        _history = List.unmodifiable(
          (jsonDecode(raw) as List).map(
            (e) => ReadingProgress.fromJson(e as Json),
          ),
        );
      } catch (_) {
        _history = const [];
      }
      _recent = {for (final p in _history.reversed) p.comic.key: p};
      _historyRaw = raw;
    }
    return _history;
  }

  Future<void> saveProgress(ReadingProgress progress) async {
    final chapters = readMap('chapter_progress');
    chapters['${progress.comic.key}:${progress.chapterId}'] = progress.toJson();
    await writeMap('chapter_progress', chapters);
    final entries = history
        .where((e) => e.comic.key != progress.comic.key)
        .toList();
    entries.insert(0, progress);
    await preferences.setString(
      'history',
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  ReadingProgress? chapterProgress(String comic, String chapter) {
    final raw = preferences.getString('chapter_progress') ?? '{}';
    if (raw != _chaptersRaw) {
      try {
        _chapters = (jsonDecode(raw) as Json).map(
          (key, value) =>
              MapEntry(key, ReadingProgress.fromJson(value as Json)),
        );
      } catch (_) {
        _chapters = const {};
      }
      _chaptersRaw = raw;
    }
    final saved = _chapters['$comic:$chapter'];
    if (saved != null) return saved;
    final recent = recentProgress(comic);
    return recent?.chapterId == chapter ? recent : null;
  }
}
