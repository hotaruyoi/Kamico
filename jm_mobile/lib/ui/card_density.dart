import 'motion.dart';
import 'package:flutter/material.dart';
import '../domain/card_layout.dart';
import 'app.dart';
import 'translations.dart';
import 'design_system.dart';

String cardDensityLabel(CardDensity density) => switch (density) {
  CardDensity.large => '大卡片',
  CardDensity.medium => '中卡片',
  CardDensity.compact => '小卡片',
};

Future<void> showCardDensity(BuildContext context, AppSession session) async {
  await showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: AppMotion.sheet(context),
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('卡片大小'),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: AppText('列数随屏幕宽度自动调整'),
                ),
                for (final density in CardDensity.values)
                  ListTile(
                    selected:
                        ComicCardLayout.fromPreferences(
                          session.appearance,
                        ).density ==
                        density,
                    leading: Icon(switch (density) {
                      CardDensity.large => Icons.view_agenda_outlined,
                      CardDensity.medium => Icons.grid_view_outlined,
                      CardDensity.compact => Icons.apps,
                    }),
                    title: AppText(cardDensityLabel(density)),
                    subtitle: AppText(switch (density) {
                      CardDensity.large => '更大封面',
                      CardDensity.medium => '均衡浏览',
                      CardDensity.compact => '更高密度',
                    }),
                    trailing:
                        ComicCardLayout.fromPreferences(
                              session.appearance,
                            ).density ==
                            density
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () async {
                      await session.setAppearance('card_density', density.name);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class CardDensityButton extends StatelessWidget {
  const CardDensityButton({super.key, required this.session});
  final AppSession session;
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: AppTranslations.text(context, '卡片大小'),
    onPressed: () => showCardDensity(context, session),
    icon: const Icon(Icons.view_comfy_alt_outlined),
  );
}
