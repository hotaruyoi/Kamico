import 'package:flutter/services.dart';
import 'dart:convert';

class PlatformFiles {
  static const channel = MethodChannel('app.jmpic/files');
  static Future<String?> publishPdf(
    String path,
    String book,
    String chapter, {
    String? tree,
    String source = 'JM',
  }) async {
    try {
      return await channel.invokeMethod<String>('publishPdf', {
        'path': path,
        'book': book,
        'chapter': chapter,
        'tree': ?tree,
        'source': source,
      });
    } on MissingPluginException {
      return null; // Desktop keeps the PDF alongside its offline cache.
    }
  }

  static Future<List<Map<String, dynamic>>> systemFonts() async {
    try {
      final fonts = await channel.invokeListMethod<Map<Object?, Object?>>(
        'systemFonts',
      );
      return (fonts ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    } on MissingPluginException {
      return [];
    }
  }

  static Future<Uint8List?> fontBytes(String id) =>
      channel.invokeMethod<Uint8List>('fontBytes', {'id': id});
  static Future<void> privacy(bool enabled) async {
    try {
      await channel.invokeMethod<void>('privacy', {'enabled': enabled});
    } on MissingPluginException {
      /* Only Android supports the secure window flag. */
    }
  }

  static Future<void> keepAwake(bool enabled) async {
    try {
      await channel.invokeMethod<void>('keepAwake', {'enabled': enabled});
    } on MissingPluginException {
      /* Android-only; desktop keeps system behavior. */
    }
  }

  static Future<void> readerSystemBars(bool visible) async {
    try {
      await channel.invokeMethod<void>('readerSystemBars', {
        'visible': visible,
      });
    } on MissingPluginException {
      await SystemChrome.setEnabledSystemUIMode(
        visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      );
    }
  }

  static Future<Map<String, dynamic>?> storageInfo() async {
    try {
      return await channel.invokeMapMethod<String, dynamic>('storageInfo');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> openWeb(String url) =>
      channel.invokeMethod<void>('openWeb', {'url': url});
  static Future<String?> pickDirectory() =>
      channel.invokeMethod<String>('pickDirectory');
  static Future<List<Map<String, dynamic>>> importDirectory(String root) async {
    final data = await channel.invokeListMethod<dynamic>('importDirectory', {
      'root': root,
    });
    return (data ?? [])
        .map((e) => jsonDecode(jsonEncode(e)) as Map<String, dynamic>)
        .toList();
  }

  static String mime(Uint8List bytes) {
    if (bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return 'image/jpeg';
    }
    if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      return 'image/png';
    }
    if (bytes.length > 3 && bytes[0] == 0x47 && bytes[1] == 0x49) {
      return 'image/gif';
    }
    if (bytes.length > 12 && String.fromCharCodes(bytes.take(4)) == 'RIFF') {
      return 'image/webp';
    }
    return 'application/octet-stream';
  }

  static Future<bool> image(
    String action,
    Uint8List bytes,
    String name,
  ) async =>
      await channel.invokeMethod<bool>(action, {
        'bytes': bytes,
        'name': name,
        'mime': mime(bytes),
      }) ??
      false;
}
