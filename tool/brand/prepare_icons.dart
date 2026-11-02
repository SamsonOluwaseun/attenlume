// Production sizing/masking only; the approved full-bleed artwork is the input.
// Run before `dart run flutter_launcher_icons`.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final source = img.decodePng(
    File('assets/brand/icons/attenlume-app-icon-fullbleed.png')
        .readAsBytesSync(),
  )!;
  final square = img.copyResize(source, width: 1254, height: 1254);
  final rounded = square.convert(numChannels: 4);
  const radius = 175.0;
  for (final pixel in rounded) {
    final x = pixel.x + 0.5;
    final y = pixel.y + 0.5;
    final cx = x.clamp(radius, rounded.width - radius);
    final cy = y.clamp(radius, rounded.height - radius);
    final distance = ((x - cx) * (x - cx) + (y - cy) * (y - cy));
    if (distance > radius * radius) pixel.a = 0;
  }
  for (final path in [
    'assets/brand/logos/attenlume-app-icon-primary.png',
    'assets/brand/icons/attenlume-app-icon-filled.png',
  ]) {
    File(path).writeAsBytesSync(img.encodePng(rounded));
  }
  File('android/app/src/main/res/drawable-xxhdpi/splash_logo.png')
      .writeAsBytesSync(
        img.encodePng(img.copyResize(rounded, width: 288, height: 288)),
      );
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(
    img.IcoEncoder().encodeImages([
      for (final size in [16, 24, 32, 48, 64, 128, 256])
        img.copyResize(rounded, width: size, height: size),
    ]),
  );
}
