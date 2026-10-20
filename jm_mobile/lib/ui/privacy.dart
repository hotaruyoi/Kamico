import 'package:flutter/material.dart';
import '../data/platform_files.dart';
import '../domain/content_source.dart';
import 'app.dart';
import 'dialogs.dart';
import 'account.dart' show notice;
import 'design_system.dart';
import 'translations.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  Future<void> _change(String key, bool value) async {
    try {
      if (key == 'privacy_window') await PlatformFiles.privacy(value);
      await widget.session.savedProgress;
      await widget.session.store.preferences.setBool(key, value);
      await widget.session.setAppearance(
        'privacy_revision',
        DateTime.now().millisecondsSinceEpoch,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) notice(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('隐私与历史')),
    body: AppPageBody(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const AppText('隐藏最近任务预览并阻止截图'),
            subtitle: const AppText('仅 Android；系统可能限制投屏和截图'),
            value:
                widget.session.store.preferences.getBool('privacy_window') ??
                false,
            onChanged: (v) => _change('privacy_window', v),
          ),
          SwitchListTile(
            title: const AppText('不记录新的阅读进度'),
            subtitle: const AppText('开启后无法继续本次阅读；不会删除已有历史'),
            value:
                widget.session.store.preferences.getBool(
                  'privacy_no_history',
                ) ??
                false,
            onChanged: (v) => _change('privacy_no_history', v),
          ),
          SwitchListTile(
            title: const AppText('隐藏首页最近阅读'),
            value:
                widget.session.store.preferences.getBool(
                  'privacy_hide_recent',
                ) ??
                false,
            onChanged: (v) => _change('privacy_hide_recent', v),
          ),
          const Divider(),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.delete_outline),
            label: const AppText('清空设备内阅读与搜索历史'),
            onPressed: () async {
              if (!await confirm(
                context,
                '清空全部设备内阅读进度和搜索记录？不会影响云端记录、收藏或下载文件。',
                title: '清空历史',
                action: '清空',
              )) {
                return;
              }
              await widget.session.savedProgress;
              await widget.session.store.preferences.remove('history');
              await widget.session.store.preferences.remove('chapter_progress');
              for (final source in ContentSource.values) {
                final store = widget.session.forSource(source).store;
                await store.clearSearchHistory();
                await store.writeMap('search_options', {
                  ...store.readMap('search_options'),
                  'query': '',
                });
              }
              await widget.session.setAppearance(
                'privacy_revision',
                DateTime.now().millisecondsSinceEpoch,
              );
              if (context.mounted) notice(context, '设备内历史已清空');
            },
          ),
        ],
      ),
    ),
  );
}
