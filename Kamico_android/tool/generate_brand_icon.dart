import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  // Same K outline as the adaptive vector. Supersampled for legacy launchers.
  const polygon = [
    (32, 28),
    (42, 28),
    (42, 51),
    (62, 28),
    (75, 28),
    (52, 54),
    (76, 80),
    (62, 80),
    (42, 58),
    (42, 80),
    (32, 80),
  ];
  final image = img.Image(width: 864, height: 864);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final px = (x + .5) / 8, py = (y + .5) / 8;
      var inside = false;
      for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        final a = polygon[i], b = polygon[j];
        if ((a.$2 > py) != (b.$2 > py) &&
            px < (b.$1 - a.$1) * (py - a.$2) / (b.$2 - a.$2) + a.$1) {
          inside = !inside;
        }
      }
      if (inside) image.setPixelRgb(x, y, 233, 91, 145);
    }
  }
  for (final entry in {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  }.entries) {
    File(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
    ).writeAsBytesSync(
      img.encodePng(
        img.copyResize(
          image,
          width: entry.value,
          height: entry.value,
          interpolation: img.Interpolation.average,
        ),
      ),
    );
  }
  Directory('docs/previews/0.16.0').createSync(recursive: true);
  File('docs/previews/0.16.0/kamico-icon.png').writeAsBytesSync(
    img.encodePng(
      img.copyResize(
        image,
        width: 432,
        height: 432,
        interpolation: img.Interpolation.average,
      ),
    ),
  );
}
