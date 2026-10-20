import 'motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/api_config.dart';
import '../data/platform_files.dart';
import '../data/site_links.dart';
import '../app_version.dart';
import '../app_identity.dart';
import 'translations.dart';
import 'app.dart';
import 'account.dart';
import 'content_filter.dart';
import 'preferences.dart';
import 'design_system.dart';
import 'dialogs.dart';
import 'privacy.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.session});
  final AppSession session;
  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  Widget _accountHeader(BuildContext context) {
    final profile = session.api.userProfile ?? {};
    final uid = '${profile['uid'] ?? ''}';
    final username = '${profile['username'] ?? ''}'.trim();
    final identity = username.isNotEmpty
        ? username
        : uid.isNotEmpty
        ? uid
        : AppTranslations.text(context, '当前账号');
    Widget shortcut(String label, IconData icon, VoidCallback action) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: action,
              child: SizedBox(
                height: 36 + MediaQuery.textScalerOf(context).scale(14) * 2.8,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon),
                    const SizedBox(height: 8),
                    AppText(label, maxLines: 2, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        );
    return AppPanel(
      tonal: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: session.loggedIn && session.avatarUrl.isNotEmpty
                      ? Image.network(
                          session.avatarUrl,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (64 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.account_circle_outlined,
                            size: 64,
                          ),
                        )
                      : const Icon(Icons.account_circle_outlined, size: 64),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: session.loggedIn
                    ? Semantics(
                        label: identity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            identity,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                      )
                    : AppText(
                        '未登录',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppText(
            session.loggedIn
                ? '账号资料、签到与我的评论'
                : session.isPic
                ? '登录后同步收藏'
                : '登录后同步收藏和观看历史',
          ),
          const SizedBox(height: 16),
          if (session.loggedIn)
            Row(
              key: const ValueKey('account-shortcuts'),
              children: [
                shortcut(
                  '签到',
                  Icons.event_available_outlined,
                  () => _open(context, AccountScreen(session: session)),
                ),
                shortcut(
                  '我的评论',
                  Icons.comment_outlined,
                  () => _open(
                    context,
                    CommentsScreen(session: session, uid: uid),
                  ),
                ),
                shortcut(
                  '账号',
                  Icons.person_outline,
                  () => _open(context, AccountScreen(session: session)),
                ),
                shortcut('退出', Icons.logout, () async {
                  if (!await confirm(context, '退出当前账号？')) return;
                  try {
                    await session.logout();
                  } catch (error) {
                    if (context.mounted) notice(context, error);
                  }
                }),
              ],
            )
          else
            FilledButton.tonalIcon(
              onPressed: () => _open(context, LoginScreen(session: session)),
              icon: const Icon(Icons.login),
              label: const AppText('登录'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _accountHeader(context),
        const SectionTitle('偏好设置', icon: Icons.tune),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const AppText('外观与语言'),
                subtitle: const AppText('主题、字体与阅读列表'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, AppearanceScreen(session: session)),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.filter_alt_outlined),
                title: const AppText('标题和标签屏蔽'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    _open(context, ContentFilterScreen(session: session)),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const AppText('隐私与历史'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, PrivacyScreen(session: session)),
              ),
            ],
          ),
        ),
        const SectionTitle('存储与连接', icon: Icons.storage_outlined),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const AppText('清除阅读图片缓存'),
                subtitle: const AppText('不会清除阅读历史'),
                onTap: () async {
                  if (!await confirm(context, '清除阅读图片缓存？')) return;
                  try {
                    await session.images.clearCache();
                    if (context.mounted) notice(context, '图片缓存已清除');
                  } catch (e) {
                    if (context.mounted) notice(context, e);
                  }
                },
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const AppText('连接设置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    _open(context, ConnectionSettingsScreen(session: session)),
              ),
            ],
          ),
        ),
        const SectionTitle('关于应用', icon: Icons.info_outline),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const AppText('版本信息与日志'),
                subtitle: const AppText('$appName $appVersion'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    _open(context, MaintenanceScreen(session: session)),
              ),
              const Divider(height: 1, indent: 56, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.code),
                title: const AppText('开源许可'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: appName,
                  applicationVersion: appVersion,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ConnectionSettingsScreen extends StatefulWidget {
  const ConnectionSettingsScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<ConnectionSettingsScreen> createState() =>
      _ConnectionSettingsScreenState();
}

class _ConnectionSettingsScreenState extends State<ConnectionSettingsScreen> {
  late final TextEditingController _hosts, _images, _version, _token, _data;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final config = widget.session.api.config;
    _hosts = TextEditingController(text: config.apiHosts.join('\n'));
    _images = TextEditingController(text: config.imageHost);
    _version = TextEditingController(text: config.version);
    _token = TextEditingController(text: config.tokenSecret);
    _data = TextEditingController(text: config.dataSecret);
  }

  @override
  void dispose() {
    for (final c in [_hosts, _images, _version, _token, _data]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.session.configure(
        ApiConfig(
          apiHosts: _hosts.text
              .split(RegExp(r'\s+'))
              .where((s) => s.isNotEmpty)
              .toList(),
          imageHost: _images.text.trim(),
          version: _version.text.trim(),
          tokenSecret: _token.text.trim(),
          dataSecret: _data.text.trim(),
        ),
      );
      if (mounted) notice(context, '连接设置已保存');
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('连接设置')),
    body: AppPageBody(
      maxWidth: 720,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppPanel(
            tonal: true,
            child: AppText('默认线路来自原项目源码，可能随上游调整。保存配置会退出当前账号。'),
          ),
          const SectionTitle('API 与图片'),
          TextField(
            controller: _hosts,
            enabled: !_busy,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: AppTranslations.text(context, 'API 线路（每行一个 HTTPS 域名）'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _images,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: AppTranslations.text(context, '图片线路'),
            ),
          ),
          const SizedBox(height: 24),
          AppPanel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              title: const AppText('高级协议参数'),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                for (final entry in [
                  (_version, '上游版本'),
                  (_token, '请求签名参数'),
                  (_data, widget.session.isPic ? 'HMAC 签名密钥' : '响应解密参数'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: entry.$1,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: AppTranslations.text(context, entry.$2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const AppText('保存配置'),
          ),
        ],
      ),
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController(),
      _password = TextEditingController();
  bool _busy = false, _hidden = true;
  String? _error;
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(_username.text.trim(), _password.text);
      if (mounted) {
        TextInput.finishAutofillContext();
        _password.clear();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    try {
      await PlatformFiles.openWeb(officialRegistrationUrl);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        animationStyle: AppMotion.sheet(context),
        builder: (context) => AlertDialog(
          title: const AppText('无法打开浏览器'),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText('请复制链接到浏览器完成注册，然后返回此页登录。'),
                SelectableText(officialRegistrationUrl),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: officialRegistrationUrl),
                );
                if (context.mounted) notice(context, '链接已复制');
              },
              child: const AppText('复制链接'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const AppText('返回登录'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const AppText('登录')),
      body: AppPageBody(
        maxWidth: 520,
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    Icons.menu_book_outlined,
                    size: 40,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              AppText(
                widget.session.isPic ? '登录 Pic' : '登录 kamico',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              AppText(
                widget.session.isPic ? '使用 Pic 账号邮箱登录后浏览和同步收藏' : '登录后同步收藏和观看历史',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _username,
                enabled: !_busy,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: AppTranslations.text(
                    context,
                    widget.session.isPic ? '邮箱' : '账号',
                  ),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _hidden,
                autofillHints: const [AutofillHints.password],
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_busy) _login();
                },
                decoration: InputDecoration(
                  labelText: AppTranslations.text(context, '密码'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: AppTranslations.text(
                      context,
                      _hidden ? '显示密码' : '隐藏密码',
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: AppPanel(
                    child: AppText(
                      _error!,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_busy) ...[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    AppText(_busy ? '登录中…' : '登录'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!widget.session.isPic) ...[
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _register,
                  icon: const Icon(Icons.open_in_new),
                  label: const AppText('注册账号'),
                ),
                const SizedBox(height: 12),
                AppText(
                  '在原网站完成注册后，返回此页登录',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Uri.parse(officialWebsite).host,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
