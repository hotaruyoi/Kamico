import 'dart:io';
import 'package:image/image.dart' as img;

// Run from the client root. An optional input replaces the compact source master.
void main(List<String> args) {
  final sourceFile = File(
    args.isEmpty ? 'artwork/launcher-foreground.png' : args.single,
  );
  final decoded = img.decodePng(sourceFile.readAsBytesSync());
  if (decoded == null) throw const FormatException('Invalid launcher PNG');
  final master = img.copyResize(
    decoded,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.average,
  );
  void save(String path, img.Image image) {
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image, level: 9));
  }

  img.Image canvas(int size, {required bool adaptive}) {
    final image = img.Image(width: size, height: size, numChannels: 4);
    if (!adaptive) img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
    // Android's foreground is 108dp; keep the artwork inside its 66dp safe area.
    final side = (size * (adaptive ? 66 / 108 : .94)).round();
    final artwork = img.copyResize(
      master,
      width: side,
      height: side,
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(
      image,
      artwork,
      dstX: (size - side) ~/ 2,
      dstY: (size - side) ~/ 2,
    );
    return image;
  }

  save('artwork/launcher-foreground.png', master);
  for (final entry in {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  }.entries) {
    save(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      canvas(entry.value, adaptive: false),
    );
  }
  final foreground = canvas(432, adaptive: true);
  save(
    'android/app/src/main/res/drawable-nodpi/kamico_launcher_foreground.png',
    foreground,
  );
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(
    img.IcoEncoder().encodeImages([
      for (final size in [16, 32, 48, 64, 128, 256])
        canvas(size, adaptive: false),
    ]),
  );
  final preview = img.Image(width: 432, height: 432, numChannels: 4);
  img.fill(preview, color: img.ColorRgba8(255, 255, 255, 255));
  img.compositeImage(preview, foreground);
  save('docs/previews/1.0.1/launcher-adaptive.png', preview);
  save('docs/previews/1.0.1/launcher-legacy.png', canvas(192, adaptive: false));
}
