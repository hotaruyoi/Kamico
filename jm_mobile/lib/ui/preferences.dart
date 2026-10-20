import 'filled_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_version.dart';
import '../app_identity.dart';
import '../domain/models.dart';
import 'app.dart';
import 'dialogs.dart';
import 'translations.dart';
import 'design_system.dart';
import 'card_density.dart';
import '../domain/card_layout.dart';
import 'font_picker.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.session});
  final AppSession session;
  Widget select(
    BuildContext context,
    String key,
    String title,
    Map<String, String> options,
    String fallback,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: FilledSelect(
      label: title,
      value: '${session.appearance[key] ?? fallback}',
      choices: options,
      onChanged: (v) => session.setAppearance(key, v),
    ),
  );

  Widget slider(
    String key,
    String title,
    double fallback,
    double min,
    double max,
    int divisions,
  ) {
    final value = ((session.appearance[key] as num?)?.toDouble() ?? fallback)
        .clamp(min, max);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText('$title · ${value.toStringAsFixed(1)}'),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) => session.setAppearance(key, v),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('外观与语言')),
    body: AppPageBody(
      maxWidth: 720,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            const SectionTitle('主题与语言', icon: Icons.palette_outlined),
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  select(context, 'theme', '主题', {
                    'system': '跟随系统',
                    'light': '浅色',
                    'dark': '深色',
                  }, 'system'),
                  select(context, 'language', '界面语言', {
                    'zh_CN': '简体中文',
                    'zh_TW': '繁體中文',
                    'en': 'English',
                    'auto': '跟随系统',
                  }, 'zh_CN'),
                  const SizedBox(height: 16),
                  const AppText('主题色'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children:
                        [
                              0xff296b5c,
                              0xff476cbb,
                              0xff9a508a,
                              0xff9c6229,
                              0xff546e7a,
                            ]
                            .map(
                              (color) => Semantics(
                                selected:
                                    integer(
                                      session.appearance['color'] ?? 0xff296b5c,
                                    ) ==
                                    color,
                                child: IconButton(
                                  tooltip: AppTranslations.text(
                                    context,
                                    {
                                      0xff296b5c: '主题色：青绿',
                                      0xff476cbb: '主题色：蓝色',
                                      0xff9a508a: '主题色：紫色',
                                      0xff9c6229: '主题色：棕色',
                                      0xff546e7a: '主题色：蓝灰',
                                    }[color]!,
                                  ),
                                  onPressed: () =>
                                      session.setAppearance('color', color),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Color(color),
                                  ),
                                  icon: Icon(
                                    integer(
                                              session.appearance['color'] ??
                                                  0xff296b5c,
                                            ) ==
                                            color
                                        ? Icons.check
                                        : Icons.circle_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
            const SectionTitle('字体与排版', icon: Icons.text_fields),
            AppPanel(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const AppText('字体'),
                    subtitle: AppText(
                      (session.appearance['font'] ?? 'system') == 'system'
                          ? '跟随系统'
                          : '${session.appearance['font_name'] ?? session.appearance['font']}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDeviceFonts(context, session),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const AppText('粗体'),
                    value: session.appearance['bold'] == true,
                    onChanged: (v) => session.setAppearance('bold', v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const AppText('斜体'),
                    value: session.appearance['italic'] == true,
                    onChanged: (v) => session.setAppearance('italic', v),
                  ),
                  slider('scale', '字体缩放', 1, .8, 1.4, 6),
                ],
              ),
            ),
            const SectionTitle('阅读列表', icon: Icons.grid_view_outlined),
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const AppText('卡片大小'),
                    subtitle: AppText(
                      cardDensityLabel(
                        ComicCardLayout.fromPreferences(
                          session.appearance,
                        ).density,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showCardDensity(context, session),
                  ),
                  const SizedBox(height: 8),
                  const AppText('标题行数'),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: [
                      for (final line in [1, 2, 3, 4])
                        ButtonSegment(value: line, label: Text('$line')),
                    ],
                    selected: {integer(session.appearance['lines'] ?? 2)},
                    onSelectionChanged: (v) =>
                        session.setAppearance('lines', v.single),
                  ),
                ],
              ),
            ),
            const SectionTitle('预览：字体与标题样式'),
            AppPanel(
              tonal: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    'kamico',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text('JM 0123456789'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  String _query = '', _category = '全部';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('版本信息与日志')),
    body: AppPageBody(
      maxWidth: 800,
      child: ListenableBuilder(
        listenable: widget.session.logs,
        builder: (context, _) {
          final logs = widget.session.logs;
          final items = logs.entries
              .where(
                (e) =>
                    (_category == '全部' || e['category'] == _category) &&
                    logs
                        .export([e])
                        .toLowerCase()
                        .contains(_query.toLowerCase()),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AppPanel(
                tonal: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 40),
                    const SizedBox(height: 16),
                    AppText(
                      '$appName $appVersion',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const AppText('Flutter 独立客户端 · Android 优先'),
                    const SizedBox(height: 8),
                    const AppText('更新检查将在配置正式发布源后接入。'),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: appName,
                  applicationVersion: appVersion,
                ),
                child: const AppText('开源许可'),
              ),
              const Divider(),
              const AppText('日志最多保留 300 条，仅记录请求路径、状态、耗时及事件代码。'),
              SearchBar(
                onChanged: (v) => setState(() => _query = v),
                hintText: AppTranslations.text(context, '搜索日志'),
                leading: const Icon(Icons.search),
              ),
              Wrap(
                runSpacing: 8,
                spacing: 8,
                children: ['全部', 'APP', 'API', 'ACCOUNT', 'DOWNLOAD', 'ERROR']
                    .map(
                      (e) => ChoiceChip(
                        label: AppText(e),
                        selected: _category == e,
                        onSelected: (_) => setState(() => _category = e),
                      ),
                    )
                    .toList(),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: logs.export(items)),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: AppText(
                              AppTranslations.text(context, '日志已复制'),
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const AppText('复制日志'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (await confirm(context, '清空本地日志？')) await logs.clear();
                    },
                    child: const AppText('清空日志'),
                  ),
                ],
              ),
              if (logs.persistenceError != null)
                AppText(logs.persistenceError!),
              if (items.isEmpty) const AppText('暂无日志'),
              ...items.reversed.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppPanel(
                    child: SelectableText(
                      logs.export([Map<String, dynamic>.from(e)]),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
