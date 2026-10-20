import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import '../data/app_log.dart';
import 'translations.dart';
import '../data/api_config.dart';
import '../data/download_repository.dart';
import '../data/download_queue.dart';
import '../data/system_fonts.dart';
import 'downloads.dart';
import '../data/image_repository.dart';
import '../data/jm_client.dart';
import '../data/local_store.dart';
import '../domain/models.dart';
import 'settings.dart';
import 'discovery.dart';
import 'bookcase.dart';
import 'design_system.dart';
import '../domain/card_layout.dart';
import 'cover_image.dart';
import '../app_identity.dart';
import '../data/platform_files.dart';
import '../data/comic_source.dart';
import '../data/pic_client.dart';

class AppSession extends ChangeNotifier {
  AppSession(
    this.store, {
    JmClient? client,
    ComicSource? picClient,
    DownloadRepository? repository,
  }) : api = client ?? JmClient(config: store.config),
       _root = null {
    logs = AppLog(store);
    api.onUnauthorized = _expired;
    api.onRequest = (path, method, status, ms) =>
        logs.record('API', '$method $path', status: status, milliseconds: ms);
    logs.record('APP', 'session_start');
    images = ImageRepository(api);
    downloads =
        repository ??
        DownloadRepository(
          fetchImage: (chapter, index) =>
              forSource(chapter.source).images.load(chapter, index),
          publishSourcePdf: (path, book, chapter, source) =>
              PlatformFiles.publishPdf(
                path,
                book,
                chapter,
                source: source == ContentSource.jm ? 'JM' : 'PIC',
                tree: store.preferences.getString('export_tree'),
              ),
        );
    queue = DownloadQueue(
      store: store,
      repository: downloads,
      loadJob: (job) => forSource(job.comic.source).api.chapter(job.chapter.id),
    );
    queue.addListener(_downloadChanged);
    _pic = AppSession._source(
      this,
      picClient ?? PicClient(config: store.forSource(ContentSource.pic).config),
    );
  }
  AppSession._source(AppSession root, this.api)
    : _root = root,
      store = root.store.forSource(api.source) {
    logs = root.logs;
    downloads = root.downloads;
    queue = root.queue;
    images = ImageRepository(api);
    api.onUnauthorized = _expired;
    api.onRequest = (path, method, status, ms) =>
        logs.record('API', '$method $path', status: status, milliseconds: ms);
  }
  final AppSession? _root;
  AppSession? _pic;
  AppSession get root => _root ?? this;
  ContentSource get source => api.source;
  bool get isPic => source == ContentSource.pic;
  AppSession forSource(ContentSource source) =>
      source == ContentSource.jm ? root : root._pic!;
  ContentSource get activeSource =>
      ContentSource.parse(root.store.preferences.getString('active_source'));
  AppSession get active => forSource(activeSource);
  Future<void> _sourceSwitches = Future.value();
  Future<void> switchSource() {
    final operation = root._sourceSwitches.then((_) async {
      final next = activeSource == ContentSource.jm
          ? ContentSource.pic
          : ContentSource.jm;
      await root.store.preferences.setString('active_source', next.id);
      if (!root._disposed) root.notifyListeners();
    });
    root._sourceSwitches = operation.catchError((Object _) {});
    return operation;
  }

  String prefKey(String name) => store.prefKey(name);
  String imageHostFor(Comic comic) =>
      forSource(comic.source).api.config.imageHost;
  String get avatarUrl {
    if (isPic) return '${api.userProfile?['avatar'] ?? ''}';
    final uid = '${api.userProfile?['uid'] ?? ''}';
    return RegExp(r'^\d+$').hasMatch(uid)
        ? '${api.config.imageHost}/media/users/$uid.jpg'
        : '';
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (_root != null && !root._disposed) root.notifyListeners();
  }

  final LocalStore store;
  final homeKey = GlobalKey<_HomeScreenState>();
  void returnHome(BuildContext context) {
    root.homeKey.currentState?._select(0);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  final _appearanceChanges = ChangeNotifier();
  ChangeNotifier get appearanceChanges => root._appearanceChanges;
  final ComicSource api;
  late final AppLog logs;
  Json get appearance => store.readMap('appearance');
  Future<void> setAppearance(String key, dynamic value) async {
    await store.writeMap('appearance', {...appearance, key: value});
    appearanceChanges.notifyListeners();
    notifyListeners();
  }

  late final ImageRepository images;
  late final DownloadRepository downloads;
  late final DownloadQueue queue;
  final _downloadStates = <String, String>{};
  final _offlineIds = <String>{};
  Set<String> get offlineIds => root._offlineIds;
  void rememberOffline(Iterable<OfflineChapter> entries) {
    final ids = entries.map((e) => e.comic.key).toSet();
    if (_disposed ||
        ids.length == offlineIds.length && ids.every(offlineIds.contains)) {
      return;
    }
    offlineIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  Future<void> refreshOffline() async {
    try {
      final entries = await downloads.list();
      if (_disposed) return;
      rememberOffline(entries);
    } catch (_) {
      /* Storage errors are shown in the offline library. */
    }
  }

  bool _disposed = false;
  bool authExpired = false;
  Future<void> _credentials = Future.value();
  void _expired(String rejectedToken) {
    if (_disposed || api.token != rejectedToken) return;
    api.token = null;
    api.userProfile = null;
    authExpired = true;
    _credentials = _credentials.then((_) => store.clearToken()).catchError((
      Object _,
    ) {
      storageError = '登录凭据未能清理，请重新登录或重试退出';
      if (!_disposed) logs.record('ACCOUNT', 'credential_clear_failed');
    });
    logs.record('ACCOUNT', 'session_expired');
    notifyListeners();
  }

  void _downloadChanged() {
    for (final entry in queue.jobs.entries) {
      if (_downloadStates[entry.key] != entry.value.state) {
        if (entry.value.state == 'done') unawaited(refreshOffline());
        logs.record('DOWNLOAD', entry.value.state);
        _downloadStates[entry.key] = entry.value.state;
      }
    }
    _downloadStates.removeWhere((key, _) => !queue.jobs.containsKey(key));
    notifyListeners();
  }

  String? get downloading => queue.jobs.values
      .where((j) => j.state == 'running')
      .firstOrNull
      ?.chapter
      .id;
  Future<EnqueueResult> download(Comic comic, Chapter chapter) =>
      queue.enqueue(comic, [chapter]);
  Future<void> _writes = Future.value();
  String? storageError;
  bool get loggedIn => api.token?.isNotEmpty == true;
  Future<void> restore() async {
    if (['sans-serif', 'serif', 'monospace'].contains(appearance['font'])) {
      await store.writeMap('appearance', {
        ...appearance,
        'font': 'system',
        'font_name': '跟随系统',
      });
    }
    final font = '${appearance['font'] ?? 'system'}';
    if (font.startsWith('device:')) {
      try {
        await SystemFontLibrary.load(font.substring(7));
      } catch (_) {
        logs.record('APP', 'font_unavailable');
      }
    }
    await PlatformFiles.privacy(
      store.preferences.getBool('privacy_window') ?? false,
    );
    api.token = await store.readToken();
    api.userProfile = store.readMap('profile');
    if (_root == null) {
      final other = forSource(ContentSource.pic);
      other.api.token = await other.store.readToken();
      other.api.userProfile = other.store.readMap('profile');
      await queue.restore();
      unawaited(refreshOffline());
      unawaited(other.autoSign());
    }
    unawaited(autoSign());
  }

  Future<void> login(String username, String password) async {
    final token = await api.login(username, password);
    final profile = api.userProfile;
    api.token = token;
    final write = _credentials.then((_) => store.saveToken(token));
    _credentials = write.catchError((Object _) {});
    try {
      await write;
    } catch (_) {
      if (api.token == token) api.token = null;
      rethrow;
    }
    if (api.token != token) {
      throw const ApiException('登录状态已变化，请重新登录', unauthorized: true);
    }
    api.userProfile = profile;
    authExpired = false;
    logs.record('ACCOUNT', 'login_ok');
    await store.writeMap('profile', api.userProfile ?? {});
    await store.preferences.setBool(prefKey('profile_pending'), false);
    await store.preferences.setString(
      prefKey('profile_updated'),
      DateTime.now().toIso8601String(),
    );
    unawaited(autoSign());
    notifyListeners();
  }

  Future<void> logout() async {
    api.token = null;
    final clear = _credentials.then((_) => store.clearToken());
    _credentials = clear.catchError((Object _) {});
    await clear;
    logs.record('ACCOUNT', 'logout');
    api.userProfile = null;
    authExpired = false;
    await store.writeMap('profile', {});
    notifyListeners();
  }

  Future<void> autoSign() async {
    if (!loggedIn ||
        !(store.preferences.getBool(prefKey('auto_sign')) ?? false)) {
      return;
    }
    final uid = '${api.userProfile?['uid'] ?? ''}';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (uid.isEmpty ||
        store.preferences.getString(prefKey('signed_$uid')) == today) {
      return;
    }
    try {
      final token = api.token;
      final data = await api.daily(uid);
      if (_disposed || api.token != token) return;
      var signed = false;
      void collect(dynamic value) {
        if (value is List) {
          for (final item in value) {
            collect(item);
          }
        } else if (value is Map &&
            integer(value['date']) == DateTime.now().day) {
          signed = value['signed'] == true || '${value['signed']}' == '1';
        }
      }

      collect(data['record']);
      if (!signed) {
        if (data['daily_id'] == null) throw const FormatException('签到记录缺少编号');
        await api.sign(uid, '${data['daily_id']}');
        await markProfilePending();
      }
      await store.preferences.setString(prefKey('signed_$uid'), today);
    } catch (_) {
      if (_disposed) return;
      storageError = '自动签到未成功，可在账号页重试';
      logs.record('ACCOUNT', 'auto_sign_failed');
    }
  }

  Future<void> configure(ApiConfig config) async {
    config.validate();
    await logout();
    await store.saveConfig(config);
    api.config = config;
    notifyListeners();
  }

  void progress(ReadingProgress progress) {
    if (store.preferences.getBool('privacy_no_history') ?? false) return;
    root._writes = root._writes
        .then((_) => store.saveProgress(progress))
        .then((_) {
          storageError = null;
          if (!_disposed) notifyListeners();
        })
        .catchError((Object error) {
          storageError = '阅读进度未保存，请检查本地存储';
          if (!_disposed) notifyListeners();
        });
  }

  Future<void> get savedProgress => root._writes;
  Future<void> markProfilePending() async {
    if (isPic) {
      await cacheProfile();
      return;
    }
    await store.preferences.setBool(prefKey('profile_pending'), true);
    if (!_disposed) notifyListeners();
  }

  Future<void> cacheProfile() async {
    await store.writeMap('profile', api.userProfile ?? {});
    await store.preferences.setBool(prefKey('profile_pending'), false);
    await store.preferences.setString(
      prefKey('profile_updated'),
      DateTime.now().toIso8601String(),
    );
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    api.onUnauthorized = null;
    if (_root == null) {
      _pic?.dispose();
      queue.removeListener(_downloadChanged);
      queue.dispose();
      logs.dispose();
    }
    api.close();
    api.onRequest = null;
    images.close();
    _appearanceChanges.dispose();
    super.dispose();
  }
}

class JmApp extends StatelessWidget {
  const JmApp({super.key, required this.session});
  final AppSession session;
  static final navigatorKey = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.appearanceChanges,
    builder: (context, _) {
      final prefs = session.appearance;
      final color = Color(integer(prefs['color'] ?? 0xff296b5c));
      final language = '${prefs['language'] ?? 'zh_CN'}';
      final selectedFont = '${prefs['font'] ?? 'system'}';
      final font =
          selectedFont == 'system' ||
              selectedFont.startsWith('device:') &&
                  !SystemFontLibrary.loaded(selectedFont)
          ? null
          : selectedFont;
      ThemeData theme(Brightness brightness) {
        final base = AppDesign.theme(color, brightness, font);
        return base.copyWith(
          textTheme: base.textTheme
              .apply(fontSizeFactor: 1, fontSizeDelta: 0)
              .apply(
                bodyColor: base.colorScheme.onSurface,
                displayColor: base.colorScheme.onSurface,
              )
              .mapStyles(prefs['bold'] == true, prefs['italic'] == true),
        );
      }

      return MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: switch (prefs['theme']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        locale: language == 'auto'
            ? null
            : language == 'en'
            ? const Locale('en')
            : Locale('zh', language == 'zh_TW' ? 'TW' : 'CN'),
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('zh', 'TW'),
          Locale('en'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: AppTextScaler(
              MediaQuery.textScalerOf(context),
              ((prefs['scale'] as num?)?.toDouble() ?? 1).clamp(.8, 1.4),
            ),
          ),
          child: ListenableBuilder(
            listenable: session,
            child: child,
            builder: (context, navigator) => Column(
              children: [
                if (session.active.authExpired)
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: SafeArea(
                      bottom: false,
                      child: ListTile(
                        title: const AppText('登录已失效，当前页面已保留'),
                        trailing: TextButton(
                          onPressed: () => navigatorKey.currentState!.push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  LoginScreen(session: session.active),
                            ),
                          ),
                          child: const AppText('重新登录'),
                        ),
                      ),
                    ),
                  ),
                Expanded(child: navigator!),
              ],
            ),
          ),
        ),
        home: HomeScreen(key: session.homeKey, session: session),
        navigatorKey: navigatorKey,
      );
    },
  );
}

class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

extension _FontStyles on TextTheme {
  TextTheme mapStyles(bool bold, bool italic) {
    TextStyle? apply(TextStyle? style) => style?.copyWith(
      fontWeight: bold ? FontWeight.bold : style.fontWeight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
    return copyWith(
      displayLarge: apply(displayLarge),
      displayMedium: apply(displayMedium),
      displaySmall: apply(displaySmall),
      headlineLarge: apply(headlineLarge),
      headlineMedium: apply(headlineMedium),
      headlineSmall: apply(headlineSmall),
      titleLarge: apply(titleLarge),
      titleMedium: apply(titleMedium),
      titleSmall: apply(titleSmall),
      bodyLarge: apply(bodyLarge),
      bodyMedium: apply(bodyMedium),
      bodySmall: apply(bodySmall),
      labelLarge: apply(labelLarge),
      labelMedium: apply(labelMedium),
      labelSmall: apply(labelSmall),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _visited = <int>{0};
  final _visitedSources = <ContentSource>{};
  void _select(int value) => setState(() {
    _visited.add(value);
    _tab = value;
  });
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    _visitedSources.add(session.activeSource);
    final destinations = [
      NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: const Icon(Icons.explore),
        label: AppTranslations.text(context, '发现'),
      ),
      NavigationDestination(
        icon: Icon(Icons.bookmarks_outlined),
        selectedIcon: const Icon(Icons.bookmarks),
        label: AppTranslations.text(context, '书架'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.history),
        label: AppTranslations.text(context, '历史'),
      ),
      NavigationDestination(
        icon: Icon(Icons.download_outlined),
        selectedIcon: const Icon(Icons.download),
        label: AppTranslations.text(context, '下载'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.tune),
        label: AppTranslations.text(context, '我的'),
      ),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 600;
    Widget page(int index) => switch (index) {
      0 => IndexedStack(
        index: session.activeSource.index,
        children: [
          for (final source in ContentSource.values)
            TickerMode(
              enabled: source == session.activeSource,
              child: !_visitedSources.contains(source)
                  ? const SizedBox.shrink()
                  : DiscoveryScreen(
                      key: ValueKey(source),
                      session: session.forSource(source),
                    ),
            ),
        ],
      ),
      1 => IndexedStack(
        index: session.activeSource.index,
        children: [
          for (final source in ContentSource.values)
            TickerMode(
              enabled: source == session.activeSource,
              child: !_visitedSources.contains(source)
                  ? const SizedBox.shrink()
                  : BookcaseScreen(
                      key: ValueKey(source),
                      session: session.forSource(source),
                      active: _tab == 1 && source == session.activeSource,
                    ),
            ),
        ],
      ),
      2 => HistoryScreen(session: session.active),
      3 => DownloadScreen(session: session.active),
      _ => SettingsScreen(session: session.active),
    };
    final body = IndexedStack(
      index: _tab,
      children: [
        for (var index = 0; index < 5; index++)
          TickerMode(
            enabled: index == _tab,
            child: _visited.contains(index)
                ? KeyedSubtree(key: ValueKey(index), child: page(index))
                : const SizedBox.shrink(),
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: AppText([appName, '书架', '阅读历史', '离线下载', '我的'][_tab]),
        actions: [
          if (_tab == 0 || _tab == 4)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ContentSourceButton(session: session),
            ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: destinations
                  .map(
                    (e) => NavigationRailDestination(
                      icon: e.icon,
                      selectedIcon: e.selectedIcon,
                      label: AppText(e.label),
                    ),
                  )
                  .toList(),
            ),
          Expanded(child: AppPageBody(child: body)),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _select,
              destinations: destinations,
            ),
    );
  }
}

class ContentSourceButton extends StatelessWidget {
  const ContentSourceButton({super.key, required this.session});
  final AppSession session;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton.filledTonal(
      key: const ValueKey('content-source-toggle'),
      tooltip:
          '${AppTranslations.text(context, '切换内容源')} · ${session.activeSource.label}',
      onPressed: session.switchSource,
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        shape: const CircleBorder(),
        backgroundColor:
            theme.navigationBarTheme.indicatorColor ??
            theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
      ),
      icon: const Icon(Icons.swap_horiz),
    );
  }
}

class ComicCard extends StatelessWidget {
  const ComicCard({
    super.key,
    required this.comic,
    required this.imageHost,
    required this.onTap,
    this.layout,
  });
  final Comic comic;
  final String imageHost;
  final VoidCallback onTap;
  final ComicCardLayout? layout;
  @override
  Widget build(BuildContext context) {
    final session = context.findAncestorWidgetOfExactType<JmApp>()?.session;
    final states = <String>[
      if (session?.store.hasRead(comic.key) == true) '读过',
      if (session?.store.localFavorites.containsKey(comic.key) == true) '已收藏',
      if (session?.offlineIds.contains(comic.key) == true) '已下载',
    ];
    final presentation =
        layout ??
        ComicCardLayout.fromPreferences(
          context.findAncestorWidgetOfExactType<JmApp>()?.session.appearance ??
              {},
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(url: comic.coverUrl(imageHost)),
                  if (states.isNotEmpty)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Tooltip(
                        message: states.join(' · '),
                        child: Badge(
                          label: presentation.compact
                              ? null
                              : Text(states.last),
                          child: Icon(
                            states.contains('已下载')
                                ? Icons.offline_pin
                                : Icons.bookmark,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(presentation.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: presentation.titleLines,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: presentation.fontSize,
                      height: presentation.titleHeight / presentation.fontSize,
                    ),
                  ),
                  if (presentation.showAuthor) ...[
                    const SizedBox(height: 4),
                    Text(
                      comic.authors.join(' / '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 4 / 3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
