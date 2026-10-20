import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../domain/discovery_shortcut.dart';
import 'app.dart';
import 'design_system.dart';
import 'translations.dart';

class DiscoveryShortcutOrderScreen extends StatefulWidget {
  const DiscoveryShortcutOrderScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<DiscoveryShortcutOrderScreen> createState() =>
      _DiscoveryShortcutOrderScreenState();
}

class _DiscoveryShortcutOrderScreenState
    extends State<DiscoveryShortcutOrderScreen> {
  late List<DiscoveryShortcut> _order = discoveryShortcutOrder(
    widget.session.appearance['discovery_shortcut_order'],
  );
  Future<void> _saves = Future.value();

  void _save() {
    final ids = _order.map((item) => item.name).toList();
    _saves = _saves
        .then(
          (_) => widget.session.setAppearance('discovery_shortcut_order', ids),
        )
        .catchError((Object error) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: AppText('保存排序失败，请重试')));
          }
        });
  }

  void _move(int from, int to) {
    if (from == to) return;
    setState(() => _order.insert(to, _order.removeAt(from)));
    _save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AppText('发现页入口排序'),
      actions: [
        TextButton(
          onPressed: () {
            setState(() => _order = List.of(DiscoveryShortcut.values));
            _save();
          },
          child: const AppText('恢复默认'),
        ),
      ],
    ),
    body: AppPageBody(
      maxWidth: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText('拖动右侧手柄调整顺序，修改后自动保存'),
                SizedBox(height: 8),
                AppText('上方项目显示在发现页左侧；连载、周刊仅在 JM 显示'),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorderItem: _move,
              proxyDecorator: (child, index, animation) => ScaleTransition(
                scale: animation.drive(Tween(begin: 1, end: 1.02)),
                child: Material(
                  elevation: 6,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              ),
              itemBuilder: (context, index) {
                final item = _order[index];
                return Padding(
                  key: ValueKey(item.name),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                    customSemanticsActions: {
                      if (index > 0)
                        CustomSemanticsAction(
                          label: AppTranslations.text(context, '上移'),
                        ): () =>
                            _move(index, index - 1),
                      if (index < _order.length - 1)
                        CustomSemanticsAction(
                          label: AppTranslations.text(context, '下移'),
                        ): () =>
                            _move(index, index + 1),
                    },
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        minTileHeight: 72,
                        leading: Icon(item.icon),
                        title: AppText(item.label),
                        subtitle: item.jmOnly ? const AppText('仅 JM') : null,
                        trailing: ReorderableDragStartListener(
                          key: ValueKey('drag-${item.name}'),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Semantics(
                              label: AppTranslations.text(context, '拖动排序'),
                              child: const Icon(Icons.drag_handle),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
