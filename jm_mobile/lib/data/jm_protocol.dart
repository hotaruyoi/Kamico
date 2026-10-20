import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:pointycastle/export.dart';
import 'api_config.dart';

// Protocol port: JMComic-qt src/server/req.py and src/tools/tool.py.
// See THIRD_PARTY_NOTICES.md for source and license provenance.
class JmProtocol {
  static Map<String, String> headers(
    int timestamp,
    ApiConfig config, {
    String? token,
  }) => {
    'token': md5
        .convert(utf8.encode('$timestamp${config.tokenSecret}'))
        .toString(),
    'tokenparam': '$timestamp,${config.version}',
    'version': 'v1.3.7',
    'user-agent':
        'Mozilla/5.0 (Linux; Android 9) AppleWebKit/537.36 Mobile Safari/537.36',
    if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
  };

  static dynamic decode(String encrypted, int timestamp, String secret) {
    final key = Uint8List.fromList(
      utf8.encode(md5.convert(utf8.encode('$timestamp$secret')).toString()),
    );
    final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
      ..init(
        false,
        PaddedBlockCipherParameters<KeyParameter, Null>(
          KeyParameter(key),
          null,
        ),
      );
    return jsonDecode(utf8.decode(cipher.process(base64Decode(encrypted))));
  }

  static int segmentCount(int chapterId, int scrambleId, String name) {
    if (chapterId < scrambleId) return 0;
    if (chapterId < 268850) return 10;
    // Keep the original Qt implementation's exact threshold (> 421926).
    final digest = md5.convert(utf8.encode('$chapterId$name')).toString();
    return (digest.codeUnitAt(digest.length - 1) %
                (chapterId > 421926 ? 8 : 10)) *
            2 +
        2;
  }
}

// Runs in an isolate; output is PNG to avoid another lossy JPEG encode.
Uint8List restoreImage((Uint8List, int) input) {
  final (bytes, segments) = input;
  if (segments <= 1) return bytes;
  final source = img.decodeImage(bytes);
  if (source == null) throw const FormatException('无法解码图片');
  final target = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  final blockHeight = source.height ~/ segments;
  final remainder = source.height % segments;
  var targetY = 0;
  for (var block = segments - 1; block >= 0; block--) {
    final height = blockHeight + (block == segments - 1 ? remainder : 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < source.width; x++) {
        target.setPixel(
          x,
          targetY + y,
          source.getPixel(x, block * blockHeight + y),
        );
      }
    }
    targetY += height;
  }
  return Uint8List.fromList(img.encodePng(target));
}
