import 'motion.dart';
import 'package:flutter/material.dart';

import '../data/comment_filter.dart';
import '../data/local_store.dart';
import 'design_system.dart';
import 'translations.dart';

/// Regex rules that hide matching comments everywhere.
class CommentFilterSheet extends StatefulWidget {
  const CommentFilterSheet({super.key, required this.store});
  final LocalStore store;
  @override
  State<CommentFilterSheet> createState() => _CommentFilterSheetState();
}

class _CommentFilterSheetState extends State<CommentFilterSheet> {
  late CommentFilter _filter = CommentFilter.read(widget.store);
  String? _error;

  Future<void> _apply(CommentFilter next) async {
    setState(() => _filter = next);
    await next.save(widget.store);
  }

  Future<void> _add() async {
    if (_filter.rules.length >= CommentFilter.maxRules) return;
    final rule = await _editRule();
    if (rule == null || !mounted) return;
    if (_filter.rules.contains(rule)) {
      setState(() => _error = '该规则已存在');
      return;
    }
    setState(() => _error = null);
    await _apply(_filter.copyWith(rules: [..._filter.rules, rule]));
  }

  Future<void> _edit(int index) async {
    final rule = await _editRule(initial: _filter.rules[index]);
    if (rule == null || !mounted) return;
    if (_filter.rules.contains(rule) &&
        _filter.rules.indexOf(rule) != index) {
      setState(() => _error = '该规则已存在');
      return;
    }
    setState(() => _error = null);
    final rules = [..._filter.rules];
    rules[index] = rule;
    await _apply(_filter.copyWith(rules: rules));
  }

  Future<void> _remove(int index) async {
    final rules = [..._filter.rules]..removeAt(index);
    setState(() => _error = null);
    await _apply(_filter.copyWith(rules: rules));
  }

  Future<String?> _editRule({String initial = ''}) => showDialog<String>(
    context: context,
    animationStyle: AppMotion.sheet(context),
    builder: (_) => _RuleDialog(initial: initial),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = _filter.rules.length >= CommentFilter.maxRules;
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
                      '评论筛选',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: AppTranslations.text(context, '关闭'),
                    onPressed: () => Navigator.pop(context, _filter),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  AppPanel(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile(
                      title: const AppText('启用筛选'),
                      subtitle: const AppText('关闭后所有评论都会重新显示'),
                      value: _filter.enabled,
                      onChanged: (value) =>
                          _apply(_filter.copyWith(enabled: value)),
                    ),
                  ),
                  const SectionTitle('筛选规则'),
                  AppPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (index, rule) in _filter.rules.indexed) ...[
                          if (index > 0)
                            const Divider(
                              height: 1,
                              indent: 56,
                              endIndent: 16,
                            ),
                          ListTile(
                            leading: const Icon(Icons.filter_alt_outlined),
                            title: AppText(rule, maxLines: 2),
                            subtitle: CommentFilter.tryCompile(rule) == null
                                ? const AppText('正则表达式无效，已跳过')
                                : null,
                            onTap: () => _edit(index),
                            trailing: IconButton(
                              tooltip: AppTranslations.text(context, '删除'),
                              onPressed: () => _remove(index),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ],
                        if (_filter.rules.isEmpty)
                          const ListTile(
                            leading: Icon(Icons.filter_alt_off_outlined),
                            title: AppText('还没有筛选规则'),
                            subtitle: AppText('匹配的评论不会出现在评论区'),
                          ),
                        const Divider(height: 1, indent: 56, endIndent: 16),
                        ListTile(
                          enabled: !full,
                          leading: const Icon(Icons.add),
                          title: const AppText('添加规则'),
                          subtitle: full
                              ? const AppText('最多 20 条规则')
                              : const AppText(
                                  '使用正则表达式匹配评论正文，最多 200 字符',
                                ),
                          onTap: full ? null : _add,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  AppText(
                    '规则只匹配主评论的正文，不匹配楼中楼。默认大小写敏感，需要忽略大小写时请写成 (?i:…)。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small editor that keeps the dialog open until the pattern compiles.
class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.initial});
  final String initial;
  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final rule = _text.text.trim();
    final problem = CommentFilter.validate(rule);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const AppText('筛选规则'),
    content: TextField(
      controller: _text,
      autofocus: true,
      minLines: 1,
      maxLines: 4,
      maxLength: CommentFilter.maxLength,
      decoration: InputDecoration(
        labelText: AppTranslations.text(context, '正则表达式'),
        errorText: _error,
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('取消'),
      ),
      FilledButton(onPressed: _submit, child: const AppText('保存')),
    ],
  );
}
