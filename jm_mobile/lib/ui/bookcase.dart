import 'motion.dart';
import 'design_system.dart';
import 'translations.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'app.dart';
import 'dialogs.dart';
import 'discovery.dart';
import 'settings.dart';
import 'downloads.dart';
import 'dart:convert';
import 'failure.dart';
import 'library_layout.dart';

class BookcaseScreen extends StatefulWidget {
  const BookcaseScreen({super.key, required this.session, this.active = true});
  final AppSession session;
  final bool active;
  @override
  State<BookcaseScreen> createState() => _BookcaseScreenState();
}

class _BookcaseScreenState extends State<BookcaseScreen> {
  bool _local = false, _busy = false;
  bool _selecting = false;
  String _folder = '0', _sort = 'mr', _query = '';
  int _page = 1, _total = 0, _size = 1, _generation = 0;
  Map<String, String> _folders = {'0': '默认收藏夹'};
  List<Comic> _items = [];
  final _selected = <String>{};
  Object? _error;
  @override
  void initState() {
    super.initState();
    _local =
        widget.session.store.preferences.getBool(
          widget.session.prefKey('bookcase_local'),
        ) ??
        (!widget.session.loggedIn ||
            widget.session.store.localFavorites.isNotEmpty);
    _reload();
  }

  @override
  void didUpdateWidget(covariant BookcaseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _reload(page: _page);
  }

  Future<void> _reload({int page = 1}) async {
    await widget.session.store.preferences.setBool(
      widget.session.prefKey('bookcase_local'),
      _local,
    );
    if (!mounted) return;
    final generation = ++_generation;
    _selected.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_local) {
        _folders = widget.session.store.localFolders;
        _items = widget.session.store.localFavorites.values
            .where((e) => e['folder'] == _folder)
            .map((e) => Comic.fromJson(e['comic'] as Json))
            .toList();
        _total = _items.length;
      } else if (widget.session.loggedIn) {
        final raw = await widget.session.api.favoriteFolder(
          _folder,
          page,
          _sort,
        );
        if (!mounted || generation != _generation) return;
        final result = ComicPage.fromJson(raw, key: 'list');
        _items = result.items;
        _total = result.total;
        if (page == 1) _size = result.items.isEmpty ? 1 : result.items.length;
        _folders = {
          '0': '默认收藏夹',
          for (final f in raw['folder_list'] as List? ?? [])
            '${f['FID']}': '${f['name']}',
        };
      } else {
        _items = [];
        _total = 0;
      }
      if (mounted && generation == _generation) setState(() => _page = page);
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _action(Future<void> Function() run) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await run();
      if (mounted) await _reload();
    } catch (e) {
      if (mounted) {
        await _reload();
        if (mounted) setState(() => _error = e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  final _scroll = ScrollController();
  final _search = TextEditingController();
  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });
  Future<void> _newFolder() async {
    final name = await prompt(context, '新建收藏夹');
    if (!mounted || name == null) return;
    await _action(
      () => _local
          ? widget.session.store.createLocalFolder(name)
          : widget.session.api.editFavoriteFolder('add', name: name),
    );
  }

  Future<void> _folderSheet() async {
    final target = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: AppMotion.sheet(context),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: AppText('收藏夹')),
              for (final entry in _folders.entries)
                ListTile(
                  title: Text(entry.value),
                  selected: entry.key == _folder,
                  leading: Icon(
                    entry.key == _folder ? Icons.folder : Icons.folder_outlined,
                  ),
                  onTap: () => Navigator.pop(context, entry.key),
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const AppText('新建收藏夹'),
                onTap: () => Navigator.pop(context, '__new'),
              ),
              if (_folder != '0')
                ListTile(
                  leading: const Icon(Icons.folder_delete_outlined),
                  title: const AppText('删除收藏夹'),
                  onTap: () => Navigator.pop(context, '__delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || target == null) return;
    if (target == '__new') {
      await _newFolder();
      return;
    }
    if (target == '__delete') {
      if (!await confirm(
        context,
        _local ? '删除分组，收藏移回默认收藏夹？' : '删除云端收藏夹？操作结果以上游规则为准。',
        title: '删除收藏夹',
        action: '删除',
      )) {
        return;
      }
      final folder = _folder;
      _folder = '0';
      await _action(
        () => _local
            ? widget.session.store.deleteLocalFolder(folder)
            : widget.session.api.editFavoriteFolder('del', id: folder),
      );
      return;
    }
    _folder = target;
    await _reload();
  }

  Future<void> _moveSelected() async {
    final target = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: AppMotion.sheet(context),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: AppText('移动到收藏夹')),
            for (final entry in _folders.entries)
              ListTile(
                title: Text(entry.value),
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted || target == null) return;
    final ids = List<String>.of(_selected);
    await _action(() async {
      if (_local) {
        await widget.session.store.moveLocal(ids, target);
      } else {
        for (final id in ids) {
          await widget.session.api.editFavoriteFolder(
            'move',
            id: target,
            comicId: widget.session.source.remoteId(id),
          );
        }
      }
    });
  }

  Future<void> _removeSelected() async {
    final ids = List<String>.of(_selected);
    if (!await confirm(
      context,
      '移除当前列表选中的 ${ids.length} 本${_local ? '设备内' : '云端'}收藏？不会删除图片。',
      title: '移除收藏',
      action: '移除',
    )) {
      return;
    }
    if (!mounted) return;
    final local = _local;
    final backup = {
      for (final id in ids)
        if (widget.session.store.localFavorites[id] != null)
          id: widget.session.store.localFavorites[id],
    };
    await _action(() async {
      if (local) {
        await widget.session.store.removeLocal(ids);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: AppText('已移除 ${ids.length} 本设备内收藏'),
              action: SnackBarAction(
                label: '撤销',
                onPressed: () async {
                  await widget.session.store.writeMap('local_favorites', {
                    ...widget.session.store.localFavorites,
                    ...backup,
                  });
                  if (mounted) _reload(page: _page);
                },
              ),
            ),
          );
        }
      } else {
        for (final id in ids) {
          await widget.session.api.toggleFavorite(
            widget.session.source.remoteId(id),
          );
        }
      }
    });
  }

  void _open(Widget page, String title) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: AppText(title)),
        body: page,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final items = _items
        .where(
          (e) =>
              session.store.visible(e) &&
              e.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final needsLogin = !_local && !session.loggedIn;
    final rows = _local
        ? sourceSections(items, (c) => c.source)
        : [for (final comic in items) (source: comic.source, item: comic)];
    return LibrarySelectionLayout(
      bodyBuilder: (bottomInset) => LibraryScrollView(
        bottomInset: bottomInset,
        storageKey: 'bookcase:${session.source.id}',
        controller: _scroll,
        onRefresh: () => _reload(page: _page),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        _local ? '设备内收藏' : '云端收藏',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      AppText(
                        !_local && session.isPic
                            ? '$_total 本'
                            : '$_total 本 · ${_folders[_folder] ?? '默认收藏夹'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_local || !session.isPic)
                  IconButton(
                    tooltip: AppTranslations.text(context, '新建收藏夹'),
                    onPressed: _busy || needsLogin ? null : _newFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                AppActionMenu(
                  actions: [
                    AppMenuAction(
                      '最近阅读',
                      Icons.history,
                      () => _open(HistoryScreen(session: session), '最近阅读'),
                    ),
                    AppMenuAction(
                      '离线文件',
                      Icons.offline_pin_outlined,
                      () => _open(
                        DownloadScreen(session: session, initialLibrary: true),
                        '离线文件',
                      ),
                    ),
                    AppMenuAction(
                      '收藏说明',
                      Icons.info_outline,
                      () => showDialog<void>(
                        context: context,
                        animationStyle: AppMotion.sheet(context),
                        builder: (context) => AlertDialog(
                          title: const AppText('收藏说明'),
                          content: AppText(
                            _local ? '设备内书签，不包含图片，也不自动同步' : '云端收藏，与设备内书签分别管理',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const AppText('关闭'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            AppSourceSwitch(
              padding: const EdgeInsets.symmetric(vertical: 12),
              cloud: !_local,
              onChanged: _busy
                  ? null
                  : (cloud) {
                      setState(() {
                        _local = !cloud;
                        _folder = '0';
                        _selected.clear();
                        _selecting = false;
                      });
                      _reload();
                    },
            ),
            SearchBar(
              controller: _search,
              hintText: AppTranslations.text(context, '筛选当前列表'),
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    tooltip: AppTranslations.text(context, '清空搜索'),
                    onPressed: () => setState(() {
                      _query = '';
                      _search.clear();
                      _selected.clear();
                    }),
                    icon: const Icon(Icons.clear),
                  ),
              ],
              onChanged: (value) => setState(() {
                _query = value;
                _selected.clear();
              }),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_local || !session.isPic)
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: AppText(_folders[_folder] ?? '默认收藏夹'),
                    onPressed: _busy || needsLogin ? null : _folderSheet,
                  ),
                if (!_local)
                  ActionChip(
                    avatar: const Icon(Icons.sort, size: 18),
                    label: AppText(
                      session.isPic
                          ? (_sort == 'mr' ? '最新收藏' : '最早收藏')
                          : (_sort == 'mr' ? '收藏时间' : '更新时间'),
                    ),
                    onPressed: _busy || needsLogin
                        ? null
                        : () {
                            _sort = _sort == 'mr'
                                ? (session.isPic ? 'da' : 'mp')
                                : 'mr';
                            _reload();
                          },
                  ),
                LibrarySelectionToggle(
                  selected: _selecting,
                  onPressed: needsLogin
                      ? null
                      : () => setState(() {
                          _selecting = !_selecting;
                          _selected.clear();
                        }),
                ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
        slivers: [
          if (needsLogin)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppStatus(
                icon: Icons.cloud_outlined,
                title: '云端收藏',
                message: '登录后同步收藏和观看历史',
                action: FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => LoginScreen(session: session),
                      ),
                    );
                    if (mounted) _reload();
                  },
                  icon: const Icon(Icons.login),
                  label: const AppText('登录后查看收藏'),
                ),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppFailure(
                error: _error!,
                retry: () => _reload(page: _page),
                session: session,
              ),
            )
          else if (items.isEmpty && !_busy)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppStatus(
                icon: Icons.bookmarks_outlined,
                title: _query.isEmpty ? '暂无收藏' : '没有匹配收藏',
                message: _query.isEmpty
                    ? '在作品详情收藏，之后可从这里继续阅读'
                    : '换一个关键词，或清空搜索查看全部',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  if (row.item == null) return SourceSection(row.source);
                  final comic = row.item!;
                  final saved = session.store.recentProgress(comic.key);
                  return LibraryBookTile(
                    comic: comic,
                    imageHost: session.imageHostFor(comic),
                    selected: _selecting ? _selected.contains(comic.key) : null,
                    onSelect: _busy ? null : (_) => _toggle(comic.key),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (comic.authors.isNotEmpty)
                          Text(
                            comic.authors.join(' / '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (saved != null ||
                            session.offlineIds.contains(comic.key))
                          AppText(
                            '${saved == null ? '' : '读到 ${saved.page + 1} 页'}${session.offlineIds.contains(comic.key) ? ' · 离线可读' : ''}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                    onLongPress: () => setState(() {
                      _selecting = true;
                      _selected.add(comic.key);
                    }),
                    onTap: () => _selecting
                        ? _toggle(comic.key)
                        : openComic(context, session, comic, related: items),
                  );
                },
              ),
            ),
          if (!_local && !needsLogin)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '上一页',
                      onPressed: _busy || _page == 1
                          ? null
                          : () {
                              _scroll.jumpTo(0);
                              _reload(page: _page - 1);
                            },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Flexible(child: AppText('第 $_page 页 · 共 $_total 本')),
                    IconButton(
                      tooltip: '下一页',
                      onPressed: _busy || _page * _size >= _total
                          ? null
                          : () {
                              _scroll.jumpTo(0);
                              _reload(page: _page + 1);
                            },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      selectionBar: LibrarySelectionBar(
        visible: _selecting,
        count: _selected.length,
        onDone: () => setState(() {
          _selecting = false;
          _selected.clear();
        }),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () =>
                      setState(() => _selected.addAll(items.map((c) => c.key))),
            child: const AppText('全选'),
          ),
          if (_local || !session.isPic)
            TextButton(
              onPressed: _busy || _selected.isEmpty ? null : _moveSelected,
              child: const AppText('移动'),
            ),
          TextButton(
            onPressed: _busy || _selected.isEmpty ? null : _removeSelected,
            child: const AppText('移除'),
          ),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _cloud = false,
      _selecting = false,
      _removing = false,
      _cloudBusy = false;
  String _query = '';
  int _page = 1,
      _cloudPage = 1,
      _cloudSize = 0,
      _cloudTotal = 0,
      _generation = 0;
  bool _cloudMore = false;
  Object? _cloudScope, _cloudError;
  List<Comic> _cloudItems = [];
  final _selected = <String>{};
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_cloud && _cloudScope != _scope) _loadCloud();
  }

  Object get _scope => (
    widget.session.source,
    widget.session.api.token,
    widget.session.api.config,
  );
  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCloud({int page = 1}) async {
    final scopeChanged = _cloudScope != _scope;
    _cloudScope = _scope;
    final generation = ++_generation;
    if (scopeChanged || page == 1) {
      _cloudItems = [];
      _cloudTotal = 0;
      _cloudPage = 1;
      _cloudMore = false;
    }
    if (widget.session.isPic || !widget.session.loggedIn) {
      setState(() {
        _cloudBusy = false;
        _cloudItems = [];
        _cloudError = null;
      });
      return;
    }
    final api = widget.session.api;
    setState(() {
      _cloudBusy = true;
      _cloudError = null;
    });
    try {
      final result = await api.cloudHistory(page);
      if (!mounted || generation != _generation || _cloudScope != _scope) {
        return;
      }
      setState(() {
        _cloudItems = result.items;
        _cloudPage = page;
        if (page == 1) _cloudSize = result.items.length;
        _cloudTotal = result.total;
        _cloudMore =
            result.more ?? (_cloudSize > 0 && page * _cloudSize < result.total);
      });
    } catch (error) {
      if (mounted && generation == _generation && _cloudScope == _scope) {
        setState(() => _cloudError = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _cloudBusy = false);
      }
    }
  }

  void _switch(bool cloud) {
    if (_cloud == cloud) return;
    setState(() {
      _cloud = cloud;
      _selected.clear();
      _selecting = false;
      _query = '';
      _search.clear();
      ++_generation;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (cloud) _loadCloud();
  }

  Future<void> _refresh() async {
    if (_cloud) {
      await _loadCloud(page: _cloudPage);
    } else {
      await widget.session.savedProgress;
      if (mounted) setState(() {});
    }
  }

  void _toggle(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });
  Future<void> _deleteSelected() async {
    if (_removing || _selected.isEmpty) return;
    if (!await confirm(
      context,
      '删除筛选范围内选中的 ${_selected.length} 本阅读历史？',
      title: '删除历史',
      action: '删除',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _removing = true);
    try {
      await widget.session.savedProgress;
      final store = widget.session.store, ids = Set<String>.of(_selected);
      final backup = store.history
          .where((p) => ids.contains(p.comic.key))
          .toList();
      final chapters = store
          .readMap('chapter_progress')
          .entries
          .where(
            (e) => ids.contains(
              ReadingProgress.fromJson(e.value as Json).comic.key,
            ),
          )
          .toList();
      await store.deleteHistory(ids);
      if (!mounted) return;
      setState(() => _selected.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const AppText('历史已删除'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              final current = store.history;
              final currentIds = current.map((p) => p.comic.key).toSet();
              await store.preferences.setString(
                'history',
                jsonEncode(
                  [
                    ...current,
                    ...backup.where((p) => !currentIds.contains(p.comic.key)),
                  ].map((p) => p.toJson()).toList(),
                ),
              );
              final currentChapters = store.readMap('chapter_progress');
              await store.writeMap('chapter_progress', {
                for (final entry in chapters) entry.key: entry.value,
                ...currentChapters,
              });
              if (mounted) setState(() {});
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: AppText(failureMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Widget _controls(int count) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppText(
        _cloud ? '云端阅读历史' : '设备内阅读历史',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      AppText(
        _cloud
            ? '${widget.session.source.label} · $_cloudTotal 本'
            : '$count 本 · 按来源分组',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      AppSourceSwitch(
        cloud: _cloud,
        localLabel: '本地历史',
        cloudLabel: '云端历史',
        padding: const EdgeInsets.symmetric(vertical: 12),
        onChanged: _switch,
      ),
      if (!_cloud || !widget.session.isPic && widget.session.loggedIn) ...[
        SearchBar(
          controller: _search,
          hintText: AppTranslations.text(context, _cloud ? '筛选当前页' : '搜索历史'),
          leading: const Icon(Icons.search),
          trailing: [
            if (_query.isNotEmpty)
              IconButton(
                tooltip: AppTranslations.text(context, '清空搜索'),
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() {
                  _query = '';
                  _search.clear();
                  _selected.clear();
                  _page = 1;
                }),
              ),
          ],
          onChanged: (value) => setState(() {
            _query = value;
            _page = 1;
            _selected.clear();
          }),
        ),
      ],
      if (!_cloud) ...[
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: LibrarySelectionToggle(
            selected: _selecting,
            onPressed: () => setState(() {
              _selecting = !_selecting;
              _selected.clear();
            }),
          ),
        ),
      ],
      if (_cloudBusy) const LinearProgressIndicator(),
    ],
  );
  Widget? _cloudStatus() {
    if (!_cloud) return null;
    if (widget.session.isPic) {
      return AppStatus(
        icon: Icons.cloud_off_outlined,
        title: 'Pic 暂无云端历史接口',
        message: '本地阅读记录仍完整保留，可返回本地历史查看。',
        action: FilledButton.tonal(
          onPressed: () => _switch(false),
          child: const AppText('查看本地历史'),
        ),
      );
    }
    if (!widget.session.loggedIn) {
      return AppStatus(
        icon: Icons.cloud_outlined,
        title: '登录后查看云端历史',
        action: FilledButton.icon(
          icon: const Icon(Icons.login),
          label: const AppText('登录'),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LoginScreen(session: widget.session),
              ),
            );
            if (mounted) await _loadCloud();
          },
        ),
      );
    }
    if (_cloudError != null) {
      return AppFailure(
        error: _cloudError!,
        retry: () => _loadCloud(page: _cloudPage),
        session: widget.session,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final all = ContentSource.values
        .expand(
          (source) =>
              session.store.history.where((p) => p.comic.source == source),
        )
        .where(
          (p) => p.comic.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final maxPage = (all.length / 30).ceil().clamp(1, 1000000),
        page = _page.clamp(1, (all.length / 30).ceil().clamp(1, 1000000));
    final localRows = sourceSections(
      all.skip((page - 1) * 30).take(30),
      (p) => p.comic.source,
    );
    final cloudRows = sourceSections(
      _cloudItems.where(
        (c) => c.title.toLowerCase().contains(_query.toLowerCase()),
      ),
      (c) => c.source,
    );
    final status = _cloudStatus();
    final rowCount = _cloud ? cloudRows.length : localRows.length;
    return LibrarySelectionLayout(
      bodyBuilder: (bottomInset) => LibraryScrollView(
        bottomInset: bottomInset,
        storageKey: 'history:${_cloud ? session.source.id : 'local'}',
        controller: _scroll,
        onRefresh: _refresh,
        header: _controls(all.length),
        slivers: [
          if (status != null)
            SliverFillRemaining(hasScrollBody: false, child: status)
          else if (rowCount == 0)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _cloudBusy
                  ? const SizedBox.shrink()
                  : AppStatus(
                      icon: Icons.history,
                      title: _query.isNotEmpty
                          ? '没有匹配历史'
                          : _cloud
                          ? '暂无云端历史'
                          : '阅读后会在这里保留进度',
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: rowCount,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (_cloud) {
                    final row = cloudRows[index];
                    if (row.item == null) return SourceSection(row.source);
                    final comic = row.item!;
                    return LibraryBookTile(
                      comic: comic,
                      imageHost: session.imageHostFor(comic),
                      subtitle: const AppText('云端阅读记录'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openComic(context, session, comic),
                    );
                  }
                  final row = localRows[index];
                  if (row.item == null) return SourceSection(row.source);
                  final entry = row.item!, comic = entry.comic;
                  return LibraryBookTile(
                    comic: comic,
                    imageHost: session.imageHostFor(comic),
                    selected: _selecting ? _selected.contains(comic.key) : null,
                    onSelect: _removing ? null : (_) => _toggle(comic.key),
                    subtitle: AppText('已读至第 ${entry.page + 1} 页'),
                    trailing: const Icon(Icons.play_circle_outline),
                    onLongPress: () => setState(() {
                      _selecting = true;
                      _selected.add(comic.key);
                    }),
                    onTap: () => _selecting
                        ? _toggle(comic.key)
                        : openProgress(context, session, entry),
                  );
                },
              ),
            ),
          if (status == null &&
              (!_cloud && all.isNotEmpty || _cloud && _cloudItems.isNotEmpty))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: AppTranslations.text(context, '上一页'),
                      icon: const Icon(Icons.chevron_left),
                      onPressed:
                          (_cloud ? _cloudBusy || _cloudPage <= 1 : page <= 1)
                          ? null
                          : () {
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                              if (_cloud) {
                                _loadCloud(page: _cloudPage - 1);
                              } else {
                                setState(() => _page = page - 1);
                              }
                            },
                    ),
                    AppText(
                      _cloud
                          ? '第 $_cloudPage 页 · 共 $_cloudTotal 本'
                          : '$page / $maxPage',
                    ),
                    IconButton(
                      tooltip: AppTranslations.text(context, '下一页'),
                      icon: const Icon(Icons.chevron_right),
                      onPressed:
                          (_cloud ? _cloudBusy || !_cloudMore : page >= maxPage)
                          ? null
                          : () {
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                              if (_cloud) {
                                _loadCloud(page: _cloudPage + 1);
                              } else {
                                setState(() => _page = page + 1);
                              }
                            },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      selectionBar: LibrarySelectionBar(
        visible: !_cloud && _selecting,
        count: _selected.length,
        onDone: () => setState(() {
          _selecting = false;
          _selected.clear();
        }),
        actions: [
          TextButton(
            onPressed: _removing
                ? null
                : () => setState(
                    () => _selected.addAll(all.map((p) => p.comic.key)),
                  ),
            child: const AppText('全选'),
          ),
          TextButton(
            onPressed: _removing || _selected.isEmpty ? null : _deleteSelected,
            child: const AppText('删除'),
          ),
        ],
      ),
    );
  }
}
