import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'translations.dart';

class AccountCalendar extends StatelessWidget {
  const AccountCalendar({
    super.key,
    required this.records,
    required this.available,
    required this.busy,
    required this.onMakeup,
  });
  final List<Json> records;
  final int available;
  final bool busy;
  final ValueChanged<String> onMakeup;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now(), colors = Theme.of(context).colorScheme;
    final leading = DateTime(now.year, now.month).weekday - 1;
    final days = DateTime(now.year, now.month + 1, 0).day;
    return Column(
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            for (final weekday in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(child: Center(child: AppText(weekday))),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leading + days,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            final day = index - leading + 1;
            if (day <= 0) return const SizedBox.shrink();
            final record = records
                .where((r) => integer(r['date']) == day)
                .firstOrNull;
            final signed =
                record?['signed'] == true || '${record?['signed']}' == '1';
            final enabled =
                !busy &&
                record != null &&
                !signed &&
                day < now.day &&
                available > 0;
            final today = day == now.day;
            return Semantics(
              label:
                  '$day 日 · ${signed
                      ? '已签到'
                      : enabled
                      ? '可补签'
                      : today
                      ? '今天'
                      : '不可补签'}',
              selected: today,
              child: Material(
                color: signed
                    ? colors.primaryContainer
                    : today
                    ? colors.secondaryContainer
                    : colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: enabled
                      ? () => onMakeup(
                          '${now.year}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
                        )
                      : null,
                  child: Stack(
                    children: [
                      Center(child: Text('$day')),
                      if (signed)
                        const Positioned(
                          top: 2,
                          right: 2,
                          child: Icon(Icons.check, size: 12),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Icon(Icons.check, size: 16),
            SizedBox(width: 4),
            Expanded(child: AppText('已签到 · 边框为今天 · 点击可用的过去日期补签')),
          ],
        ),
      ],
    );
  }
}
