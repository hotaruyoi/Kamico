import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../domain/models.dart';
import 'cover_image.dart';
import 'translations.dart';
import 'design_system.dart';

/// Keep each source contiguous, retaining the caller's order within it.
List<({ContentSource source, T? item})> sourceSections<T>(
  Iterable<T> items,
  ContentSource Function(T) sourceOf,
) {
  final groups = <ContentSource, List<T>>{};
  for (final item in items) {
    (groups[sourceOf(item)] ??= []).add(item);
  }
  return [
    for (final source in ContentSource.values)
      if (groups[source]?.isNotEmpty == true) ...[
        (source: source, item: null),
        for (final item in groups[source]!) (source: source, item: item),
      ],
  ];
}

class SourceSection extends StatelessWidget {
  const SourceSection(this.source, {super.key});
  final ContentSource source;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
    child: Text(
      source == ContentSource.jm ? 'JM' : 'PIC',
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
}

/// One scroll surface keeps library controls from consuming the reading area.
class LibraryScrollView extends StatelessWidget {
  const LibraryScrollView({
    super.key,
    required this.storageKey,
    required this.header,
    required this.slivers,
    required this.onRefresh,
    this.controller,
    this.bottomInset = 0,
  });
  final String storageKey;
  final Widget header;
  final List<Widget> slivers;
  final Future<void> Function() onRefresh;
  final ScrollController? controller;
  final double bottomInset;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: CustomScrollView(
      key: PageStorageKey(storageKey),
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverToBoxAdapter(child: header),
        ),
        ...slivers,
        SliverToBoxAdapter(
          child: SafeArea(
            top: false,
            child: SizedBox(height: 16 + bottomInset),
          ),
        ),
      ],
    ),
  );
}

/// Float the action bar without shrinking the list or painting a rectangular dock.
class LibrarySelectionLayout extends StatefulWidget {
  const LibrarySelectionLayout({
    super.key,
    required this.bodyBuilder,
    required this.selectionBar,
  });
  final Widget Function(double bottomInset) bodyBuilder;
  final LibrarySelectionBar selectionBar;
  @override
  State<LibrarySelectionLayout> createState() => _LibrarySelectionLayoutState();
}

class _LibrarySelectionLayoutState extends State<LibrarySelectionLayout> {
  double _height = 0;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.bodyBuilder(widget.selectionBar.visible ? _height : 0),
      if (widget.selectionBar.visible)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BarMeasure(
            onHeight: (height) {
              if (mounted && _height != height) {
                setState(() => _height = height);
              }
            },
            child: widget.selectionBar,
          ),
        ),
    ],
  );
}

class _BarMeasure extends SingleChildRenderObjectWidget {
  const _BarMeasure({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BarMeasureBox(onHeight);
  @override
  void updateRenderObject(BuildContext context, _BarMeasureBox renderObject) =>
      renderObject.onHeight = onHeight;
}

class _BarMeasureBox extends RenderProxyBox {
  _BarMeasureBox(this.onHeight);
  ValueChanged<double> onHeight;
  double? _height;
  @override
  void performLayout() {
    super.performLayout();
    if (_height == size.height) return;
    _height = size.height;
    final height = size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}

class LibrarySelectionToggle extends StatelessWidget {
  const LibrarySelectionToggle({
    super.key,
    required this.selected,
    required this.onPressed,
  });
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: TextButton.icon(
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.checklist),
      label: const AppText('选择'),
    ),
  );
}

class LibraryBookTile extends StatelessWidget {
  const LibraryBookTile({
    super.key,
    required this.comic,
    required this.imageHost,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.selected,
    this.onSelect,
    this.trailing,
  });
  final Comic comic;
  final String imageHost;
  final Widget subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool? selected;
  final ValueChanged<bool?>? onSelect;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    color: selected == true
        ? Theme.of(context).colorScheme.secondaryContainer
        : null,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                height: 72,
                child: CoverImage(url: comic.coverUrl(imageHost)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  subtitle,
                ],
              ),
            ),
            if (selected != null) ...[
              const SizedBox(width: 8),
              Checkbox(value: selected, onChanged: onSelect),
            ] else if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    ),
  );
}

class LibrarySelectionBar extends StatelessWidget {
  const LibrarySelectionBar({
    super.key,
    required this.count,
    required this.onDone,
    required this.actions,
    this.visible = true,
  });
  final int count;
  final VoidCallback onDone;
  final List<Widget> actions;
  final bool visible;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppDesign.contentWidth),
        child: Material(
          elevation: 0,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(liveRegion: true, child: AppText('已选 $count')),
                ...actions,
                TextButton(onPressed: onDone, child: const AppText('完成选择')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
