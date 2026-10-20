import 'package:flutter/material.dart';
import 'translations.dart';
import 'motion.dart';

/// Shared Material 3 tokens and components used by every application route.
abstract final class AppDesign {
  static const pagePadding = EdgeInsets.all(16);
  static const contentWidth = 1200.0;
  static ThemeData theme(Color seed, Brightness brightness, String? font) {
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: font,
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide.none,
    );
    return base.copyWith(
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 3,
        titleSpacing: 24,
        toolbarHeight: 64,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          animationDuration: AppMotion.state,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          animationDuration: AppMotion.state,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          backgroundColor: colors.surfaceContainerHigh,
          foregroundColor: colors.onSurface,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          animationDuration: AppMotion.state,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          animationDuration: AppMotion.state,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          elevation: const WidgetStatePropertyAll(3),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          animationDuration: AppMotion.state,
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        backgroundColor: colors.surfaceContainerHigh,
        selectedColor: colors.secondaryContainer,
        secondarySelectedColor: colors.secondaryContainer,
        shape: const StadiumBorder(),
        elevation: 0,
        pressElevation: 0,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          animationDuration: AppMotion.state,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          backgroundColor: colors.surfaceContainerHigh,
          foregroundColor: colors.onSurfaceVariant,
          selectedBackgroundColor: colors.secondaryContainer,
          selectedForegroundColor: colors.onSecondaryContainer,
          minimumSize: const Size(48, 48),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: colors.secondaryContainer,
        iconColor: colors.onSurfaceVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
        height: 80,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.secondaryContainer,
        useIndicator: true,
        groupAlignment: -1,
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        constraints: const BoxConstraints(minHeight: 56),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: colors.surfaceContainerHigh,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: colors.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        space: 24,
        thickness: 1,
      ),
    );
  }
}

class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.child,
    this.maxWidth = AppDesign.contentWidth,
  });
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.tonal = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool tonal;
  @override
  Widget build(BuildContext context) => Card(
    color: tonal ? Theme.of(context).colorScheme.secondaryContainer : null,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: padding, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.icon});
  final String title;
  final Widget? action;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 24, 8, 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: AppText(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class AppStatus extends StatelessWidget {
  const AppStatus({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: colors.onSecondaryContainer),
              ),
              const SizedBox(height: 24),
              AppText(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                AppText(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class AppSourceSwitch extends StatelessWidget {
  const AppSourceSwitch({
    super.key,
    required this.cloud,
    required this.onChanged,
    this.cloudLabel = '云端',
    this.localLabel = '本地',
    this.padding = const EdgeInsets.all(16),
  });
  final bool cloud;
  final ValueChanged<bool>? onChanged;
  final String cloudLabel, localLabel;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: AppText(localLabel),
            icon: const Icon(Icons.phone_android_outlined),
          ),
          ButtonSegment(
            value: true,
            label: AppText(cloudLabel),
            icon: const Icon(Icons.cloud_outlined),
          ),
        ],
        selected: {cloud},
        onSelectionChanged: onChanged == null
            ? null
            : (value) => onChanged!(value.single),
      ),
    ),
  );
}

class AppMenuAction {
  const AppMenuAction(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class AppActionMenu extends StatelessWidget {
  const AppActionMenu({super.key, required this.actions, this.enabled = true});
  final List<AppMenuAction> actions;
  final bool enabled;
  @override
  Widget build(BuildContext context) => MenuAnchor(
    animated: !MediaQuery.disableAnimationsOf(context),
    menuChildren: actions
        .map(
          (a) => MenuItemButton(
            leadingIcon: Icon(a.icon),
            onPressed: a.onPressed,
            child: AppText(a.label),
          ),
        )
        .toList(),
    builder: (context, controller, child) => IconButton(
      tooltip: AppTranslations.text(context, '更多操作'),
      onPressed: enabled
          ? () {
              controller.isOpen ? controller.close() : controller.open();
            }
          : null,
      icon: const Icon(Icons.more_vert),
    ),
  );
}
