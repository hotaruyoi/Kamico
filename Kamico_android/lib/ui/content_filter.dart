import 'translations.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'dialogs.dart';
import 'design_system.dart';

class ContentFilterScreen extends StatefulWidget {
  const ContentFilterScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<ContentFilterScreen> createState() => _ContentFilterScreenState();
}

class _ContentFilterScreenState extends State<ContentFilterScreen> {
  @override
  Widget build(BuildContext context) {
    final store = widget.session.store;
    return Scaffold(
      appBar: AppBar(
        title: const AppText('标题和标签屏蔽'),
        actions: [
          IconButton(
            tooltip: AppTranslations.text(context, '添加屏蔽词'),
            onPressed: () async {
              final word = await prompt(context, '添加屏蔽词');
              if (word != null) {
                await store.preferences.setStringList(
                  'blocked_words',
                  {...store.blockedWords, word}.toList(),
                );
                if (mounted) setState(() {});
              }
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: AppPageBody(
        maxWidth: 800,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const AppText('匹配标题'),
                    value: store.preferences.getBool('block_title') ?? true,
                    onChanged: (v) async {
                      await store.preferences.setBool('block_title', v);
                      if (mounted) setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const AppText('匹配标签'),
                    subtitle: const AppText('仅对列表接口实际提供的标签生效'),
                    value: store.preferences.getBool('block_tags') ?? true,
                    onChanged: (v) async {
                      await store.preferences.setBool('block_tags', v);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
            const SectionTitle('屏蔽词'),
            if (store.blockedWords.isEmpty)
              const AppStatus(icon: Icons.filter_alt_outlined, title: '暂无屏蔽词'),
            for (final word in store.blockedWords)
              ListTile(
                title: Text(word),
                trailing: IconButton(
                  tooltip: AppTranslations.text(context, '删除'),
                  onPressed: () async {
                    await store.preferences.setStringList(
                      'blocked_words',
                      store.blockedWords.where((e) => e != word).toList(),
                    );
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
