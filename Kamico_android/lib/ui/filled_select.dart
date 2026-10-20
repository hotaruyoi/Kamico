import 'package:flutter/material.dart';
import 'motion.dart';
import 'translations.dart';

/// A non-editable selector. Menus remain anchored to the control, with full labels.
class FilledSelect extends StatefulWidget {
  const FilledSelect({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.minimumHeight = 0,
    this.leading,
    this.valueStyle,
  });
  final String label, value;
  final Map<String, String> choices;
  final ValueChanged<String> onChanged;
  final double minimumHeight;
  final IconData? leading;
  final TextStyle? valueStyle;
  @override
  State<FilledSelect> createState() => _FilledSelectState();
}

class _FilledSelectState extends State<FilledSelect> {
  bool _open = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.hasBoundedWidth ? box.maxWidth : 240.0;
      final colors = Theme.of(context).colorScheme;
      return SizedBox(
        width: width,
        child: MenuAnchor(
          animated: !MediaQuery.disableAnimationsOf(context),
          consumeOutsideTap: true,
          onOpen: () => setState(() => _open = true),
          onClose: () {
            if (mounted) setState(() => _open = false);
          },
          style: MenuStyle(
            minimumSize: WidgetStatePropertyAll(
              Size(
                width.clamp(
                  48,
                  (MediaQuery.sizeOf(context).width - 32).clamp(48, 420),
                ),
                0,
              ),
            ),
            maximumSize: WidgetStatePropertyAll(
              Size(
                (MediaQuery.sizeOf(context).width - 32).clamp(48, 420),
                MediaQuery.sizeOf(context).height * .45,
              ),
            ),
          ),
          menuChildren: [
            for (final entry in widget.choices.entries)
              MenuItemButton(
                leadingIcon: Icon(
                  widget.value == entry.key ? Icons.check : null,
                  size: 20,
                ),
                onPressed: () => widget.onChanged(entry.key),
                child: AppText(entry.value),
              ),
          ],
          builder: (context, controller, child) => Semantics(
            button: true,
            expanded: _open,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: Size(48, widget.minimumHeight),
                backgroundColor: _open
                    ? colors.secondaryContainer
                    : colors.surfaceContainerHigh,
                foregroundColor: colors.onSurface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: widget.choices.isEmpty
                  ? null
                  : () {
                      controller.isOpen
                          ? controller.close()
                          : controller.open();
                    },
              child: Row(
                children: [
                  if (widget.leading != null) ...[
                    Icon(widget.leading, size: 24),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppText(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        AppText(
                          widget.choices[widget.value] ?? widget.value,
                          style: widget.valueStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: AppMotion.duration(context, AppMotion.state),
                    curve: AppMotion.curve,
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Keep controls usable at large text scales without fixed-width overflow.
class OptionGrid extends StatelessWidget {
  const OptionGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 500 ? 2 : 1;
      final width = (box.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
