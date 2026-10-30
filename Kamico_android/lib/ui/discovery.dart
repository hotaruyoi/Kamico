import 'translations.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'app.dart';
import 'detail_reader.dart';
import 'dialogs.dart';
import 'design_system.dart';
import '../domain/card_layout.dart';
import 'card_density.dart';
import 'reading_navigation.dart';
import 'search_filters.dart';
import 'content_filter.dart';
import 'failure.dart';
import 'comic_browser.dart';
import 'filled_select.dart';
import 'motion.dart';
import '../domain/discovery_shortcut.dart';

Future<void> openComic(
  BuildContext context,
  AppSession session,
  Comic comic, {
  List<Comic> related = const [],
  bool replace = false,
}) async {
  session = session.forSource(comic.source);
  if (comic.id.startsWith('local_')) {
    try {
      final chapters = (await session.downloads.list())
          .where((e) => e.comic.key == comic.key)
          .toList();
      if (!context.mounted) return;
      final route = MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(comic.title)),
          body: ListView(
            children: chapters
                .map(
                  (entry) => ListTile(
                    title: Text(entry.chapter.title),
                    subtitle: AppText('${entry.count} 页'),
                    onTap: () =>
                        openChapter(context, session, comic, entry.chapter),
                  ),
                )
                .toList(),
          ),
        ),
      );
      if (replace) {
        Navigator.of(context).pushReplacement(route);
      } else {
        await Navigator.of(context).push(route);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: AppText('$e')));
      }
    }
    return;
  }
  final route = MaterialPageRoute<void>(
    builder: (_) => MediaQuery.sizeOf(context).width >= 1000
        ? ComicBrowser(session: session, selected: comic, items: related)
        : DetailScreen(session: session, comic: comic),
  );
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    await Navigator.of(context).push(route);
  }
}

Future<void> openProgress(
  BuildContext context,
  AppSession session,
  ReadingProgress progress,
) async {
  return openChapter(
    context,
    session,
    progress.comic,
    Chapter(id: progress.chapterId, title: '继续阅读'),
    checkAccess: true,
    returnToComic: true,
  );
}

void openSearch(
  BuildContext context,
  AppSession session,
  String text, {
  String type = 'site',
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SearchScreen(session: session, initialText: text, initialType: type),
    ),
  );
}

const sorts = {
  'mr': '最新',
  'mv': '总排行',
  'mv_m': '月排行',
  'mv_w': '周排行',
  'mv_t': '日排行',
  'mp': '最多图片',
  'tf': '最多爱心',
};

Widget selectOption(
  String label,
  String value,
  Map<String, String> choices,
  ValueChanged<String> onChanged,
) => FilledSelect(
  label: label,
  value: value,
  choices: choices,
  onChanged: onChanged,
);

class ComicGrid extends StatelessWidget {
  const ComicGrid({super.key, required this.session, required this.items});
  final AppSession session;
  final List<Comic> items;
  @override
  Widget build(BuildContext context) {
    final visible = items.where(session.store.visible).toList();
    if (visible.isEmpty) {
      return AppStatus(
        icon: Icons.filter_alt_off_outlined,
        title: items.isEmpty ? '暂无结果' : '当前内容已被屏蔽',
        message: '可以调整搜索条件或设备内屏蔽规则',
        action: TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ContentFilterScreen(session: session),
            ),
          ),
          child: const AppText('调整屏蔽规则'),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => GridView.builder(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: comicGridDelegate(
          session,
          box.maxWidth - 24,
          scaler: MediaQuery.textScalerOf(context),
        ),
        itemCount: visible.length,
        itemBuilder: (_, i) => ComicCard(
          comic: visible[i],
          layout: ComicCardLayout.fromPreferences(session.appearance),
          imageHost: session.api.config.imageHost,
          onTap: () =>
              openComic(context, session, visible[i], related: visible),
        ),
      ),
    );
  }
}

class PagedComics extends StatefulWidget {
  const PagedComics({
    super.key,
    required this.session,
    required this.load,
    this.header,
  });
  final AppSession session;
  final Future<ComicPage> Function(int) load;
  final Widget? header;
  @override
  State<PagedComics> createState() => _PagedComicsState();
}

class _PagedComicsState extends State<PagedComics> {
  List<Comic> _items = [];
  int _page = 1, _total = 0, _size = 0, _generation = 0;
  bool _busy = true, _more = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page) async {
    if (page < 1) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.load(page);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = result.items;
        _page = page;
        _total = result.total;
        if (page == 1) _size = result.items.length;
        _more = result.more ?? (_size > 0 && page * _size < _total);
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_busy) const LinearProgressIndicator(),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _load(_page),
          child: LayoutBuilder(
            builder: (context, box) {
              final visible = _items
                  .where(widget.session.store.visible)
                  .toList();
              final delegate = comicGridDelegate(
                widget.session,
                box.maxWidth - 24,
                scaler: MediaQuery.textScalerOf(context),
              );
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (widget.header != null)
                    SliverToBoxAdapter(child: widget.header!),
                  if (_error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppFailure(
                        error: _error!,
                        retry: () => _load(_page),
                        session: widget.session,
                      ),
                    )
                  else if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _busy
                          ? const SizedBox.shrink()
                          : AppStatus(
                              icon: Icons.search_off,
                              title: _items.isEmpty ? '暂无结果' : '当前内容已被屏蔽',
                              message: '请调整筛选或搜索关键词，再试一次',
                              action: _items.isEmpty
                                  ? null
                                  : TextButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => ContentFilterScreen(
                                            session: widget.session,
                                          ),
                                        ),
                                      ),
                                      child: const AppText('调整屏蔽规则'),
                                    ),
                            ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: SliverGrid.builder(
                        gridDelegate: delegate,
                        itemCount: visible.length,
                        itemBuilder: (_, i) => ComicCard(
                          comic: visible[i],
                          layout: ComicCardLayout.fromPreferences(
                            widget.session.appearance,
                          ),
                          imageHost: widget.session.api.config.imageHost,
                          onTap: () => openComic(
                            context,
                            widget.session,
                            visible[i],
                            related: visible,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: Wrap(
          runSpacing: 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: AppTranslations.text(context, '上一页'),
              onPressed: _busy || _page == 1 ? null : () => _load(_page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final input = await prompt(
                        context,
                        '跳转页码',
                        initial: '$_page',
                        numeric: true,
                      );
                      final target = int.tryParse(input ?? '');
                      if (target != null &&
                          target > 0 &&
                          mounted &&
                          (_total == 0 ||
                              _size == 0 ||
                              target <= (_total / _size).ceil())) {
                        await _load(target);
                      }
                    },
              child: AppText(
                _total > 0 ? '第 $_page 页 · 共 $_total 本' : '第 $_page 页',
              ),
            ),
            IconButton(
              tooltip: AppTranslations.text(context, '下一页'),
              onPressed: _busy || !_more ? null : () => _load(_page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    ],
  );
}

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  late Future<List<HomeSection>> _sections;
  bool _fadeStart = false, _fadeEnd = true;
  Object? _accountScope;
  void _sessionChanged() {
    final scope = (widget.session.api.token, widget.session.api.config);
    if (scope == _accountScope || !mounted) return;
    _accountScope = scope;
    setState(() {
      _sections = widget.session.api.homeSections();
    });
  }

  @override
  void initState() {
    super.initState();
    _sections = widget.session.api.homeSections();
    _accountScope = (widget.session.api.token, widget.session.api.config);
    widget.session.addListener(_sessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  void _push(String title, Widget child) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: AppText(title)),
        body: AppPageBody(child: child),
      ),
    ),
  );
  Widget _shortcuts() => LayoutBuilder(
    builder: (context, box) {
      final shortcuts = discoveryShortcutOrder(
        widget.session.appearance['discovery_shortcut_order'],
      ).where((item) => item.supports(widget.session.source)).toList();
      return SizedBox(
        height: 64,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis != Axis.horizontal) return false;
            final start = notification.metrics.extentBefore > 1;
            final end = notification.metrics.extentAfter > 1;
            if (start != _fadeStart || end != _fadeEnd) {
              setState(() {
                _fadeStart = start;
                _fadeEnd = end;
              });
            }
            return false;
          },
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                _fadeStart ? Colors.transparent : Colors.white,
                Colors.white,
                Colors.white,
                _fadeEnd ? Colors.transparent : Colors.white,
              ],
              stops: const [0, .045, .955, 1],
            ).createShader(bounds),
            child: ListView.separated(
              key: PageStorageKey(
                'discovery-shortcuts:${widget.session.source.id}',
              ),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              itemCount: shortcuts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = shortcuts[index];
                return SizedBox(
                  width: (box.maxWidth - 48) / 3,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    key: ValueKey('shortcut-${item.name}'),
                    onPressed: () => _push(item.label, switch (item) {
                      DiscoveryShortcut.category => CatalogScreen(
                        session: widget.session,
                      ),
                      DiscoveryShortcut.ranking => CatalogScreen(
                        session: widget.session,
                        initialSort: 'mv',
                      ),
                      DiscoveryShortcut.latest => PagedComics(
                        session: widget.session,
                        load: widget.session.api.latest,
                      ),
                      _ => ScheduleScreen(
                        session: widget.session,
                        weekly: item == DiscoveryShortcut.weekly,
                      ),
                    }),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.icon, size: 18),
                          const SizedBox(width: 6),
                          AppText(item.label),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
  Widget _header() => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SearchBar(
            hintText: AppTranslations.text(
              context,
              widget.session.isPic ? '搜索标题、作者或标签' : '搜索标题、作者、标签或 JM 编号',
            ),
            leading: const Icon(Icons.search),
            onTap: () => openSearch(context, widget.session, ''),
            readOnly: true,
            trailing: [CardDensityButton(session: widget.session)],
          ),
        ),
        _shortcuts(),
        if (!(widget.session.store.preferences.getBool('privacy_hide_recent') ??
            false))
          if (widget.session.store.history.firstOrNull case final progress?)
            ListTile(
              leading: const Icon(Icons.history),
              title: const AppText('继续阅读'),
              subtitle: Text(
                '${progress.comic.source.label} · ${progress.comic.title} · ${progress.page + 1} 页',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.play_arrow),
              onTap: () => openProgress(context, widget.session, progress),
            ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final gridDelegate = comicGridDelegate(
        widget.session,
        (box.maxWidth - 24).clamp(1, double.infinity),
        scaler: MediaQuery.textScalerOf(context),
      );
      final cardLayout = ComicCardLayout.fromPreferences(
        widget.session.appearance,
      );
      return FutureBuilder<List<HomeSection>>(
        future: _sections,
        builder: (context, snapshot) {
          final sections =
              snapshot.data
                  ?.map(
                    (section) => HomeSection(
                      title: section.title,
                      type: section.type,
                      id: section.id,
                      slug: section.slug,
                      filter: section.filter,
                      items: section.items
                          .where(widget.session.store.visible)
                          .toList(),
                    ),
                  )
                  .toList() ??
              const <HomeSection>[];
          Widget? status;
          if (snapshot.hasError) {
            status = AppFailure(
              error: snapshot.error!,
              retry: () => setState(() {
                _sections = widget.session.api.homeSections();
              }),
              session: widget.session,
            );
          } else if (snapshot.data == null) {
            status = const Center(child: CircularProgressIndicator());
          } else if (sections.every((s) => s.items.isEmpty) &&
              snapshot.data!.any((s) => s.items.isNotEmpty)) {
            status = AppStatus(
              icon: Icons.filter_alt_off_outlined,
              title: '当前内容已被屏蔽',
              message: '推荐已返回，但都命中了设备内屏蔽规则',
              action: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ContentFilterScreen(session: widget.session),
                  ),
                ),
                child: const AppText('调整屏蔽规则'),
              ),
            );
          } else if (sections.isEmpty) {
            status = const AppStatus(
              icon: Icons.explore_outlined,
              title: '暂无推荐',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              final future = widget.session.api.homeSections();
              setState(() {
                _sections = future;
              });
              // FutureBuilder owns error rendering; refresh must not leak its error.
              try {
                await future;
              } catch (_) {}
            },
            child: CustomScrollView(
              key: PageStorageKey('discovery-feed:${widget.session.source.id}'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFloatingHeader(
                  key: const ValueKey('discovery-floating-header'),
                  animationStyle: AppMotion.sheet(context),
                  snapMode: FloatingHeaderSnapMode.overlay,
                  child: _header(),
                ),
                if (status != null)
                  SliverFillRemaining(child: status)
                else ...[
                  for (final section in sections) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: AppText(
                                section.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            TextButton(
                              onPressed: () => _push(
                                section.title,
                                ComicGrid(
                                  session: widget.session,
                                  items: section.items,
                                ),
                              ),
                              child: const AppText('查看全部'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => ComicCard(
                            comic: section.items[i],
                            layout: cardLayout,
                            imageHost: widget.session.api.config.imageHost,
                            onTap: () => openComic(
                              context,
                              widget.session,
                              section.items[i],
                              related: section.items,
                            ),
                          ),
                          childCount: section.items.length.clamp(
                            0,
                            gridDelegate.crossAxisCount * 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          );
        },
      );
    },
  );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.session,
    this.initialText = '',
    this.initialType = 'site',
  });
  final AppSession session;
  final String initialText, initialType;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late TextEditingController _text;
  late String _type;
  String _sort = 'mr', _year = '', _month = '', _query = '';
  int _revision = 0;
  SearchOptions _applied = const SearchOptions();
  bool _filtersOpen = false;
  void _saveSearch() {
    widget.session.store.writeMap('search_options', {
      'sort': _sort,
      'type': _type,
      'year': _year,
      'month': _month,
      'query': _query,
    });
  }

  void _apply(SearchOptions options) => setState(() {
    _filtersOpen = false;
    _applied = options;
    _sort = options.sort;
    _type = options.type;
    _year = options.year;
    _month = options.month;
    _revision++;
    _saveSearch();
  });
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
    _type = widget.initialType;
    final saved = widget.session.store.readMap('search_options');
    _sort = '${saved['sort'] ?? (widget.session.isPic ? 'dd' : 'mr')}';
    _year = '${saved['year'] ?? ''}';
    _month = '${saved['month'] ?? ''}';
    if (widget.initialText.isEmpty) {
      _type = '${saved['type'] ?? _type}';
      _query = '${saved['query'] ?? ''}';
      _text.text = _query;
    }
    _applied = SearchOptions(
      type: _type,
      sort: _sort,
      year: _year,
      month: _month,
    );
    if (widget.initialText.isNotEmpty) _submit();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final id = widget.session.isPic
        ? (RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(text) ? text : null)
        : SearchOptions.directId(text);
    if (id != null) {
      openComic(
        context,
        widget.session,
        Comic(
          id: id,
          title: '${widget.session.source.label} $id',
          source: widget.session.source,
        ),
      );
      return;
    }
    await widget.session.store.rememberSearch(text);
    if (mounted) {
      setState(() {
        _query = text;
        _applied = SearchOptions(
          sort: _sort,
          type: _type,
          year: _year,
          month: _month,
        );
        _revision++;
        _saveSearch();
      });
    }
  }

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SearchBar(
          controller: _text,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          onChanged: (value) => setState(() {
            if (value.trim().isEmpty) _query = '';
          }),
          trailing: [
            IconButton(
              tooltip: '清空搜索',
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() {
                _text.clear();
                _query = '';
              }),
            ),
          ],
          hintText: AppTranslations.text(
            context,
            widget.session.isPic
                ? '标题 / 作者 / 标签 / Pic ID'
                : '标题 / 作者 / 标签 / JM号',
          ),
          leading: IconButton(
            tooltip: AppTranslations.text(context, '搜索'),
            onPressed: _submit,
            icon: const Icon(Icons.search),
          ),
        ),
      ),
      if (_query.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppText(
            '当前结果：$_query${_text.text.trim() != _query ? ' · 输入已修改，点击搜索应用' : ''}',
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ActionChip(
              avatar: const Icon(Icons.tune, size: 18),
              label: const AppText('筛选和排序'),
              onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            ),
            if (_applied.sort != 'mr')
              InputChip(
                label: AppText(
                  (widget.session.isPic ? picSorts : sorts)[_applied.sort] ??
                      _applied.sort,
                ),
                onDeleted: () => _apply(
                  SearchOptions(type: _type, year: _year, month: _month),
                ),
              ),
            if (_applied.type != 'site')
              InputChip(
                label: AppText(searchTypes[_applied.type] ?? _type),
                onDeleted: () => _apply(
                  SearchOptions(sort: _sort, year: _year, month: _month),
                ),
              ),
            if (_year.isNotEmpty)
              InputChip(
                label: AppText('年份：$_year'),
                onDeleted: () => _apply(
                  SearchOptions(sort: _sort, type: _type, month: _month),
                ),
              ),
            if (_month.isNotEmpty)
              InputChip(
                label: AppText('月份：$_month'),
                onDeleted: () => _apply(
                  SearchOptions(sort: _sort, type: _type, year: _year),
                ),
              ),
            TextButton(
              onPressed: () => _apply(
                SearchOptions(sort: widget.session.isPic ? 'dd' : 'mr'),
              ),
              child: const AppText('重置筛选'),
            ),
          ],
        ),
      ),
      AppReveal(
        visible: _filtersOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SearchFilterEditor(
            key: ValueKey('search-filters:$_filtersOpen'),
            initial: _applied,
            source: widget.session.source,
            onApply: _apply,
            onCancel: () => setState(() => _filtersOpen = false),
          ),
        ),
      ),
      if (_query.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: AppText('搜索历史 / 输入提示')),
                  TextButton(
                    onPressed: () async {
                      await widget.session.store.clearSearchHistory();
                      if (mounted) setState(() {});
                    },
                    child: const AppText('清空'),
                  ),
                ],
              ),
              Wrap(
                runSpacing: 8,
                spacing: 8,
                children: widget.session.store.searchHistory
                    .where(
                      (e) => e.toLowerCase().contains(_text.text.toLowerCase()),
                    )
                    .map(
                      (word) => ActionChip(
                        label: Text(word),
                        onPressed: () {
                          _text.text = word;
                          _submit();
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('搜索')),
    body: _query.isEmpty
        ? CustomScrollView(slivers: [SliverToBoxAdapter(child: _header())])
        : PagedComics(
            key: ValueKey(_revision),
            session: widget.session,
            header: _header(),
            load: (page) =>
                widget.session.api.search(_query, page, options: _applied),
          ),
  );
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.session,
    this.initialSort = 'mr',
  });
  final AppSession session;
  final String initialSort;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<CategoryCatalog> _catalog;
  late String _sort;
  String _category = '0', _sub = '';
  bool _filtersOpen = false;
  String _draftCategory = '0', _draftSub = '', _draftSort = 'mr';
  void _filters() => setState(() {
    if (!_filtersOpen) {
      _draftCategory = _category;
      _draftSub = _sub;
      _draftSort = _sort;
    }
    _filtersOpen = !_filtersOpen;
  });
  Widget _filterPanel(CategoryCatalog catalog) {
    final children =
        catalog.categories
            .where((c) => c.slug == _draftCategory)
            .firstOrNull
            ?.children ??
        [];
    return AppReveal(
      visible: _filtersOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OptionGrid(
                children: [
                  if (!widget.session.isPic || !_draftSort.startsWith('mv'))
                    selectOption(
                      '分类',
                      _draftCategory,
                      {
                        '0': '全部',
                        for (final c in catalog.categories) c.slug: c.name,
                      },
                      (v) => setState(() {
                        _draftCategory = v;
                        _draftSub = '';
                      }),
                    ),
                  if (children.isNotEmpty)
                    selectOption('子分类', _draftSub, {
                      '': '全部',
                      for (final c in children) c.slug: c.name,
                    }, (v) => setState(() => _draftSub = v)),
                  selectOption(
                    '排序',
                    _draftSort,
                    widget.session.isPic ? picCatalogSorts : sorts,
                    (v) => setState(() => _draftSort = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => setState(() {
                      _category = _draftCategory;
                      _sub = _draftSub;
                      _sort = _draftSort;
                      if (widget.session.isPic && _sort.startsWith('mv')) {
                        _category = '0';
                        _sub = '';
                      }
                      _filtersOpen = false;
                    }),
                    child: const AppText('应用筛选'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _draftCategory = '0';
                      _draftSub = '';
                      _draftSort = 'mr';
                    }),
                    child: const AppText('重置筛选'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _filtersOpen = false),
                    child: const AppText('取消'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _catalog = widget.session.api.categories();
    _sort = widget.session.isPic && widget.initialSort == 'mv'
        ? 'mv_m'
        : widget.initialSort;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _catalog,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () =>
                setState(() => _catalog = widget.session.api.categories()),
            child: AppText('加载分类失败，点击重试\n${snapshot.error}'),
          ),
        );
      }
      final catalog = snapshot.data;
      if (catalog == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final choices = {
        '0': '全部',
        for (final c in catalog.categories) c.slug: c.name,
      };
      final children =
          catalog.categories
              .where((c) => c.slug == _category)
              .firstOrNull
              ?.children ??
          [];
      final slug = _sub.isEmpty ? _category : '${_category}_$_sub';
      return PagedComics(
        key: ValueKey('$slug:$_sort'),
        session: widget.session,
        load: (page) => widget.session.api.category(slug, page, sort: _sort),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.tune, size: 18),
                    label: const AppText('筛选和排序'),
                    onPressed: _filters,
                  ),
                  if (_category != '0')
                    InputChip(
                      label: AppText(choices[_category] ?? _category),
                      onDeleted: () => setState(() {
                        _category = '0';
                        _sub = '';
                      }),
                    ),
                  if (_sub.isNotEmpty)
                    InputChip(
                      label: AppText(
                        children
                                .where((c) => c.slug == _sub)
                                .firstOrNull
                                ?.name ??
                            _sub,
                      ),
                      onDeleted: () => setState(() => _sub = ''),
                    ),
                  InputChip(
                    label: AppText(
                      (widget.session.isPic ? picCatalogSorts : sorts)[_sort] ??
                          _sort,
                    ),
                    onDeleted: _sort == 'mr'
                        ? null
                        : () => setState(() => _sort = 'mr'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _category = '0';
                      _sub = '';
                      _sort = 'mr';
                    }),
                    child: const AppText('重置筛选'),
                  ),
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      sheetAnimationStyle: AppMotion.sheet(context),
                      isScrollControlled: true,
                      builder: (context) => SafeArea(
                        child: FractionallySizedBox(
                          heightFactor: .8,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              for (final e in catalog.keywords.entries) ...[
                                AppText(
                                  e.key,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Wrap(
                                  runSpacing: 8,
                                  spacing: 8,
                                  children: e.value
                                      .map(
                                        (word) => ActionChip(
                                          label: Text(word),
                                          onPressed: () {
                                            Navigator.pop(context);
                                            openSearch(
                                              this.context,
                                              widget.session,
                                              word,
                                            );
                                          },
                                        ),
                                      )
                                      .toList(),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: const AppText('分类关键词'),
                  ),
                ],
              ),
            ),
            _filterPanel(catalog),
          ],
        ),
      );
    },
  );
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.session, this.weekly = false});
  final AppSession session;
  final bool weekly;
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late Future<List<Json>> _issues;
  String _issue = '', _type = 'all';
  int _day = DateTime.now().weekday;
  @override
  void initState() {
    super.initState();
    _issues = widget.weekly
        ? widget.session.api.weekIssues()
        : Future.value([]);
    if (widget.weekly) _type = 'manga';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _issues,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () =>
                setState(() => _issues = widget.session.api.weekIssues()),
            child: AppText('加载失败，点击重试\n${snapshot.error}'),
          ),
        );
      }
      final issues = snapshot.data;
      if (issues == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (widget.weekly && issues.isEmpty) {
        return const Center(child: AppText('暂无周刊档期'));
      }
      final issue = _issue.isEmpty && issues.isNotEmpty
          ? '${issues.first['id']}'
          : _issue;
      return PagedComics(
        key: ValueKey('$issue:$_day:$_type'),
        session: widget.session,
        load: (page) => widget.weekly
            ? widget.session.api.week(issue, _type, page)
            : widget.session.api.serialization(_day, _type, page),
        header: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: widget.weekly
                    ? selectOption('档期', issue, {
                        for (final e in issues)
                          '${e['id']}': '${e['time'] ?? e['id']}',
                      }, (v) => setState(() => _issue = v))
                    : selectOption('星期', '$_day', const {
                        '1': '一',
                        '2': '二',
                        '3': '三',
                        '4': '四',
                        '5': '五',
                        '6': '六',
                        '7': '日',
                        '0': '全部',
                      }, (v) => setState(() => _day = int.parse(v))),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: selectOption('类型', _type, {
                  if (!widget.weekly) 'all': '全部',
                  'manga': '漫画',
                  'hanman': '韩漫',
                  if (widget.weekly) 'another': '其他',
                }, (v) => setState(() => _type = v)),
              ),
            ],
          ),
        ),
      );
    },
  );
}

SliverGridDelegateWithFixedCrossAxisCount comicGridDelegate(
  AppSession session,
  double available, {
  TextScaler? scaler,
}) {
  final layout = ComicCardLayout.fromPreferences(
    session.appearance,
    effectiveTextScale: scaler == null
        ? null
        : [
            scaler.scale(12) / 12,
            scaler.scale(14) / 14,
          ].reduce((a, b) => a > b ? a : b),
  );
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: layout.columns(available),
    crossAxisSpacing: layout.spacing,
    mainAxisSpacing: layout.spacing,
    mainAxisExtent: layout.extent(available),
  );
}
