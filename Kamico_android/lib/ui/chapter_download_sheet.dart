import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'app.dart';
import 'translations.dart';

class ChapterDownloadSheet extends StatefulWidget {
  const ChapterDownloadSheet({
    super.key,
    required this.session,
    required this.detail,
  });
  final AppSession session;
  final ComicDetail detail;
  @override
  State<ChapterDownloadSheet> createState() => _ChapterDownloadSheetState();
}

class _ChapterDownloadSheetState extends State<ChapterDownloadSheet> {
  final _selected = <String>{}, _downloaded = <String>{};
  bool _loading = true;
  String _query = '';
  Object? _error;
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
      final entries = await widget.session.downloads.list();
      if (!mounted) return;
      setState(() {
        _downloaded.addAll(
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

  bool _available(Chapter chapter) =>
      !_downloaded.contains(chapter.id) &&
      !['queued', 'running', 'done'].contains(
        widget
            .session
            .queue
            .jobs['${widget.detail.comic.key}:${chapter.id}']
            ?.state,
      );
  void _selectRemaining() {
    _selected
      ..clear()
      ..addAll(widget.detail.chapters.where(_available).map((c) => c.id));
  }

  void _toggle(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });
  @override
  Widget build(BuildContext context) {
    final chapters = widget.detail.chapters
        .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();
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
                      '下载章节',
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
                        child: const AppText('读取离线状态失败，点击重试'),
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
                                const AppText('默认选择尚未下载、也未排队的章节；修改筛选会清空选择'),
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
                                      child: const AppText('仅选未下载'),
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
                            final state = widget
                                .session
                                .queue
                                .jobs['${widget.detail.comic.key}:${chapter.id}']
                                ?.state;
                            final status =
                                _downloaded.contains(chapter.id) ||
                                    state == 'done'
                                ? '已下载'
                                : switch (state) {
                                    'queued' => '排队中',
                                    'running' => '下载中',
                                    'paused' => '已暂停',
                                    'failed' => '下载失败',
                                    _ => '未下载',
                                  };
                            return CheckboxListTile(
                              value: _selected.contains(chapter.id),
                              onChanged: (_) => _toggle(chapter.id),
                              title: Text(chapter.title),
                              subtitle: AppText(status),
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
                  onPressed: _loading || _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          widget.detail.chapters
                              .where((c) => _selected.contains(c.id))
                              .toList(),
                        ),
                  icon: const Icon(Icons.download_outlined),
                  label: AppText('加入下载队列 (${_selected.length})'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
