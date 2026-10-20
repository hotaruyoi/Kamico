import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/local_store.dart';
import 'ui/app.dart';
import 'ui/translations.dart';
import 'ui/cover_image_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureImageCaching();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'JMComic-qt (tonquer) / kamico',
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'JMComic-Crawler-Python (hect0x7)',
    ], await rootBundle.loadString('third_party/jmcomic.LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'picacg-qt (tonquer)',
    ], await rootBundle.loadString('third_party/picacg.LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'GNU GPL v3 (LGPL supplemental terms)',
    ], await rootBundle.loadString('third_party/GPL-3.0.txt'));
  });
  try {
    await AppTranslations.load();
    final store = LocalStore(await SharedPreferences.getInstance());
    final session = AppSession(store);
    FlutterError.onError = (details) {
      session.logs.record('ERROR', 'flutter_${details.exception.runtimeType}');
      FlutterError.presentError(details);
    };
    await session.restore();
    runApp(JmApp(session: session));
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('本地存储初始化失败，请重试。'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: main, child: const Text('重试')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
