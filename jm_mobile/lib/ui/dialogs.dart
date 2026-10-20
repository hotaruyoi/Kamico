import 'motion.dart';
import 'translations.dart';
import 'package:flutter/material.dart';

Future<String?> prompt(
  BuildContext context,
  String title, {
  String initial = '',
  bool numeric = false,
}) => showDialog<String>(
  context: context,
  animationStyle: AppMotion.sheet(context),
  builder: (_) => _Prompt(title: title, initial: initial, numeric: numeric),
);
Future<bool> confirm(
  BuildContext context,
  String message, {
  String title = '确认操作',
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.sheet(context),
      builder: (context) => AlertDialog(
        title: AppText(title),
        content: AppText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: AppText(action),
          ),
        ],
      ),
    ) ??
    false;

class _Prompt extends StatefulWidget {
  const _Prompt({
    required this.title,
    required this.initial,
    required this.numeric,
  });
  final String title, initial;
  final bool numeric;
  @override
  State<_Prompt> createState() => _PromptState();
}

class _PromptState extends State<_Prompt> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: AppText(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_text.text.trim().isNotEmpty) {
            Navigator.pop(context, _text.text.trim());
          }
        },
        child: const AppText('确定'),
      ),
    ],
  );
}
