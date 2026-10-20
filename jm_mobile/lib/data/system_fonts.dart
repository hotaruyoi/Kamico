import 'package:flutter/services.dart';
import 'platform_files.dart';

class SystemFontLibrary {
  static final _loaded = <String>{};
  static bool loaded(String family) => _loaded.contains(family);
  static Future<String> load(String id) async {
    final family = 'device:$id';
    if (_loaded.contains(family)) return family;
    final bytes = await PlatformFiles.fontBytes(id);
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('字体读取失败，请重试');
    }
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(family);
    return family;
  }
}
