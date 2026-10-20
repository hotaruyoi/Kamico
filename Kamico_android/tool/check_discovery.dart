import 'dart:io';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/jm_client.dart';

Future<void> main() async {
  final api = JmClient(config: const ApiConfig());
  try {
    final groups = await api.homeSections();
    stdout.writeln(
      'promote: sections=${groups.length}, items=${groups.fold<int>(0, (s, g) => s + g.items.length)}',
    );
    final catalog = await api.categories();
    stdout.writeln('categories: ${catalog.categories.length}');
    stdout.writeln('latest: ${(await api.latest(1)).items.length}');
    stdout.writeln(
      'rank: ${(await api.category('0', 1, sort: 'mv_w')).items.length}',
    );
    stdout.writeln(
      'serialization: ${(await api.serialization(DateTime.now().weekday, 'all', 1)).items.length}',
    );
    final issues = await api.weekIssues();
    stdout.writeln('week: issues=${issues.length}');
    if (issues.isNotEmpty) {
      stdout.writeln(
        'week/filter: ${(await api.week('${issues.first['id']}', 'manga', 1)).items.length}',
      );
    }
  } catch (e) {
    stderr.writeln('Read-only discovery check failed: $e');
    exitCode = 1;
  } finally {
    api.close();
  }
}
