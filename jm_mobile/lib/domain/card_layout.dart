import 'models.dart';

enum CardDensity { large, medium, compact }

/// Card width is a target, not a fixed column count; the viewport decides columns.
class ComicCardLayout {
  ComicCardLayout.fromPreferences(Json prefs, {double? effectiveTextScale})
    : density =
          CardDensity.values
              .where((d) => d.name == prefs['card_density'])
              .firstOrNull ??
          CardDensity.medium,
      titleLines = integer(prefs['lines'] ?? 2).clamp(1, 4),
      textScale =
          effectiveTextScale ??
          ((prefs['scale'] as num?)?.toDouble() ?? 1).clamp(.8, 1.4);
  final CardDensity density;
  final int titleLines;
  final double textScale;
  bool get compact => density == CardDensity.compact;
  bool get showAuthor => !compact;
  double get targetWidth => switch (density) {
    CardDensity.large => 160,
    CardDensity.medium => 104,
    CardDensity.compact => 68,
  };
  double get spacing => switch (density) {
    CardDensity.large => 12,
    CardDensity.medium => 8,
    CardDensity.compact => 6,
  };
  double get padding => switch (density) {
    CardDensity.large => 12,
    CardDensity.medium => 8,
    CardDensity.compact => 4,
  };
  double get fontSize => compact ? 12 : 14;
  double get titleHeight => compact ? 16 : 20;
  int columns(double available) =>
      ((available + spacing) / (targetWidth + spacing)).floor().clamp(1, 30);
  double extent(double available) {
    final count = columns(available);
    final width = (available - spacing * (count - 1)) / count;
    return width * 4 / 3 +
        padding * 2 +
        titleLines * titleHeight * textScale +
        (showAuthor ? 4 + 16 * textScale : 0) +
        2;
  }
}
