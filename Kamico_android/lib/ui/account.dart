import 'translations.dart';

import 'package:flutter/material.dart';

import '../domain/models.dart';

import 'app.dart';
import 'dialogs.dart';
import 'design_system.dart';
import 'settings.dart';
import 'account_calendar.dart';
import 'comments_body.dart';
import 'failure.dart';

void notice(BuildContext context, Object message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppText(
          message is Exception ? failureMessage(message) : '$message',
        ),
      ),
    );

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.session});
  final AppSession session;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Future<Json>? _daily;
  bool _busy = false;
  String get uid => '${widget.session.api.userProfile?['uid'] ?? ''}';
  @override
  void initState() {
    super.initState();
    if (uid.isNotEmpty) _reload();
  }

  void _reload() {
    _daily = widget.session.api.daily(uid).then((data) async {
      if (widget.session.isPic && widget.session.loggedIn) {
        await widget.session.cacheProfile();
        if (mounted) setState(() {});
      }
      return data;
    });
  }

  Future<void> _sign(Json data, {String date = ''}) async {
    if (data['daily_id'] == null) {
      notice(context, '签到记录缺少编号，请刷新重试');
      return;
    }
    if (date.isNotEmpty && !await confirm(context, '确认补签 $date？补签次数由上游限制。')) {
      return;
    }
    setState(() => _busy = true);
    try {
      final message = await widget.session.api.sign(
        uid,
        '${data['daily_id']}',
        date: date,
      );
      await widget.session.markProfilePending();
      if (mounted) {
        notice(context, message);
        setState(_reload);
      }
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.session.api.userProfile ?? {};
    return Scaffold(
      appBar: AppBar(title: const AppText('账号资料与签到')),
      body: AppPageBody(
        maxWidth: 800,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppPanel(
              tonal: true,
              child: Row(
                children: [
                  if (widget.session.avatarUrl.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ClipOval(
                        child: Image.network(
                          widget.session.avatarUrl,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.account_circle, size: 72),
                        ),
                      ),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '${profile['username'] ?? '当前账号'}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in {
                  'level_name': '等级',
                  'coin': '金币',
                  'exp': '经验',
                }.entries)
                  if (profile.containsKey(entry.key))
                    Chip(
                      label: AppText('${entry.value}：${profile[entry.key]}'),
                    ),
              ],
            ),
            AppText(
              '资料更新时间：${widget.session.store.preferences.getString(widget.session.prefKey('profile_updated'))?.replaceFirst('T', ' ').split('.').first ?? '未记录'}',
            ),
            if (widget.session.store.preferences.getBool(
                  widget.session.prefKey('profile_pending'),
                ) ??
                false)
              const AppText('购买或签到后的余额、经验等待重新登录确认'),
            ExpansionTile(
              title: const AppText('更多账号资料'),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in {
                      'uid': '用户编号',
                      'level': '等级',
                      'gender': '性别',
                      'nextLevelExp': '下一级经验',
                      'album_favorites': '已收藏',
                      'album_favorites_max': '收藏上限',
                    }.entries)
                      if (profile.containsKey(entry.key))
                        Chip(
                          label: AppText(
                            '${entry.value}：${profile[entry.key]}',
                          ),
                        ),
                  ],
                ),
                if (!widget.session.isPic)
                  const AppText('资料来自最近一次登录；当前接口不提供独立资料刷新。'),
                TextButton(
                  onPressed: () async {
                    if (widget.session.isPic) {
                      setState(_reload);
                      return;
                    }
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => LoginScreen(session: widget.session),
                      ),
                    );
                    if (mounted) setState(_reload);
                  },
                  child: AppText(widget.session.isPic ? '刷新资料' : '重新登录刷新资料'),
                ),
              ],
            ),
            SwitchListTile(
              title: const AppText('启动后自动签到'),
              value:
                  widget.session.store.preferences.getBool(
                    widget.session.prefKey('auto_sign'),
                  ) ??
                  false,
              onChanged: (v) async {
                await widget.session.store.preferences.setBool(
                  widget.session.prefKey('auto_sign'),
                  v,
                );
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              title: const AppText('我的评论'),
              leading: const Icon(Icons.comment_outlined),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CommentsScreen(session: widget.session, uid: uid),
                ),
              ),
            ),
            const SectionTitle('每日签到', icon: Icons.event_available_outlined),
            if (_daily != null)
              FutureBuilder<Json>(
                future: _daily,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppFailure(
                      error: snapshot.error!,
                      retry: () => setState(_reload),
                      session: widget.session,
                    );
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final records = <Json>[];
                  void collect(dynamic value) {
                    if (value is List) {
                      for (final item in value) {
                        collect(item);
                      }
                    } else if (value is Map && value.containsKey('date')) {
                      records.add(Map<String, dynamic>.from(value));
                    }
                  }

                  collect(data['record']);
                  final now = DateTime.now();
                  final checked = records.any(
                    (r) =>
                        integer(r['date']) == now.day &&
                        (r['signed'] == true || '${r['signed']}' == '1'),
                  );
                  return AppPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText('签到日历 · ${now.year}-${now.month}'),
                        if (!widget.session.isPic)
                          AppText(
                            '补签额度：${data['makeup_used'] ?? 0} / ${data['makeup_limit'] ?? 0}',
                          ),
                        FilledButton(
                          onPressed: _busy || checked
                              ? null
                              : () => _sign(data),
                          child: AppText(checked ? '今日已签到' : '今日签到'),
                        ),
                        if (!widget.session.isPic)
                          AccountCalendar(
                            records: records,
                            busy: _busy,
                            available:
                                integer(data['makeup_limit']) -
                                integer(data['makeup_used']),
                            onMakeup: (date) => _sign(data, date: date),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class CommentsScreen extends StatelessWidget {
  const CommentsScreen({
    super.key,
    required this.session,
    this.id = '',
    this.uid,
  });
  final AppSession session;
  final String id;
  final String? uid;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: AppText(uid == null ? '评论' : '我的评论')),
    body: AppPageBody(
      maxWidth: 800,
      child: CommentsBody(session: session, id: id, uid: uid),
    ),
  );
}
