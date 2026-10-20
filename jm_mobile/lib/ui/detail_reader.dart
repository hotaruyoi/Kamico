import 'motion.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../domain/models.dart';
import 'app.dart';
import 'account.dart' show notice;
import 'chapter_download_sheet.dart';
import 'comments_body.dart';
import 'detail_artwork.dart';
import 'cover_image_provider.dart';
import 'design_system.dart';
import 'dialogs.dart';
import 'discovery.dart';
import 'failure.dart';
import 'reading_navigation.dart';
import 'settings.dart' show LoginScreen;
import 'translations.dart';
export 'reader.dart';

final _chapterNumber = RegExp(
  r'第\s*([0-9一二三四五六七八九十百千零〇两兩]+(?:\.[0-9]+)?)\s*[话話章集]',
);

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.session,
    required this.comic,
    this.embedded = false,
  });
  final AppSession session;
  final Comic comic;
  final bool embedded;
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with SingleTickerProviderStateMixin {
  late Future<ComicDetail> _detail;
  late Comic _artworkComic = widget.comic;
  final _artwork = DetailArtwork();
  late final TabController _tabs;
  final _visited = <int>{0}, _downloaded = <String>{};
  bool _favoriteBusy = false, _downloadBusy = false, _reversed = false;
  String _chapterQuery = '';
  bool _chapterSearchOpen = false;
  final _chapterSearch = TextEditingController();
  @override
  void initState() {
    super.initState();
    _artwork.addListener(_artworkChanged);
    _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged);
    _detail = _loadDetail();
    widget.session.downloads
        .list()
        .then((entries) {
          if (mounted) {
            setState(
              () => _downloaded.addAll(
                entries
                    .where((e) => e.comic.key == widget.comic.key)
                    .map((e) => e.chapter.id),
              ),
            );
          }
        })
        .catchError((Object _) {});
  }

  void _tabChanged() {
    if (!_visited.contains(_tabs.index)) {
      setState(() => _visited.add(_tabs.index));
    }
  }

  void _artworkChanged() {
    if (mounted) setState(() {});
  }

  Future<ComicDetail> _loadDetail({bool refresh = false}) async {
    final detail = await widget.session.api.detail(
      widget.comic.id,
      refresh: refresh,
    );
    if (mounted && detail.comic.cover != _artworkComic.cover) {
      _artworkComic = detail.comic;
      _resolveArtwork();
    }
    return detail;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveArtwork();
  }

  void _resolveArtwork() {
    if (widget.session.isPic && _artworkComic.cover.isEmpty) return;
    final width = math.min(960.0, MediaQuery.sizeOf(context).width) - 32;
    final pixels =
        math.min(240.0, width * .43) * MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = ((pixels / 64).ceil() * 64).clamp(64, 400);
    _artwork.resolve(
      CoverImageProvider(
        _artworkComic.coverUrl(widget.session.api.config.imageHost),
        decodeWidth,
      ),
      createLocalImageConfiguration(context),
    );
  }

  @override
  void dispose() {
    _artwork.removeListener(_artworkChanged);
    _artwork.dispose();
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    _chapterSearch.dispose();
    super.dispose();
  }

  void _reload() {
    _detail = _loadDetail(refresh: true);
  }

  ReadingProgress? _recent(ComicDetail detail) =>
      widget.session.store.recentProgress(detail.comic.key);

  Future<void> _download(ComicDetail detail) async {
    if (_downloadBusy) return;
    if (detail.price > 0 && !detail.purchased) {
      notice(context, '请先购买后下载');
      return;
    }
    setState(() => _downloadBusy = true);
    try {
      final chapters = await showModalBottomSheet<List<Chapter>>(
        context: context,
        sheetAnimationStyle: AppMotion.sheet(context),
        isScrollControlled: true,
        builder: (_) =>
            ChapterDownloadSheet(session: widget.session, detail: detail),
      );
      if (!mounted || chapters == null || chapters.isEmpty) return;
      final result = await widget.session.queue.enqueue(detail.comic, chapters);
      if (mounted) {
        notice(
          context,
          '${result.message}${result.added + result.resumed > 0 ? '\n下载期间请保持应用在前台，系统可能中断后台任务' : ''}',
        );
      }
    } catch (error) {
      if (mounted) notice(context, error);
    } finally {
      if (mounted) setState(() => _downloadBusy = false);
    }
  }

  Future<void> _read(
    ComicDetail detail,
    Chapter chapter, {
    bool fromStart = false,
  }) async {
    await openChapter(
      context,
      widget.session,
      detail.comic,
      chapter,
      chapters: detail.chapters,
      fromStart: fromStart,
      locked: detail.price > 0 && !detail.purchased,
    );
    if (mounted) setState(() {});
  }

  Future<void> _purchase(ComicDetail detail) async {
    if (!await confirm(
      context,
      '购买《${detail.comic.title}》需要 ${detail.price} 金币，确认购买？',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _favoriteBusy = true);
    try {
      final current = await widget.session.api.detail(
        detail.comic.id,
        refresh: true,
      );
      if (current.purchased) {
        if (mounted) setState(_reload);
        return;
      }
      if (current.price != detail.price) {
        throw const FormatException('价格已改变，请刷新后确认');
      }
      final message = await widget.session.api.purchase(detail.comic.id);
      await widget.session.markProfilePending();
      if (mounted) {
        notice(context, message);
        setState(_reload);
      }
    } catch (error) {
      if (mounted) notice(context, error);
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _favorite(ComicDetail detail, {bool cloud = false}) async {
    if (_favoriteBusy) return;
    setState(() => _favoriteBusy = true);
    try {
      if (cloud) {
        await widget.session.api.toggleFavorite(detail.comic.id);
        if (mounted) setState(_reload);
      } else if (widget.session.store.localFavorites.containsKey(
        detail.comic.key,
      )) {
        await widget.session.store.removeLocal([detail.comic.key]);
      } else {
        await widget.session.store.addLocal(detail.comic);
      }
    } catch (error) {
      if (mounted) notice(context, error);
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _favoriteMenu(ComicDetail detail) async {
    var cloud = widget.session.loggedIn;
    var busy = false;
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.sheet(context),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          final saved = cloud
              ? detail.favorite
              : widget.session.store.localFavorites.containsKey(
                  detail.comic.key,
                );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('收藏'),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.bookmark_outline),
                        label: AppText('本地收藏'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.cloud_outlined),
                        label: AppText('云端收藏'),
                      ),
                    ],
                    selected: {cloud},
                    onSelectionChanged: busy
                        ? null
                        : (values) => update(() => cloud = values.single),
                  ),
                  const SizedBox(height: 16),
                  AppText(cloud ? '收藏同步到当前账号' : '收藏保存在这台设备'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (cloud && !widget.session.loggedIn) {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      LoginScreen(session: widget.session),
                                ),
                              );
                              if (context.mounted) update(() {});
                              return;
                            }
                            update(() => busy = true);
                            await _favorite(detail, cloud: cloud);
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                    child: AppText(
                      cloud && !widget.session.loggedIn
                          ? '登录后收藏'
                          : saved
                          ? '取消收藏'
                          : '加入收藏',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summary(ComicDetail detail) {
    final saved = _recent(detail);
    final continuing = detail.chapters
        .where((c) => c.id == saved?.chapterId)
        .firstOrNull;
    final resumeNumber = continuing == null
        ? null
        : _chapterNumber.firstMatch(continuing.title)?.group(1) ??
              '${detail.chapters.indexOf(continuing) + 1}';
    final locked = detail.price > 0 && !detail.purchased;
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            key: const ValueKey('detail-artwork-background'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .45, 1],
                colors: [
                  colors.surface.withValues(alpha: 0),
                  colors.surface.withValues(alpha: .15),
                  colors.surface,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                detail.comic.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, box) {
                  final coverWidth = math.min(240.0, box.maxWidth * .43);
                  return Row(
                    key: const ValueKey('detail-cover-metadata'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: coverWidth,
                          height: coverWidth * 4 / 3,
                          child: _DetailCover(artwork: _artwork),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 24,
                          children: [
                            if (detail.comic.authors.isNotEmpty)
                              Text(
                                detail.comic.authors.join(' / '),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            if (detail.comic.source == ContentSource.jm)
                              Text(
                                '${detail.comic.source.label} ${detail.comic.id}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            Semantics(
                              label: AppTranslations.text(
                                context,
                                detail.likes == null
                                    ? '点赞数暂无数据'
                                    : '点赞 ${detail.likes}',
                              ),
                              excludeSemantics: true,
                              child: Row(
                                key: const ValueKey('detail-likes'),
                                children: [
                                  Icon(
                                    Icons.thumb_up_outlined,
                                    size: 18,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: AppText(
                                      detail.likes ?? '—',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, box) {
                  final iconWidth = math.max(48.0, box.maxWidth * .15);
                  final readWidth = math.min(
                    box.maxWidth * .5,
                    box.maxWidth - iconWidth * 2 - 16,
                  );
                  return Row(
                    key: const ValueKey('detail-primary-actions'),
                    children: [
                      SizedBox(
                        width: readWidth,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 52),
                          ),
                          onPressed: detail.chapters.isEmpty
                              ? null
                              : () => _read(
                                  detail,
                                  continuing ?? detail.chapters.first,
                                ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AppText(
                              resumeNumber == null
                                  ? '开始阅读'
                                  : '继续 第$resumeNumber话',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: iconWidth,
                        height: 52,
                        child: IconButton.filledTonal(
                          key: const ValueKey('detail-download'),
                          tooltip: AppTranslations.text(context, '下载'),
                          onPressed: _downloadBusy
                              ? null
                              : () => _download(detail),
                          icon: const Icon(Icons.download_outlined),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: iconWidth,
                        height: 52,
                        child: IconButton.filledTonal(
                          key: const ValueKey('detail-favorite'),
                          tooltip: AppTranslations.text(context, '收藏'),
                          onPressed: _favoriteBusy
                              ? null
                              : () => _favoriteMenu(detail),
                          icon: Icon(
                            detail.favorite ||
                                    widget.session.store.localFavorites
                                        .containsKey(detail.comic.key)
                                ? Icons.bookmark
                                : Icons.bookmark_outline,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (locked) const AppText('需购买 · 已下载可离线阅读'),
              if (detail.price > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.paid_outlined),
                    label: AppText(
                      detail.purchased ? '已购买' : '购买 · ${detail.price} 金币',
                    ),
                    onPressed:
                        detail.purchased ||
                            _favoriteBusy ||
                            !widget.session.loggedIn
                        ? null
                        : () => _purchase(detail),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _descriptionExpanded = false,
      _tagsExpanded = false,
      _chaptersExpanded = false;
  bool get _compact =>
      widget.session.store.preferences.getString('chapter_layout') == 'compact';

  Future<void> _chapterLayout() async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.sheet(context),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionTitle('目录样式'),
            for (final compact in [false, true])
              ListTile(
                selected: _compact == compact,
                leading: Icon(
                  compact
                      ? Icons.grid_view_outlined
                      : Icons.view_agenda_outlined,
                ),
                title: AppText(compact ? '紧凑短框' : '详细列表'),
                subtitle: AppText(
                  compact ? '更多章节同时展示，列数随屏幕调整' : '显示章节名称、阅读和下载状态',
                ),
                trailing: _compact == compact ? const Icon(Icons.check) : null,
                onTap: () async {
                  await widget.session.store.preferences.setString(
                    'chapter_layout',
                    compact ? 'compact' : 'list',
                  );
                  if (mounted) setState(() {});
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Object? _descriptionMeasureKey;
  bool _descriptionIsLong = false;
  Widget _description(ComicDetail detail) => LayoutBuilder(
    builder: (context, box) {
      final value = detail.description.isEmpty
          ? AppTranslations.text(context, '暂无简介')
          : detail.description;
      final style = Theme.of(context).textTheme.bodyMedium!;
      final measureKey = (
        value,
        style,
        box.maxWidth,
        Directionality.of(context),
        MediaQuery.textScalerOf(context),
      );
      if (_descriptionMeasureKey != measureKey) {
        final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          maxLines: 4,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        _descriptionIsLong = painter.didExceedMaxLines;
        painter.dispose();
        _descriptionMeasureKey = measureKey;
      }
      final long = _descriptionIsLong;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('简介'),
          if (_descriptionExpanded)
            SelectableText(value, style: style)
          else
            Text(
              value,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          if (long)
            TextButton.icon(
              onPressed: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
              icon: Icon(
                _descriptionExpanded ? Icons.expand_less : Icons.expand_more,
              ),
              label: AppText(_descriptionExpanded ? '收起简介' : '展开简介'),
            ),
        ],
      );
    },
  );

  List<Widget> _contentSlivers(ComicDetail detail) {
    var chapters = detail.chapters
        .where(
          (c) => c.title.toLowerCase().contains(_chapterQuery.toLowerCase()),
        )
        .toList();
    if (_reversed) chapters = chapters.reversed.toList();
    final visible = _chaptersExpanded
        ? chapters.length
        : chapters.length.clamp(0, _compact ? 12 : 6);
    final metadata = <({String label, String query, String type})>[
      for (final author in detail.comic.authors)
        (label: author, query: author, type: 'author'),
      for (final tag in detail.tags) (label: tag, query: tag, type: 'tag'),
      for (final work in detail.works)
        (
          label: AppTranslations.text(context, '作品：$work'),
          query: work,
          type: 'work',
        ),
      for (final actor in detail.actors)
        (
          label: AppTranslations.text(context, '角色：$actor'),
          query: actor,
          type: 'character',
        ),
    ];
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _description(detail),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final item
                        in (_tagsExpanded ? metadata : metadata.take(6)))
                      ActionChip(
                        label: Text(item.label),
                        onPressed: () => openSearch(
                          context,
                          widget.session,
                          item.query,
                          type: item.type,
                        ),
                      ),
                    if (metadata.length > 6)
                      TextButton(
                        onPressed: () =>
                            setState(() => _tagsExpanded = !_tagsExpanded),
                        child: AppText(_tagsExpanded ? '收起标签' : '展开标签'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppText(
                          '章节 · ${detail.chapters.length}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        IconButton(
                          tooltip: AppTranslations.text(
                            context,
                            _chapterSearchOpen ? '收起章节搜索' : '搜索章节',
                          ),
                          onPressed: () {
                            if (_chapterSearchOpen) {
                              FocusScope.of(context).unfocus();
                              _chapterSearch.clear();
                            }
                            setState(() {
                              _chapterSearchOpen = !_chapterSearchOpen;
                              if (!_chapterSearchOpen) {
                                _chapterQuery = '';
                                _chaptersExpanded = false;
                              }
                            });
                          },
                          icon: Icon(
                            _chapterSearchOpen
                                ? Icons.search_off
                                : Icons.search,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _reversed = !_reversed),
                          icon: const Icon(Icons.swap_vert, size: 18),
                          label: AppText(_reversed ? '倒序' : '正序'),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: AppTranslations.text(context, '目录样式'),
                    onPressed: _chapterLayout,
                    icon: Icon(
                      _compact
                          ? Icons.grid_view_outlined
                          : Icons.view_agenda_outlined,
                    ),
                  ),
                ],
              ),
              if (_recent(detail) != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _chapterQuery =
                          detail.chapters
                              .where((c) => c.id == _recent(detail)?.chapterId)
                              .firstOrNull
                              ?.title ??
                          '';
                      _chapterSearch.text = _chapterQuery;
                      _chapterSearchOpen = true;
                      _chaptersExpanded = false;
                    }),
                    child: const AppText('定位最近章节'),
                  ),
                ),
              AnimatedSize(
                duration: AppMotion.duration(context, AppMotion.panel),
                curve: AppMotion.curve,
                alignment: Alignment.topCenter,
                child: _chapterSearchOpen
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SearchBar(
                          controller: _chapterSearch,
                          hintText: AppTranslations.text(context, '搜索章节'),
                          leading: const Icon(Icons.search),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          trailing: [
                            if (_chapterQuery.isNotEmpty)
                              IconButton(
                                tooltip: AppTranslations.text(
                                  context,
                                  '清空章节筛选',
                                ),
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() {
                                  _chapterQuery = '';
                                  _chapterSearch.clear();
                                  _chaptersExpanded = false;
                                }),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _chapterQuery = v;
                            _chaptersExpanded = false;
                          }),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
      if (chapters.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: AppText('没有匹配章节')),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: _compact
              ? SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final columns =
                        (constraints.crossAxisExtent / (104 * scale))
                            .floor()
                            .clamp(1, 8);
                    return SliverGrid.builder(
                      itemCount: visible,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        mainAxisExtent: 52 * scale,
                      ),
                      itemBuilder: (_, i) =>
                          _chapterTile(detail, chapters[i], compact: true),
                    );
                  },
                )
              : SliverList.builder(
                  itemCount: visible,
                  itemBuilder: (_, i) => _chapterTile(detail, chapters[i]),
                ),
        ),
      if (chapters.length > (_compact ? 12 : 6))
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _chaptersExpanded = !_chaptersExpanded),
                icon: Icon(
                  _chaptersExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                label: AppText(
                  _chaptersExpanded ? '收起目录' : '展开全部章节 (${chapters.length})',
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _chapterTile(
    ComicDetail detail,
    Chapter chapter, {
    bool compact = false,
  }) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final state =
          widget.session.queue.jobs['${detail.comic.key}:${chapter.id}']?.state;
      final saved = widget.session.store.chapterProgress(
        detail.comic.key,
        chapter.id,
      );
      final downloaded = _downloaded.contains(chapter.id) || state == 'done';
      final status = downloaded
          ? ''
          : switch (state) {
              'queued' => '排队中',
              'running' => '下载中',
              'paused' => '已暂停',
              'failed' => '下载失败',
              _ => '',
            };
      final title = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              chapter.title,
              textAlign: compact ? TextAlign.center : null,
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
            ),
          ),
          if (downloaded) ...[
            const SizedBox(width: 6),
            Semantics(
              label: AppTranslations.text(context, '已下载'),
              child: Container(
                key: ValueKey('downloaded-chapter:${chapter.id}'),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  size: 14,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      );
      final subtitle = [
        if (status.isNotEmpty) status,
        if (saved != null) '${saved.page + 1} 页',
      ].join(' · ');
      if (compact) {
        return FilledButton.tonal(
          key: ValueKey('compact-chapter:${chapter.id}'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: saved == null
                ? null
                : Theme.of(context).colorScheme.secondaryContainer,
          ),
          onPressed: () => _read(detail, chapter),
          child: Tooltip(message: chapter.title, child: title),
        );
      }
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: const Icon(Icons.menu_book_outlined),
        title: title,
        subtitle: subtitle.isEmpty ? null : AppText(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _read(detail, chapter),
      );
    },
  );

  Widget _scrollTab(List<Widget> slivers) => Builder(
    builder: (context) => CustomScrollView(
      key: PageStorageKey('contents:${widget.comic.key}'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        ...slivers,
        const SliverToBoxAdapter(
          child: SafeArea(top: false, child: SizedBox(height: 24)),
        ),
      ],
    ),
  );
  Widget _detailBody(AsyncSnapshot<ComicDetail> snapshot) {
    final detail =
        snapshot.data ??
        widget.session.api.cachedDetail(widget.comic.id, allowStale: true);
    if (snapshot.hasError && detail == null) {
      return AppFailure(
        error: snapshot.error!,
        retry: () => setState(_reload),
        session: widget.session,
      );
    }
    if (detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return NestedScrollView(
      headerSliverBuilder: (context, innerScrolled) => [
        SliverToBoxAdapter(child: _summary(detail)),
        if (snapshot.hasError)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(child: AppText('详情更新失败，显示上次内容')),
                  TextButton(
                    onPressed: () => setState(() {
                      _detail = widget.session.api.detail(widget.comic.id);
                    }),
                    child: const AppText('重试'),
                  ),
                ],
              ),
            ),
          ),
        SliverOverlapAbsorber(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          sliver: SliverPersistentHeader(
            pinned: true,
            delegate: _DetailTabs(
              TabBar(
                key: const ValueKey('detail-tabs'),
                controller: _tabs,
                tabs: const [
                  Tab(child: AppText('详情')),
                  Tab(child: AppText('评论')),
                ],
              ),
            ),
          ),
        ),
      ],
      body: Material(
        color: Theme.of(context).colorScheme.surface,
        child: TabBarView(
          controller: _tabs,
          children: [
            _scrollTab(_contentSlivers(detail)),
            _visited.contains(1)
                ? CommentsBody(
                    session: widget.session,
                    id: detail.comic.id,
                    nested: true,
                  )
                : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ComicDetail>(
    future: _detail,
    initialData: widget.session.api.cachedDetail(
      widget.comic.id,
      allowStale: true,
    ),
    builder: (context, snapshot) => Stack(
      children: [
        Positioned.fill(
          child: _DetailBackdrop(
            key: const ValueKey('detail-shared-backdrop'),
            frame:
                snapshot.hasData ||
                    widget.session.api.cachedDetail(
                          widget.comic.id,
                          allowStale: true,
                        ) !=
                        null
                ? _artwork.frame
                : null,
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: widget.embedded
              ? null
              : AppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                ),
          body: AppPageBody(maxWidth: 960, child: _detailBody(snapshot)),
        ),
      ],
    ),
  );
}

class _DetailCover extends StatelessWidget {
  const _DetailCover({required this.artwork});
  final DetailArtwork artwork;
  @override
  Widget build(BuildContext context) {
    final frame = artwork.frame;
    if (frame != null) {
      return Semantics(
        label: '作品封面',
        image: true,
        child: RawImage(
          image: frame.image,
          scale: frame.scale,
          fit: BoxFit.cover,
        ),
      );
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: artwork.error == null
            ? const Icon(Icons.image_outlined)
            : IconButton(
                tooltip: '封面加载失败，点击重试',
                onPressed: artwork.retry,
                icon: const Icon(Icons.refresh),
              ),
      ),
    );
  }
}

class _DetailBackdrop extends StatelessWidget {
  const _DetailBackdrop({super.key, required this.frame});
  final ImageInfo? frame;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: colors.surface),
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 18,
                    sigmaY: 18,
                    tileMode: ui.TileMode.clamp,
                  ),
                  child: RawImage(
                    image: frame?.image,
                    scale: frame?.scale ?? 1,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .5, 1],
                      colors: [
                        colors.surface.withValues(alpha: .5),
                        colors.surface.withValues(alpha: .65),
                        colors.surface,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTabs extends SliverPersistentHeaderDelegate {
  _DetailTabs(this.tabs);
  final TabBar tabs;
  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(
    child: Material(color: Theme.of(context).colorScheme.surface, child: tabs),
  );
  @override
  bool shouldRebuild(covariant _DetailTabs oldDelegate) => true;
}
