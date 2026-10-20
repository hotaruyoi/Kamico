import 'motion.dart';
import 'package:flutter/material.dart';
import '../data/platform_files.dart';
import '../data/system_fonts.dart';
import 'app.dart';
import 'translations.dart';

Future<void> showDeviceFonts(BuildContext context, AppSession session) =>
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.sheet(context),
      isScrollControlled: true,
      builder: (_) => _DeviceFonts(session: session),
    );

class _DeviceFonts extends StatefulWidget {
  const _DeviceFonts({required this.session});
  final AppSession session;
  @override
  State<_DeviceFonts> createState() => _DeviceFontsState();
}

class _DeviceFontsState extends State<_DeviceFonts> {
  late Future<List<Map<String, dynamic>>> _fonts;
  String _query = '';
  String? _loading;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _fonts = PlatformFiles.systemFonts();
  }

  Future<void> _choose(String? id, String name) async {
    if (_loading != null) return;
    setState(() {
      _loading = id ?? 'system';
      _error = null;
    });
    try {
      final family = id == null ? 'system' : await SystemFontLibrary.load(id);
      await widget.session.setAppearance('font_name', name);
      await widget.session.setAppearance('font', family);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: .85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: AppText(
                    '设备字体',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: AppTranslations.text(context, '关闭'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchBar(
              hintText: AppTranslations.text(context, '搜索设备字体'),
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          ListTile(
            title: const AppText('跟随系统'),
            leading: const Icon(Icons.settings_suggest_outlined),
            trailing:
                (widget.session.appearance['font'] ?? 'system') == 'system'
                ? const Icon(Icons.check)
                : null,
            onTap: _loading == null ? () => _choose(null, '跟随系统') : null,
          ),
          if (_loading != null) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: AppText('字体读取失败，请重试'),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: AppText('显示系统允许应用读取的字体；部分厂商字体可能不开放'),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _fonts = PlatformFiles.systemFonts()),
                      child: const AppText('读取字体失败，点击重试'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final fonts = snapshot.data!
                    .where(
                      (e) => '${e['name']}'.toLowerCase().contains(
                        _query.toLowerCase(),
                      ),
                    )
                    .toList();
                if (fonts.isEmpty) {
                  return const Center(child: AppText('没有可用字体，请使用跟随系统'));
                }
                return ListView.builder(
                  itemCount: fonts.length,
                  itemBuilder: (context, i) {
                    final font = fonts[i];
                    final family = 'device:${font['id']}';
                    return ListTile(
                      title: Text('${font['name']}'),
                      trailing: widget.session.appearance['font'] == family
                          ? const Icon(Icons.check)
                          : null,
                      onTap: _loading == null
                          ? () => _choose('${font['id']}', '${font['name']}')
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
