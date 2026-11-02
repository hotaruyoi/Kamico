import 'package:html/parser.dart' as html;

import 'local_store.dart';

/// Global, regex-based comment filter.
///
/// One list is shared by every content source and every account, because the
/// rules describe what the reader never wants to read rather than anything
/// specific to one site.
class CommentFilter {
  const CommentFilter({this.enabled = false, this.rules = const []});
  final bool enabled;
  final List<String> rules;

  static const String key = 'comment_filters';
  static const int maxRules = 20;
  static const int maxLength = 200;

  static CommentFilter read(LocalStore store) {
    final data = store.readMap(key, {'enabled': false, 'rules': <String>[]});
    final rules = (data['rules'] as List? ?? const [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .take(maxRules)
        .toList(growable: false);
    return CommentFilter(enabled: data['enabled'] == true, rules: rules);
  }

  Future<void> save(LocalStore store) async {
    await store.writeMap(key, {'enabled': enabled, 'rules': rules});
  }

  CommentFilter copyWith({bool? enabled, List<String>? rules}) => CommentFilter(
    enabled: enabled ?? this.enabled,
    rules: rules ?? this.rules,
  );

  /// Whether the filter can actually hide anything.
  bool get active => enabled && rules.isNotEmpty;

  /// A stored pattern that no longer compiles is skipped instead of throwing:
  /// a bad entry must never take the whole comment list down.
  List<RegExp> get patterns => [
    for (final rule in rules) ?tryCompile(rule),
  ];

  static RegExp? tryCompile(String rule) {
    try {
      return RegExp(rule);
    } on FormatException {
      return null;
    }
  }

  /// Reason the rule cannot be saved, or null when it is fine.
  static String? validate(String rule) {
    final value = rule.trim();
    if (value.isEmpty) return '规则不能为空';
    if (value.length > maxLength) return '规则最多 200 个字符';
    if (tryCompile(value) == null) return '正则表达式无效';
    return null;
  }

  /// Strips markup exactly like the comment bubble does, so a rule sees the
  /// same text the reader sees.
  static String plain(String raw) =>
      html
          .parseFragment(
            raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
          )
          .text ??
      '';

  /// Case sensitivity is the regex author's choice: fixed here so `(?i)` and
  /// inline groups behave the way the pattern says.
  bool blocks(String raw) {
    if (!active) return false;
    final text = plain(raw);
    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }
}
