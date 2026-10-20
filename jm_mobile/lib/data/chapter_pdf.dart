import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

/// Writes one borderless page per image, in reading order. Only one decoded
/// image is held at a time; the PDF is streamed to disk rather than assembled
/// in RAM. OneColumn asks PDF viewers for a continuous vertical page layout.
Future<void> writeChapterPdf(
  File target,
  List<File> pages, {
  Future<void> Function()? checkpoint,
}) async {
  if (pages.isEmpty) throw const FormatException('章节没有可下载的图片');
  final temporary = File('${target.path}.part');
  final out = await temporary.open(mode: FileMode.write);
  final offsets = <int>[0];
  Future<void> text(String value) => out.writeFrom(latin1.encode(value));
  Future<void> object(int id, String value) async {
    offsets.add(await out.position());
    await text('$id 0 obj\n$value\nendobj\n');
  }

  try {
    await text('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    await object(1, '<< /Type /Catalog /Pages 2 0 R /PageLayout /OneColumn >>');
    await object(
      2,
      '<< /Type /Pages /Count ${pages.length} /Kids [${List.generate(pages.length, (i) => '${3 + i * 3} 0 R').join(' ')}] >>',
    );
    for (var i = 0; i < pages.length; i++) {
      await checkpoint?.call();
      final jpeg = await compute(_pdfImage, await pages[i].readAsBytes());
      final width = jpeg.$1, height = jpeg.$2, bytes = jpeg.$3;
      // A common page width keeps a continuous strip even for mixed source sizes.
      const pageWidth = 720;
      final pageHeight = (height * pageWidth / width).toStringAsFixed(4);
      final id = 3 + i * 3;
      await object(
        id,
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidth $pageHeight] /Resources << /XObject << /Im0 ${id + 2} 0 R >> >> /Contents ${id + 1} 0 R >>',
      );
      final commands = 'q\n$pageWidth 0 0 $pageHeight 0 0 cm\n/Im0 Do\nQ\n';
      await object(
        id + 1,
        '<< /Length ${commands.length} >>\nstream\n${commands}endstream',
      );
      offsets.add(await out.position());
      await text(
        '${id + 2} 0 obj\n<< /Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${bytes.length} >>\nstream\n',
      );
      await out.writeFrom(bytes);
      await text('\nendstream\nendobj\n');
    }
    final start = await out.position();
    await text('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      await text('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    await text(
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$start\n%%EOF\n',
    );
    await out.flush();
  } catch (_) {
    await out.close();
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
  await out.close();
  await checkpoint?.call();
  await temporary.rename(target.path);
}

(int, int, Uint8List) _pdfImage(Uint8List bytes) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw const FormatException('图片无法解码，不能生成 PDF');
  final rgb = image.Image(
    width: decoded.width,
    height: decoded.height,
    numChannels: 3,
  );
  image.fill(rgb, color: image.ColorRgb8(255, 255, 255));
  image.compositeImage(rgb, decoded);
  return (
    rgb.width,
    rgb.height,
    Uint8List.fromList(image.encodeJpg(rgb, quality: 95)),
  );
}
