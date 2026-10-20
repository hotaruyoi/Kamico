import 'motion.dart';
import 'design_system.dart';
import 'translations.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../data/download_repository.dart';
import '../data/platform_files.dart';
import '../app_identity.dart';
import 'app.dart';
import 'dialogs.dart';
import '../data/download_queue.dart';
import 'library_layout.dart';
import 'reading_navigation.dart';
import 'failure.dart';
import 'discovery.dart' show selectOption;

const jobLabels = {
  'queued': '等待',
  'running': '下载中',
  'paused': '已暂停',
  'failed': '失败',
  'done': '已完成',
  'cancelled': '已取消',
};

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({
    super.key,
    required this.session,
    this.initialLibrary = false,
  });
  final AppSession session;
  final bool initialLibrary;
  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  bool _library = false, _busy = false, _descending = false;
  bool _selecting = false;
  String? _operationStatus;
  int _bytes = 0;
  int? _available;
  String _query = '', _state = 'all';
  List<OfflineChapter> _chapters = [];
  final _selected = <String>{};
  String _key(OfflineChapter c) => '${c.comic.key}:${c.chapter.id}';
  @override
  void initState() {
    super.initState();
    _library = widget.initialLibrary;
    widget.session.queue.addListener(_queueChanged);
    _reload();
  }

  int _completed = 0;
  void _queueChanged() {
    final count = widget.session.queue.jobs.values
        .where((j) => j.state == 'done')
        .length;
    if (count != _completed) {
      _completed = count;
      _reload();
    }
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    try {
      final chapters = await widget.session.downloads.list();
      final bytes = await widget.session.downloads.bytes;
      final info = await PlatformFiles.storageInfo();
      if (mounted) {
        setState(() {
          _chapters = chapters;
          _bytes = bytes;
          _available = info?['available'] as int?;
          _selected.retainAll(chapters.map(_key));
        });
        widget.session.rememberOffline(chapters);
      }
    } catch (e) {
      if (mounted) {
        _message(
          '${_operationStatus == null ? '' : '$_operationStatus；已成功导出的文件保留，可再次导出。\n'}$e',
        );
      }
    }
  }

  void _message(Object message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: AppText(
        message is Exception ? failureMessage(message) : '$message',
      ),
    ),
  );
  Future<void> _operation(Future<void> Function() run) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await run();
      if (mounted) await _reload();
    } catch (e) {
      if (mounted) {
        _message(
          '${_operationStatus == null ? '' : '$_operationStatus；已成功导出的文件保留，可重试。\n'}$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _operationStatus = null;
        });
      }
    }
  }

  Future<void> _import() async {
    await _operation(() async {
      final root = await widget.session.downloads.directory;
      final entries = await PlatformFiles.importDirectory(root.path);
      if (entries.isEmpty) {
        if (mounted) _message('未导入图片：可能已取消，或目录内没有支持的图片');
        return;
      }
      for (final entry in entries) {
        final comic = Map<String, dynamic>.from(entry['comic'] as Map);
        comic['source'] ??= widget.session.source.id;
        entry['comic'] = comic;
      }
      await widget.session.downloads.registerImports(entries);
      final books = {
        for (final e in entries)
          '${e['comic']['id']}': Comic.fromJson(e['comic'] as Json),
      };
      for (final comic in books.values) {
        await widget.session.store.addLocal(comic);
      }
      if (mounted) _message('已导入 ${entries.length} 个章节；可在本地收藏中分组管理');
    });
  }

  Future<void> _export() async {
    var tree = widget.session.store.preferences.getString('export_tree');
    if (tree == null) {
      tree = await PlatformFiles.pickDirectory();
      if (tree == null || !mounted) return;
      await widget.session.store.preferences.setString('export_tree', tree);
    }
    final selected = _chapters
        .where((c) => _selected.contains(_key(c)))
        .toList();
    if (!mounted) return;
    if (!await confirm(
      context,
      '将 ${selected.length} 个章节另存为 PDF？已有文件保留，由系统处理重名。',
    )) {
      return;
    }
    await _operation(() async {
      var completed = 0;
      for (final chapter in selected) {
        if (mounted) {
          setState(
            () => _operationStatus =
                '正在导出 ${completed + 1}/${selected.length} · ${chapter.chapter.title}',
          );
        }
        final naming =
            widget.session.store.preferences.getString('download_naming') ??
            'id_title';
        final book = switch (naming) {
          'id' => chapter.comic.id,
          'title_id' => '${chapter.comic.title}_${chapter.comic.id}',
          _ => '${chapter.comic.id}_${chapter.comic.title}',
        };
        final pdf = await widget.session.downloads.ensurePdf(chapter);
        await PlatformFiles.publishPdf(
          pdf.path,
          book,
          '${chapter.chapter.title}_${chapter.chapter.exportId}',
          tree: tree,
          source: chapter.comic.source == ContentSource.jm ? 'JM' : 'PIC',
        );
        completed++;
      }
      if (mounted) _message('已导出 ${selected.length} 个章节');
      if (mounted) setState(() => _operationStatus = null);
    });
  }

  Future<void> _settings() async {
    final store = widget.session.store;
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.sheet(context),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .75,
          child: StatefulBuilder(
            builder: (context, update) => ListView(
              children: [
                const ListTile(title: AppText('下载与导出设置')),
                ListTile(
                  title: const AppText('PDF 下载目录'),
                  subtitle: SelectableText(
                    '系统 Downloads/$publicDownloadsFolder/作品名称_编号/章节名称_编号.pdf',
                  ),
                ),
                ListTile(
                  title: AppText(
                    '同时下载 ${widget.session.queue.concurrency} 个章节',
                  ),
                  subtitle: Slider(
                    min: 1,
                    max: 3,
                    divisions: 2,
                    value: widget.session.queue.concurrency.toDouble(),
                    onChanged: (v) async {
                      await store.preferences.setInt(
                        'download_concurrency',
                        v.round(),
                      );
                      widget.session.queue.reschedule();
                      update(() {});
                    },
                  ),
                ),
                ListTile(
                  title: AppText(
                    '失败自动重试 ${store.preferences.getInt('download_retries') ?? 2} 次',
                  ),
                  subtitle: Slider(
                    min: 0,
                    max: 5,
                    divisions: 5,
                    value: (store.preferences.getInt('download_retries') ?? 2)
                        .toDouble(),
                    onChanged: (v) async {
                      await store.preferences.setInt(
                        'download_retries',
                        v.round(),
                      );
                      update(() {});
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: selectOption(
                    '导出命名',
                    store.preferences.getString('download_naming') ??
                        'id_title',
                    const {
                      'id_title': '编号_标题',
                      'title_id': '标题_编号',
                      'id': '仅编号',
                    },
                    (v) async {
                      await store.preferences.setString('download_naming', v);
                      update(() {});
                    },
                  ),
                ),
                ListTile(
                  title: const AppText('选择导出目录'),
                  subtitle: AppText(
                    store.preferences.getString('export_tree') ?? '未选择',
                  ),
                  trailing: const Icon(Icons.folder_open),
                  onTap: () async {
                    try {
                      final tree = await PlatformFiles.pickDirectory();
                      if (tree != null) {
                        await store.preferences.setString('export_tree', tree);
                        update(() {});
                      }
                    } catch (e) {
                      if (mounted) _message('$e');
                    }
                  },
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: AppText(
                    '每章保存为无白边、按阅读顺序排列的 PDF。应用内保留断点及离线缓存；卸载不会删除系统下载目录中的 PDF。请保持应用在前台完成下载。',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.session.queue.removeListener(_queueChanged);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _expanded = <String>{};

  Future<void> _bulkAdd() async {
    final input = await prompt(context, '输入漫画编号，逗号或空格分隔');
    if (!mounted || input == null) return;
    await _operation(() async {
      for (final text
          in input.split(RegExp(r'[\s,，;；]+')).where((e) => e.isNotEmpty)) {
        final id = widget.session.isPic
            ? text
            : text.replaceFirst(RegExp(r'^JM', caseSensitive: false), '');
        if (!(widget.session.isPic
                ? RegExp(r'^[a-fA-F0-9]{24}$')
                : RegExp(r'^\d+$'))
            .hasMatch(id)) {
          throw FormatException('无效编号：$text');
        }
        final detail = await widget.session.api.detail(id);
        if (detail.price > 0 && !detail.purchased) {
          throw const FormatException('请先购买后下载');
        }
        final result = await widget.session.queue.enqueue(
          detail.comic,
          detail.chapters,
        );
        if (mounted) _message('${detail.comic.title} · ${result.message}');
      }
    });
  }

  Future<void> _deleteSelected() async {
    final selected = _chapters
        .where((c) => _selected.contains(_key(c)))
        .toList();
    if (selected.any(
      (c) => [
        'running',
        'queued',
      ].contains(widget.session.queue.jobs[_key(c)]?.state),
    )) {
      _message('请先暂停对应下载任务再删除');
      return;
    }
    if (!await confirm(
      context,
      '删除选中的 ${selected.length} 个章节的应用内缓存？系统下载目录中的 PDF 保留。\n${selected.take(5).map((c) => '${c.comic.title} / ${c.chapter.title}').join('\n')}\n文件删除无法撤销。',
      title: '删除离线文件',
      action: '删除文件',
    )) {
      return;
    }
    if (!mounted) return;
    await _operation(() async {
      for (final chapter in selected) {
        await widget.session.downloads.delete(chapter);
        widget.session.queue.remove(_key(chapter));
      }
      _selected.clear();
    });
  }

  void _toggle(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });
  void _expand(String book) => setState(() {
    final key = '${_library ? 'offline' : 'jobs'}:$book';
    if (!_expanded.add(key)) _expanded.remove(key);
  });
  Future<void> _statusSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: AppMotion.sheet(context),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: AppText('任务状态')),
            for (final entry in {'all': '全部', ...jobLabels}.entries)
              ListTile(
                title: AppText(entry.value),
                selected: _state == entry.key,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (mounted && result != null) setState(() => _state = result);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session, queue = session.queue;
    final chapters = _chapters
        .where(
          (c) => '${c.comic.title} ${c.chapter.title}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    final jobs = queue.jobs.values
        .where(
          (j) =>
              (_state == 'all' || j.state == _state) &&
              '${j.comic.title} ${j.chapter.title}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();
    final offlineGroups = <String, List<OfflineChapter>>{};
    final jobGroups = <String, List<DownloadJob>>{};
    for (final chapter in chapters) {
      (offlineGroups[chapter.comic.key] ??= []).add(chapter);
    }
    for (final job in jobs) {
      (jobGroups[job.comic.key] ??= []).add(job);
    }
    final books = _library
        ? offlineGroups.keys.toList()
        : jobGroups.keys.toList();
    if (_library) {
      books.sort(
        (a, b) =>
            (_descending ? -1 : 1) *
            offlineGroups[a]!.first.comic.title.compareTo(
              offlineGroups[b]!.first.comic.title,
            ),
      );
    }
    ContentSource sourceOf(String book) => _library
        ? offlineGroups[book]!.first.comic.source
        : jobGroups[book]!.first.comic.source;
    final order = {for (final (index, book) in books.indexed) book: index};
    books.sort((a, b) {
      final bySource = sourceOf(a).index.compareTo(sourceOf(b).index);
      return bySource == 0 ? order[a]!.compareTo(order[b]!) : bySource;
    });
    final rows = <({String book, OfflineChapter? offline, DownloadJob? job})>[];
    ContentSource? previousSource;
    for (final book in books) {
      final source = sourceOf(book);
      if (source != previousSource) {
        rows.add((book: '__source_${source.id}', offline: null, job: null));
        previousSource = source;
      }
      rows.add((book: book, offline: null, job: null));
      if (_expanded.contains('${_library ? 'offline' : 'jobs'}:$book')) {
        if (_library) {
          for (final chapter in offlineGroups[book]!) {
            rows.add((book: book, offline: chapter, job: null));
          }
        } else {
          for (final job in jobGroups[book]!) {
            rows.add((book: book, offline: null, job: job));
          }
        }
      }
    }
    final running = queue.jobs.values.where((j) => j.state == 'running').length;
    final waiting = queue.jobs.values.where((j) => j.state == 'queued').length;
    return Column(
      children: [
        Expanded(
          child: LibraryScrollView(
            storageKey: 'downloads',
            controller: _scroll,
            onRefresh: _reload,
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
                            _library ? '离线书库' : '下载管理',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          AppText(
                            _library
                                ? '${_chapters.map((c) => c.comic.key).toSet().length} 本 · ${_chapters.length} 章 · ${(_bytes / 1048576).toStringAsFixed(1)} MB'
                                : '${queue.jobs.length} 章 · 进行中 $running · 等待 $waiting',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppTranslations.text(context, '下载设置'),
                      onPressed: _busy ? null : _settings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: AppText('下载任务'),
                      icon: Icon(Icons.downloading_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: AppText('本地书库'),
                      icon: Icon(Icons.folder_outlined),
                    ),
                  ],
                  selected: {_library},
                  onSelectionChanged: (values) {
                    setState(() {
                      _library = values.single;
                      _selecting = false;
                      _selected.clear();
                    });
                    if (_library) _reload();
                  },
                ),
                const SizedBox(height: 12),
                SearchBar(
                  controller: _search,
                  leading: const Icon(Icons.search),
                  hintText: AppTranslations.text(context, '搜索任务或本地漫画'),
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
                  onChanged: (v) => setState(() {
                    _query = v;
                    _selected.clear();
                  }),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _bulkAdd,
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: const AppText('批量下载编号'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const AppText('导入本地目录'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_library) ...[
                      ActionChip(
                        avatar: const Icon(Icons.sort_by_alpha, size: 18),
                        label: AppText(_descending ? '标题降序' : '标题升序'),
                        onPressed: () =>
                            setState(() => _descending = !_descending),
                      ),
                      if (!_selecting)
                        TextButton.icon(
                          onPressed: () => setState(() => _selecting = true),
                          icon: const Icon(Icons.checklist),
                          label: const AppText('选择'),
                        ),
                    ] else ...[
                      ActionChip(
                        avatar: const Icon(Icons.filter_list, size: 18),
                        label: AppText(
                          _state == 'all' ? '全部状态' : jobLabels[_state]!,
                        ),
                        onPressed: _statusSheet,
                      ),
                      TextButton(
                        onPressed: running + waiting == 0
                            ? null
                            : () {
                                for (final job in queue.jobs.values.toList()) {
                                  queue.pause(job.id);
                                }
                              },
                        child: const AppText('全部暂停'),
                      ),
                      TextButton(
                        onPressed:
                            !queue.jobs.values.any(
                              (j) => ['paused', 'failed'].contains(j.state),
                            )
                            ? null
                            : () {
                                for (final job in queue.jobs.values.toList()) {
                                  if ([
                                    'paused',
                                    'failed',
                                  ].contains(job.state)) {
                                    queue.resume(job.id);
                                  }
                                }
                              },
                        child: const AppText('全部继续'),
                      ),
                    ],
                  ],
                ),
                if (_available != null)
                  AppText(
                    '设备可用 ${(_available! / 1073741824).toStringAsFixed(1)} GB · 下载占用 ${(_bytes / 1048576).toStringAsFixed(1)} MB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (running + waiting > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AppText(
                      '下载期间请保持应用在前台；后台或系统回收可能中断，下次打开可恢复',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_operationStatus != null) AppText(_operationStatus!),
                if (queue.persistenceError != null)
                  AppText(queue.persistenceError!),
              ],
            ),
            slivers: [
              if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppStatus(
                    icon: _library
                        ? Icons.offline_pin_outlined
                        : Icons.download_outlined,
                    title: _query.isNotEmpty || !_library && _state != 'all'
                        ? '没有匹配内容'
                        : _library
                        ? '暂无已下载章节'
                        : '暂无下载任务',
                    message: _library
                        ? '在作品详情下载，或导入设备内图片目录'
                        : '从作品详情选章下载，任务会显示在这里',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index],
                          chapter = row.offline,
                          job = row.job;
                      if (row.book.startsWith('__source_')) {
                        return SourceSection(
                          ContentSource.parse(row.book.substring(9)),
                        );
                      }
                      if (chapter != null) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.menu_book_outlined),
                              trailing: _selecting
                                  ? Checkbox(
                                      value: _selected.contains(_key(chapter)),
                                      onChanged: (_) => _toggle(_key(chapter)),
                                    )
                                  : null,
                              title: Text(chapter.chapter.title),
                              subtitle: AppText('${chapter.count} 页 · 离线可读'),
                              onLongPress: () => setState(() {
                                _selecting = true;
                                _selected.add(_key(chapter));
                              }),
                              onTap: () => _selecting
                                  ? _toggle(_key(chapter))
                                  : openChapter(
                                      context,
                                      session,
                                      chapter.comic,
                                      chapter.chapter,
                                    ),
                            ),
                          ),
                        );
                      }
                      if (job != null) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Card(
                            child: ListTile(
                              title: Text(job.chapter.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText(
                                    '${jobLabels[job.state] ?? job.state} · ${job.done}/${job.total}${job.attempts > 0 ? ' · 重试 ${job.attempts}' : ''}',
                                  ),
                                  if (job.total > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: LinearProgressIndicator(
                                        value: job.done / job.total,
                                      ),
                                    ),
                                  if (job.error.isNotEmpty) AppText(job.error),
                                ],
                              ),
                              trailing: AppActionMenu(
                                actions: [
                                  if (['queued', 'running'].contains(job.state))
                                    AppMenuAction(
                                      '暂停',
                                      Icons.pause,
                                      () => queue.pause(job.id),
                                    ),
                                  if ([
                                    'paused',
                                    'failed',
                                    'cancelled',
                                  ].contains(job.state))
                                    AppMenuAction(
                                      '继续 / 重试',
                                      Icons.play_arrow,
                                      () => queue.resume(job.id),
                                    ),
                                  if (job.state != 'done')
                                    AppMenuAction(
                                      '取消任务',
                                      Icons.cancel_outlined,
                                      () => queue.cancel(job.id),
                                    ),
                                  AppMenuAction(
                                    '移除记录（保留图片）',
                                    Icons.playlist_remove,
                                    () => queue.remove(job.id),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      final local = offlineGroups[row.book];
                      final tasks = jobGroups[row.book];
                      final comic = _library
                          ? local!.first.comic
                          : tasks!.first.comic;
                      final total =
                          tasks?.fold(0, (sum, j) => sum + j.total) ?? 0;
                      final done =
                          tasks?.fold(0, (sum, j) => sum + j.done) ?? 0;
                      final expanded = _expanded.contains(
                        '${_library ? 'offline' : 'jobs'}:${row.book}',
                      );
                      return LibraryBookTile(
                        comic: comic,
                        imageHost: session.imageHostFor(comic),
                        selected: _library && _selecting
                            ? local!.every((c) => _selected.contains(_key(c)))
                            : null,
                        onSelect: (_) => setState(() {
                          final keys = local!.map(_key).toList();
                          if (keys.every(_selected.contains)) {
                            _selected.removeAll(keys);
                          } else {
                            _selected.addAll(keys);
                          }
                        }),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              _library
                                  ? '${local!.length} 章已下载'
                                  : '${tasks!.where((j) => j.state == 'done').length}/${tasks.length} 章已完成',
                            ),
                            if (!_library)
                              Text(
                                [
                                  for (final state in [
                                    'running',
                                    'queued',
                                    'failed',
                                    'paused',
                                    'cancelled',
                                  ])
                                    if (tasks!.any((job) => job.state == state))
                                      '${AppTranslations.text(context, jobLabels[state]!)} ${tasks.where((job) => job.state == state).length}',
                                ].join(' · '),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            if (!_library)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: LinearProgressIndicator(
                                  value: total == 0
                                      ? 0
                                      : (done / total).clamp(0, 1),
                                ),
                              ),
                          ],
                        ),
                        trailing: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        onLongPress: !_library
                            ? null
                            : () => setState(() {
                                _selecting = true;
                                _selected.addAll(local!.map(_key));
                              }),
                        onTap: () => _expand(row.book),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        LibrarySelectionBar(
          visible: _library && _selecting,
          count: _selected.length,
          onDone: () => setState(() {
            _selecting = false;
            _selected.clear();
          }),
          actions: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _selected.addAll(chapters.map(_key))),
              child: const AppText('全选'),
            ),
            TextButton(
              onPressed: _selected.isEmpty || _busy ? null : _export,
              child: const AppText('导出选中'),
            ),
            TextButton(
              onPressed: _selected.isEmpty || _busy ? null : _deleteSelected,
              child: const AppText('删除文件'),
            ),
          ],
        ),
      ],
    );
  }
}
