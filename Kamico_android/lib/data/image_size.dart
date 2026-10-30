import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Image dimensions read from the file header, without decoding pixels.
///
/// Manga pages arrive as JPEG, PNG, WebP or GIF. Knowing the height before the
/// bitmap is decoded lets the continuous reader reserve the final extent, so a
/// page that decodes above the viewport cannot push the content under the
/// reader's finger.
double? imageAspectFromBytes(Uint8List bytes) {
  final size = imageSizeFromBytes(bytes);
  if (size == null || size.width <= 0 || size.height <= 0) return null;
  return size.height / size.width;
}

/// Placeholder ratio for pages whose extent is not known yet. It is close to a
/// typical manga page and only used before the page's bytes arrive.
const defaultPageAspect = 1.45;

double clampPageAspect(double aspect) => aspect.clamp(0.4, 4.0).toDouble();

({int width, int height})? imageSizeFromBytes(Uint8List bytes) {
  if (bytes.length < 16) return null;
  final png = _pngSize(bytes);
  if (png != null) return png;
  final gif = _gifSize(bytes);
  if (gif != null) return gif;
  final webp = _webpSize(bytes);
  if (webp != null) return webp;
  return _jpegSize(bytes);
}

/// Reads only the header window of each file, so a whole chapter can be
/// measured without loading page bitmaps.
List<double?> measurePageAspects(List<String> paths) => [
  for (final path in paths) _fileAspect(path),
];

double? _fileAspect(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final length = file.lengthSync();
    if (length <= 0) return null;
    final read = file.readSync(math.min(length, 64 * 1024));
    return imageAspectFromBytes(read);
  } catch (_) {
    return null;
  } finally {
    try {
      file?.closeSync();
    } catch (_) {}
  }
}

int _u32be(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _u16le(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

({int width, int height})? _pngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  if (bytes.length < 24) return null;
  final width = _u32be(bytes, 16), height = _u32be(bytes, 20);
  return width > 0 && height > 0 ? (width: width, height: height) : null;
}

({int width, int height})? _gifSize(Uint8List bytes) {
  if (bytes.length < 10) return null;
  final header = String.fromCharCodes(bytes.sublist(0, 6));
  if (header != 'GIF87a' && header != 'GIF89a') return null;
  final width = _u16le(bytes, 6), height = _u16le(bytes, 8);
  return width > 0 && height > 0 ? (width: width, height: height) : null;
}

({int width, int height})? _webpSize(Uint8List bytes) {
  if (bytes.length < 30) return null;
  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
  if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WEBP') return null;
  final kind = String.fromCharCodes(bytes.sublist(12, 16));
  if (kind == 'VP8 ') {
    // Lossy: 3-byte frame tag, 3-byte start code, then 14-bit dimensions.
    if (bytes[23] != 0x9D || bytes[24] != 0x01 || bytes[25] != 0x2A) {
      return null;
    }
    final width = _u16le(bytes, 26) & 0x3FFF;
    final height = _u16le(bytes, 28) & 0x3FFF;
    return width > 0 && height > 0 ? (width: width, height: height) : null;
  }
  if (kind == 'VP8L') {
    if (bytes[20] != 0x2F) return null;
    final b1 = bytes[21], b2 = bytes[22], b3 = bytes[23], b4 = bytes[24];
    final width = ((b2 & 0x3F) << 8 | b1) + 1;
    final height = ((b4 & 0x0F) << 10 | b3 << 2 | b2 >> 6) + 1;
    return (width: width, height: height);
  }
  if (kind == 'VP8X') {
    final width = (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)) + 1;
    final height = (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)) + 1;
    return (width: width, height: height);
  }
  return null;
}

({int width, int height})? _jpegSize(Uint8List bytes) {
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    if (marker == 0xFF) {
      offset++;
      continue;
    }
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) return null;
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (length < 2) return null;
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
      final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
      return width > 0 && height > 0 ? (width: width, height: height) : null;
    }
    offset += 2 + length;
  }
  return null;
}
