import 'package:flutter/material.dart' show IconData, Icons;
import 'content_source.dart';

enum DiscoveryShortcut { category, ranking, latest, serial, weekly }

extension DiscoveryShortcutInfo on DiscoveryShortcut {
  String get label => switch (this) {
    DiscoveryShortcut.category => '分类',
    DiscoveryShortcut.ranking => '排行榜',
    DiscoveryShortcut.latest => '最近更新',
    DiscoveryShortcut.serial => '每周连载',
    DiscoveryShortcut.weekly => '周刊推荐',
  };
  IconData get icon => switch (this) {
    DiscoveryShortcut.category => Icons.category_outlined,
    DiscoveryShortcut.ranking => Icons.leaderboard_outlined,
    DiscoveryShortcut.latest => Icons.update,
    DiscoveryShortcut.serial => Icons.calendar_view_week_outlined,
    DiscoveryShortcut.weekly => Icons.date_range_outlined,
  };
  bool get jmOnly =>
      this == DiscoveryShortcut.serial || this == DiscoveryShortcut.weekly;
  bool supports(ContentSource source) => source == ContentSource.jm || !jmOnly;
}

/// Keep known IDs once, and append newly introduced/missing entries in default order.
List<DiscoveryShortcut> discoveryShortcutOrder(dynamic raw) {
  final byId = {for (final item in DiscoveryShortcut.values) item.name: item};
  return {
    if (raw is List)
      for (final id in raw) ?byId[id],
    ...DiscoveryShortcut.values,
  }.toList();
}
