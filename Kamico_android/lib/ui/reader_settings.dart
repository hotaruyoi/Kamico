import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../domain/reader_options.dart';
import 'app.dart';
import 'design_system.dart';
import 'filled_select.dart';
import 'motion.dart';
import 'translations.dart';

class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.session,
    required this.mode,
    required this.onMode,
    required this.onEnvironment,
  });
  final AppSession session;
  final ReaderMode mode;
  final ValueChanged<ReaderMode> onMode;
  final Future<void> Function() onEnvironment;
  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  late ReaderMode _mode = widget.mode;
  late bool _awake = prefs.getBool('reader_awake') ?? false;
  late String _orientation = prefs.getString('reader_orientation') ?? 'system';
  late double _seconds = (prefs.getInt('reader_seconds') ?? 5)
      .clamp(2, 20)
      .toDouble();
  late double _prefetch = (prefs.getInt('reader_prefetch') ?? 2)
      .clamp(0, 3)
      .toDouble();
  SharedPreferences get prefs => widget.session.store.preferences;
  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    ValueChanged<double> onEnd,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppText(label, style: Theme.of(context).textTheme.titleSmall),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: (max - min).round(),
        label: value.round().toString(),
        onChanged: onChanged,
        onChangeEnd: onEnd,
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: AppText(
                  '阅读设置',
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
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const AppText('阅读时保持屏幕常亮'),
                  value: _awake,
                  onChanged: (v) async {
                    setState(() => _awake = v);
                    await prefs.setBool('reader_awake', v);
                    await widget.onEnvironment();
                  },
                ),
                const SizedBox(height: 12),
                FilledSelect(
                  key: const ValueKey('reader-orientation'),
                  label: '屏幕方向',
                  value: _orientation,
                  minimumHeight: 88,
                  leading: Icons.screen_rotation_outlined,
                  valueStyle: Theme.of(context).textTheme.titleMedium,
                  choices: const {
                    'system': '跟随系统',
                    'portrait': '竖屏',
                    'landscape': '横屏',
                  },
                  onChanged: (v) async {
                    setState(() => _orientation = v);
                    await prefs.setString('reader_orientation', v);
                    await widget.onEnvironment();
                  },
                ),
                const SectionTitle('阅读模式'),
                for (final mode in ReaderMode.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AnimatedContainer(
                      duration: AppMotion.duration(context, AppMotion.state),
                      curve: AppMotion.curve,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: _mode == mode
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          minTileHeight: 88,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          title: AppText(mode.label),
                          subtitle: AppText(mode.hint),
                          leading: Icon(mode.icon),
                          trailing: Icon(
                            _mode == mode
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                          ),
                          selected: _mode == mode,
                          selectedTileColor: Colors.transparent,
                          onTap: () async {
                            if (_mode == mode) return;
                            setState(() => _mode = mode);
                            widget.onMode(mode);
                            await prefs.setString('reader_layout', mode.name);
                          },
                        ),
                      ),
                    ),
                  ),
                const SectionTitle('自动阅读与预加载'),
                AppPanel(
                  child: Column(
                    children: [
                      _slider(
                        '自动翻页/滚动间隔：${_seconds.round()} 秒',
                        _seconds,
                        2,
                        20,
                        (v) => setState(() => _seconds = v),
                        (v) => prefs.setInt('reader_seconds', v.round()),
                      ),
                      const SizedBox(height: 12),
                      _slider(
                        '预加载前后 ${_prefetch.round()} 页',
                        _prefetch,
                        0,
                        3,
                        (v) => setState(() => _prefetch = v),
                        (v) => prefs.setInt('reader_prefetch', v.round()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
