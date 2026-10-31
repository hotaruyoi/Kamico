import 'dart:async';
import 'motion.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import '../domain/models.dart';
import 'app.dart';
import 'comment_editor.dart';
import 'design_system.dart';
import 'failure.dart';
import 'settings.dart';
import 'translations.dart';
import '../data/pic_client.dart';

/// Shared by an embedded detail tab and the standalone account comments route.
class CommentsBody extends StatefulWidget {
  const CommentsBody({
    super.key,
    required this.session,
    this.id = '',
    this.uid,
    this.nested = false,
  });
  final AppSession session;
  final String id;
  final String? uid;
  final bool nested;
  @override
  State<CommentsBody> createState() => _CommentsBodyState();
}

class _CommentsBodyState extends State<CommentsBody>
    with AutomaticKeepAliveClientMixin {
  final _items = <Json>[];
  int _page = 0, _pageSize = 0, _generation = 0;
  int? _total;
  bool _loading = false, _more = true, _composing = false;
  Object? _error;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_more)) return;
    final generation = ++_generation;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.session.api.comments(
        widget.id,
        page,
        uid: widget.uid,
      );
      if (!mounted || generation != _generation) return;
      final incoming = (data['list'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        if (reset) {
          _items.clear();
          _pageSize = incoming.length;
        }
        final ids = _items.map((e) => '${e['CID']}').toSet();
        for (final item in incoming) {
          if (item['CID'] == null || ids.add('${item['CID']}')) {
            _items.add(item);
          }
        }
        _page = page;
        _total = data['total'] == null ? null : integer(data['total']);
        final more = data['has_more'] ?? data['more'];
        _more =
            incoming.isNotEmpty &&
            (more != null
                ? more == true || '$more' == '1'
                : _total != null
                ? _pageSize > 0 && page * _pageSize < _total!
                : true);
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _compose({Json? reply}) async {
    if (_composing) return;
    setState(() => _composing = true);
    try {
      final sent = await showDialog<bool>(
        context: context,
        animationStyle: AppMotion.sheet(context),
        barrierDismissible: false,
        builder: (_) => CommentEditor(
          session: widget.session,
          aid: '${reply?['AID'] ?? widget.id}',
          reply: '${reply?['CID'] ?? ''}',
          recipient: '${reply?['username'] ?? '匿名'}',
        ),
      );
      if (mounted && sent == true) await _load(reset: true);
    } finally {
      if (mounted) setState(() => _composing = false);
    }
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification is ScrollUpdateNotification &&
        notification.metrics.axis == Axis.vertical &&
        notification.scrollDelta != null &&
        notification.scrollDelta! > 0 &&
        notification.metrics.extentAfter < 280 &&
        _error == null) {
      _load();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => NotificationListener<ScrollNotification>(
        onNotification: _scrolled,
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: CustomScrollView(
            key: PageStorageKey(
              'comments:${widget.session.source.id}:${widget.uid ?? ''}:${widget.id}',
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (widget.nested)
                SliverOverlapInjector(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppText(
                        _total == null ? '评论' : '评论 · $_total',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (widget.session.loggedIn && widget.id.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: _composing ? null : () => _compose(),
                          icon: const Icon(Icons.edit_outlined),
                          label: const AppText('发表评论'),
                        ),
                      if (!widget.session.loggedIn)
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  LoginScreen(session: widget.session),
                            ),
                          ),
                          child: const AppText('登录后评论'),
                        ),
                      IconButton(
                        tooltip: AppTranslations.text(context, '刷新评论'),
                        onPressed: _loading ? null : () => _load(reset: true),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),
              if (_items.isEmpty && _loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_items.isEmpty && _error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppFailure(
                    error: _error!,
                    retry: () => _load(reset: true),
                    session: widget.session,
                  ),
                )
              else if (_items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppStatus(
                    icon: Icons.chat_bubble_outline,
                    title: '暂无评论',
                    message: '阅读后，欢迎留下你的看法',
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _CommentThread(
                      key: ValueKey('${_items[index]['CID'] ?? index}'),
                      item: _items[index],
                      loadReplies: widget.session.api is PicClient
                          ? (page) => (widget.session.api as PicClient).replies(
                              '${_items[index]['CID']}',
                              page,
                            )
                          : null,
                      onReply: widget.session.loggedIn && !_composing
                          ? (item) => _compose(reply: item)
                          : null,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Column(
                            children: [
                              AppText(failureMessage(_error!)),
                              TextButton(
                                onPressed: () => _load(),
                                child: const AppText('重试'),
                              ),
                            ],
                          )
                        : _more
                        ? Center(
                            child: TextButton(
                              onPressed: () => _load(),
                              child: const AppText('加载更多评论'),
                            ),
                          )
                        : const Center(child: AppText('已显示全部评论')),
                  ),
                ),
              ],
              const SliverToBoxAdapter(
                child: SafeArea(top: false, child: SizedBox(height: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentThread extends StatefulWidget {
  const _CommentThread({
    super.key,
    required this.item,
    this.onReply,
    this.loadReplies,
  });
  final Json item;
  final ValueChanged<Json>? onReply;
  final Future<Json> Function(int)? loadReplies;
  @override
  State<_CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends State<_CommentThread> {
  bool _expanded = false;
  bool _loading = false, _more = true;
  int _page = 0;
  Object? _error;
  final _remoteReplies = <Json>[];
  Future<void> _loadReplies() async {
    if (_loading || widget.loadReplies == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _expanded = true;
    });
    try {
      final data = await widget.loadReplies!(_page + 1);
      if (!mounted) return;
      final ids = _remoteReplies.map((e) => e['CID']).toSet();
      setState(() {
        for (final raw in List<Json>.from(data['list'] as List? ?? [])) {
          if (ids.add(raw['CID'])) {
            _remoteReplies.add({...raw, 'AID': widget.item['AID']});
          }
        }
        _page++;
        _more = data['more'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Iterable<Json> _replies(Json parent) sync* {
    for (final value in parent['replys'] as List? ?? []) {
      final item = Map<String, dynamic>.from(value as Map);
      item['AID'] ??= parent['AID'];
      yield item;
      yield* _replies(item);
    }
  }

  Widget _content(Json item, {bool reply = false}) => Padding(
    padding: EdgeInsets.only(left: reply ? 12 : 0, top: reply ? 12 : 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${item['username'] ?? '匿名'}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${item['addtime'] ?? ''}',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Plain Text instead of SelectableText: every selectable text widget
        // registers a 500 ms long-press recognizer, and once it wins the gesture
        // arena the enclosing list stops scrolling when you drag from the text.
        // See docs/DECISIONS.md ("评论正文的长按复制").
        _CopyOnLongPress(
          text:
              html
                  .parseFragment(
                    '${item['content'] ?? ''}'.replaceAll(
                      RegExp(r'<br\s*/?>', caseSensitive: false),
                      '\n',
                    ),
                  )
                  .text ??
              '',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.55),
        ),
        if (widget.onReply != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => widget.onReply!(item),
              child: const AppText('回复'),
            ),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final replies = [..._replies(widget.item), ..._remoteReplies];
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _content(widget.item),
          for (final reply in (_expanded ? replies : replies.take(2)))
            _content(reply, reply: true),
          if (replies.length > 2)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: AppText(_expanded ? '收起回复' : '展开 ${replies.length} 条回复'),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) AppText(failureMessage(_error!)),
          if (widget.loadReplies != null &&
              _more &&
              integer(widget.item['replyTotal']) > 0)
            TextButton(
              onPressed: _loading ? null : _loadReplies,
              child: AppText(
                _error != null
                    ? '重试加载回复'
                    : _page == 0
                    ? '查看回复'
                    : '加载更多回复',
              ),
            ),
        ],
      ),
    );
  }
}

/// Long-press to copy that stays out of the gesture arena.
///
/// `SelectableText`, `SelectionArea` and `GestureDetector(onLongPress:)` all
/// register a long-press recognizer. After [kLongPressTimeout] that recognizer
/// wins the arena and the enclosing scroll view never receives the drag, so the
/// list feels frozen when you press the text (measured: 280 px of scroll at a
/// 400 ms hold, 0 px at 500 ms). A raw [Listener] sees pointer events without
/// competing, which keeps both scrolling and long-press copy working.
///
/// Trade-off: this copies the whole comment instead of letting the user drag a
/// partial selection. That is intentional — the copy target is a short comment,
/// and partial selection is not worth breaking scrolling.
class _CopyOnLongPress extends StatefulWidget {
  const _CopyOnLongPress({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_CopyOnLongPress> createState() => _CopyOnLongPressState();
}

class _CopyOnLongPressState extends State<_CopyOnLongPress> {
  static const _hold = Duration(milliseconds: 500);

  Timer? _timer;
  Offset? _origin;
  bool _fired = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    _origin = event.position;
    _fired = false;
    _timer?.cancel();
    _timer = Timer(_hold, () {
      if (!mounted) return;
      _fired = true;
      HapticFeedback.selectionClick();
      _copy();
    });
  }

  // Any movement past the touch slop means the user is scrolling, not copying.
  void _move(PointerMoveEvent event) {
    if (_fired) return;
    final origin = _origin ?? event.position;
    if ((event.position - origin).distance > kTouchSlop) _timer?.cancel();
  }

  void _up(PointerEvent _) {
    _timer?.cancel();
    _fired = false;
  }

  void _copy() {
    final text = widget.text;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: AppText('已复制评论内容'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: Text(widget.text, style: widget.style),
  );
}
