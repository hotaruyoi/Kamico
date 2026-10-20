import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Development-only dependency closure minus runtime closure, from package_graph.json.
const developmentOnlyLicensePackages = {
  'boolean_selector',
  'fake_async',
  'flutter_lints',
  'flutter_test',
  'leak_tracker',
  'leak_tracker_flutter_testing',
  'leak_tracker_testing',
  'lints',
  'matcher',
  'stack_trace',
  'stream_channel',
  'test_api',
  'vm_service',
};

Stream<LicenseEntry> relevantLicenses(Stream<LicenseEntry> entries) async* {
  await for (final entry in entries) {
    final packages = entry.packages
        .where(
          (name) =>
              name != 'jm_mobile' &&
              !developmentOnlyLicensePackages.contains(name),
        )
        .toList();
    if (packages.isNotEmpty) yield _ScopedLicense(entry, packages);
  }
}

class _ScopedLicense extends LicenseEntry {
  _ScopedLicense(this.original, this.packages);
  final LicenseEntry original;
  @override
  final Iterable<String> packages;
  @override
  Iterable<LicenseParagraph> get paragraphs => original.paragraphs;
}

/// A shared LGPL text covers both source adaptations; retain their attribution.
Stream<LicenseEntry> applicationLicenses() async* {
  yield LicenseEntryWithLineBreaks(
    ['kamico'],
    '''
Protocol, image processing and translation portions adapted from:
tonquer / JMComic-qt — https://github.com/tonquer/JMComic-qt
tonquer / picacg-qt — https://github.com/tonquer/picacg-qt
Modified for kamico's Dart implementation and Flutter interface.

${await rootBundle.loadString('LICENSE')}''',
  );
  yield LicenseEntryWithLineBreaks([
    'JMComic-Crawler-Python (hect0x7)',
  ], await rootBundle.loadString('third_party/jmcomic.LICENSE'));
  yield LicenseEntryWithLineBreaks([
    'GNU GPL v3 (LGPL supplemental terms)',
  ], await rootBundle.loadString('third_party/GPL-3.0.txt'));
}
