import 'package:flutter/material.dart';
import 'app.dart';
import 'translations.dart';

class CommentEditor extends StatefulWidget {
  const CommentEditor({
    super.key,
    required this.session,
    required this.aid,
    this.reply = '',
    this.recipient = '',
  });
  final AppSession session;
  final String aid, reply, recipient;
  @override
  State<CommentEditor> createState() => _CommentEditorState();
}

class _CommentEditorState extends State<CommentEditor> {
  late final _owner = '${widget.session.api.userProfile?['uid'] ?? 'guest'}';
  late final _key = widget.session.prefKey(
    'comment_draft:$_owner:${widget.aid}:${widget.reply}',
  );
  late final _text = TextEditingController(
    text: widget.session.store.preferences.getString(_key) ?? '',
  );
  bool _busy = false;
  String? _error;
  Future<void> _send() async {
    if (_busy || _text.text.trim().isEmpty) return;
    if (!widget.session.loggedIn ||
        '${widget.session.api.userProfile?['uid'] ?? 'guest'}' != _owner) {
      setState(() => _error = '账号已变化，请关闭编辑器并重新登录；原草稿已保留');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.comment(
        widget.aid,
        _text.text.trim(),
        reply: widget.reply,
      );
      await widget.session.store.preferences.remove(_key);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '发送未成功，草稿已保留。$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: AppText(widget.reply.isEmpty ? '发表评论' : '回复 @${widget.recipient}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.reply.isNotEmpty) AppText('评论编号：${widget.reply}'),
            TextField(
              controller: _text,
              enabled: !_busy,
              autofocus: true,
              minLines: 5,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: '评论内容',
                helperText: '关闭后保留设备内草稿',
              ),
              onChanged: (value) async {
                await widget.session.store.preferences.setString(_key, value);
                if (mounted) setState(() {});
              },
            ),
            if (_error != null) AppText(_error!),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const AppText('保存草稿并关闭'),
        ),
        FilledButton(
          onPressed: _busy || _text.text.trim().isEmpty ? null : _send,
          child: const AppText('发送'),
        ),
      ],
    ),
  );
}
