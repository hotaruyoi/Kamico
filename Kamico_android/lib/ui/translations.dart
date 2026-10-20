import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTranslations {
  static final Map<String, Map<String, String>> dictionaries = {};
  static final Map<String, List<_Template>> _templates = {};
  static Future<void> load() async {
    for (final language in ['en', 'zh_TW']) {
      dictionaries[language] = Map<String, String>.from(
        jsonDecode(await rootBundle.loadString('assets/i18n/$language.json'))
            as Map,
      );
      _templates[language] =
          dictionaries[language]!.entries
              .where((e) => RegExp(r'\{[a-z]+\}').hasMatch(e.key))
              .map(_Template.new)
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));
    }
  }

  static String text(BuildContext context, String source) =>
      translate(source, Localizations.localeOf(context));
  static String translate(String source, Locale locale) {
    final language = locale.languageCode == 'en'
        ? 'en'
        : locale.countryCode == 'TW' ||
              locale.countryCode == 'HK' ||
              locale.scriptCode == 'Hant'
        ? 'zh_TW'
        : 'zh_CN';
    final dictionary = dictionaries[language];
    if (dictionary == null) return source;
    if (dictionary.containsKey(source)) return dictionary[source]!;
    if (source.endsWith('：') &&
        dictionary.containsKey(source.substring(0, source.length - 1))) {
      return '${dictionary[source.substring(0, source.length - 1)]}:';
    }
    for (final entry in _templates[language] ?? <_Template>[]) {
      final match = entry.pattern.firstMatch(source);
      if (match == null) continue;
      var result = entry.value;
      for (var i = 0; i < entry.keys.length; i++) {
        result = result.replaceAll('{${entry.keys[i]}}', match[i + 1]!);
      }
      return result;
    }
    return source;
  }
}

class _Template {
  _Template(MapEntry<String, String> entry)
    : value = entry.value,
      length = entry.key.length {
    final source = entry.key.splitMapJoin(
      RegExp(r'\{(\w+)\}'),
      onMatch: (m) {
        keys.add(m[1]!);
        return '(.*?)';
      },
      onNonMatch: RegExp.escape,
    );
    pattern = RegExp('^$source\$', dotAll: true);
  }
  final String value;
  final int length;
  final keys = <String>[];
  late final RegExp pattern;
}

// Rebuilds with the locale, including routes that were already open.
class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });
  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Text(
    AppTranslations.text(context, data),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
  );
}
