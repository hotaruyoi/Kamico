import 'dart:io';
import 'package:jm_mobile/data/api_config.dart';
import 'package:jm_mobile/data/jm_client.dart';
import 'package:jm_mobile/domain/models.dart';

/// Read-only smoke check: prints response shape, never category titles or tokens.
Future<void> main() async {
  const defaults = ApiConfig();
  for (final host in defaults.apiHosts.take(2)) {
    final api = JmClient(config: ApiConfig(apiHosts: [host]));
    try {
      final data =
          await api.request('/categories', query: {'lang': 'CN'}) as Json;
      stdout.writeln(
        '$host: decrypted, categories=${(data['categories'] as List).length}',
      );
    } catch (error) {
      stderr.writeln('$host: $error');
      exitCode = 1;
    } finally {
      api.close();
    }
  }
}
