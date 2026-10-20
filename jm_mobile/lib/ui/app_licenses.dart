import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../app_identity.dart';
import '../app_version.dart';
import '../data/app_licenses.dart';
import 'design_system.dart';
import 'translations.dart';

void openAppLicenses(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => const AppLicensesScreen()),
);

class AppLicensesScreen extends StatefulWidget {
  const AppLicensesScreen({super.key});
  @override
  State<AppLicensesScreen> createState() => _AppLicensesScreenState();
}

class _AppLicensesScreenState extends State<AppLicensesScreen> {
  late final _licenses = _load();
  Future<Map<String, List<LicenseEntry>>> _load() async {
    final groups = <String, List<LicenseEntry>>{};
    await for (final entry in relevantLicenses(LicenseRegistry.licenses)) {
      for (final name in entry.packages) {
        (groups[name] ??= []).add(entry);
      }
    }
    final names = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final name in names) name: groups[name]!};
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('开源许可')),
    body: AppPageBody(
      maxWidth: 900,
      child: FutureBuilder(
        future: _licenses,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: AppText('许可读取失败，请重试'));
          }
          final groups = snapshot.data;
          if (groups == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final names = groups.keys.toList();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: names.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: AppText('$appName $appVersion'),
                );
              }
              final name = names[index - 1];
              return ListTile(
                title: Text(name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => _LicenseDetails(name, groups[name]!),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class _LicenseDetails extends StatelessWidget {
  const _LicenseDetails(this.name, this.entries);
  final String name;
  final List<LicenseEntry> entries;
  @override
  Widget build(BuildContext context) {
    final paragraphs = entries.expand((entry) => entry.paragraphs).toList();
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: AppPageBody(
        maxWidth: 900,
        child: ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: paragraphs.length,
          itemBuilder: (_, index) {
            final paragraph = paragraphs[index];
            final centered =
                paragraph.indent == LicenseParagraph.centeredIndent;
            return Padding(
              padding: EdgeInsets.only(
                left: centered ? 0 : paragraph.indent * 16.0,
                bottom: 12,
              ),
              child: SelectableText(
                paragraph.text,
                textAlign: centered ? TextAlign.center : TextAlign.start,
              ),
            );
          },
        ),
      ),
    );
  }
}
