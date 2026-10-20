import 'dart:io';
import 'package:jm_mobile/data/pic_client.dart';

// No account, login attempt, user content write or credentials are involved.
Future<void> main() async {
  final client = PicClient();
  client.onRequest = (path, method, status, ms) =>
      stdout.writeln('$method $path HTTP=$status elapsed=${ms}ms');
  try {
    final data = await client.request('categories', authenticated: false);
    stdout.writeln(
      'guest categories returned: ${data.containsKey('categories')}',
    );
  } catch (error) {
    stdout.writeln('guest probe: $error');
  } finally {
    client.close();
  }
}
