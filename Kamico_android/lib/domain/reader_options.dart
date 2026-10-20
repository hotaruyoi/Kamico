import 'package:flutter/material.dart' show IconData, Icons;

enum ReaderMode { vertical, reversePages, pages }

ReaderMode readerModeFromPreferences(String? value, int? legacy) {
  for (final mode in ReaderMode.values) {
    if (mode.name == value) return mode;
  }
  return switch (legacy) {
    0 || 2 || 6 => ReaderMode.pages,
    1 || 3 || 7 => ReaderMode.reversePages,
    _ => ReaderMode.vertical,
  };
}

extension ReaderModeInfo on ReaderMode {
  String get label => switch (this) {
    ReaderMode.vertical => '竖向连续滑动',
    ReaderMode.reversePages => '向右滑动',
    ReaderMode.pages => '向左滑动',
  };
  String get hint => switch (this) {
    ReaderMode.vertical => '↑ 向上滑动继续阅读，图片无缝衔接',
    ReaderMode.reversePages => '→ 手指向右滑动，进入下一页',
    ReaderMode.pages => '← 手指向左滑动，进入下一页',
  };
  IconData get icon => switch (this) {
    ReaderMode.vertical => Icons.swap_vert,
    ReaderMode.reversePages => Icons.swipe_right_alt,
    ReaderMode.pages => Icons.swipe_left_alt,
  };
  bool get reversed => this == ReaderMode.reversePages;
  bool get scrolling => this == ReaderMode.vertical;
}
