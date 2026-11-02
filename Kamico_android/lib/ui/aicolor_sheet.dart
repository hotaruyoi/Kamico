import 'package:flutter/material.dart';
import '../data/aicolor_repository.dart';
import '../domain/models.dart';
import 'app.dart';
import 'translations.dart';

/// Picks chapters of one book to hand to the background colorization queue.
/// The sheet never waits for work: it only enqueues, and results land in the
/// separate colorized library.
class AIColorSheet extends StatefulWidget {
  const AIColorSheet({super.key, required this.session, required this.detail});
  final AppSession session;
  final ComicDetail detail;
  @override
  State<AIColorSheet> createState() => _AIColorSheetState();
}

class _AIColorSheetState extends State<AIColorSheet> {
  /// Chapters already sitting in the colorized library.
  final _done = <String>{};
  /// Chapters the user picked in this sheet.
  final _selected = <String>{};
  bool _loading = true;
  String _query = '';
  Object? _error;

  AIColorRepository get _aicolor => widget.session.root.aicolor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _aicolor.output.list();
      if (!mounted) return;
      setState(() {
        _done
          ..clear()
          ..addAll(
            entries
                .where((e) => e.comic.key == widget.detail.comic.key)
                .map((e) => e.chapter.id),
          );
        _selectRemaining();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A chapter is offered when it is not colorized yet and no job holds it.
  bool _available(Chapter chapter) =>
      !_done.contains(chapter.id) &&
      !(_aicolor.jobs['${widget.detail.comic.key}:${chapter.id}']?.active ??
          false);

  void _selectRemaining() {
    _selected
      ..clear()
      ..addAll(widget.detail.chapters.where(_available).map((c) => c.id));
  }

  String _status(Chapter chapter) {
    if (_done.contains(chapter.id)) return '已上色';
    final job = _aicolor.jobs['${widget.detail.comic.key}:${chapter.id}'];
    if (job == null) return '未上色';
    return switch (job.state) {
      'queued' => '等待上色',
      'running' => job.total > 0
          ? '上色中 ${job.done}/${job.total}'
          : '上色中',
      'paused' => '已暂停',
      'failed' => '上色失败',
      'done' => '已上色',
      _ => '未上色',
    };
  }

  void _toggle(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });

  Future<void> _enqueue() async {
    final chapters = widget.detail.chapters
        .where((c) => _selected.contains(c.id))
        .toList();
    if (chapters.isEmpty) return;
    final result = await _aicolor.enqueue(widget.detail.comic, chapters);
    if (!mounted) return;
    Navigator.pop(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: AppText(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.detail.chapters
        .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final ready = _aicolor.supported;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(
                      'AI 上色章节',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: AppTranslations.text(context, '关闭'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: TextButton(
                        onPressed: _load,
                        child: const AppText('读取上色状态失败，点击重试'),
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  widget.detail.comic.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const AppText(
                                  '默认选择尚未上色的章节；修改筛选会清空选择。'
                                  '上色在后台逐章进行，完成后可在本地书库查看。',
                                ),
                                const SizedBox(height: 12),
                                SearchBar(
                                  leading: const Icon(Icons.search),
                                  hintText: AppTranslations.text(
                                    context,
                                    '搜索章节',
                                  ),
                                  onChanged: (v) => setState(() {
                                    _query = v;
                                    _selected.clear();
                                  }),
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: () => setState(
                                        () => _selected.addAll(
                                          chapters.map((c) => c.id),
                                        ),
                                      ),
                                      child: const AppText('全选筛选结果'),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _selected.clear();
                                        _selected.addAll(
                                          chapters
                                              .where(_available)
                                              .map((c) => c.id),
                                        );
                                      }),
                                      child: const AppText('仅选未上色'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          setState(_selected.clear),
                                      child: const AppText('清空选择'),
                                    ),
                                  ],
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
                          ),
                        SliverList.builder(
                          itemCount: chapters.length,
                          itemBuilder: (context, index) {
                            final chapter = chapters[index];
                            return CheckboxListTile(
                              value: _selected.contains(chapter.id),
                              onChanged: (_) => _toggle(chapter.id),
                              title: Text(chapter.title),
                              subtitle: AppText(_status(chapter)),
                            );
                          },
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading || _selected.isEmpty || !ready
                      ? null
                      : _enqueue,
                  icon: const Icon(Icons.auto_awesome),
                  label: AppText(
                    !ready
                        ? '当前设备不支持 AI 上色'
                        : '加入上色队列 (${_selected.length})',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
