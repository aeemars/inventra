// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  _generate(1024, 'assets/icons/app_icon.png');
  _generateForeground(1024, 'assets/icons/app_icon_foreground.png');
  print('✅  Icons written to assets/icons/');
}

void _generate(int size, String path) {
  final image = img.Image(width: size, height: size, numChannels: 4);

  // ── Gradient background ──
  // primaryLight #4CAF50 top-left → primaryDark #1B5E20 bottom-right
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final t = (x + y) / (size * 2.0);
      final r = _lerp(0x4C, 0x1B, t).round();
      final g = _lerp(0xAF, 0x5E, t).round();
      final b = _lerp(0x50, 0x20, t).round();
      image.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
    }
  }

  // ── Draw mark: spine + 3 bars ──
  _drawBar(image, size, 0.24, 0.24, 0.28, 0.76, (size * 0.055).round(), 140); // spine
  _drawBar(image, size, 0.24, 0.78, 0.30, 0.30, (size * 0.115).round(), 255); // bar 1
  _drawBar(image, size, 0.24, 0.64, 0.52, 0.52, (size * 0.115).round(), 255); // bar 2
  _drawBar(image, size, 0.24, 0.50, 0.74, 0.74, (size * 0.115).round(), 255); // bar 3

  _save(image, path);
}

void _generateForeground(int size, String path) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  // Centred within the safe zone (~66% of canvas)
  // Offset centre to fit adaptive icon safe area
  final scale = 0.66;
  final offset = (size * (1 - scale) / 2).round();
  final inner = (size * scale).round();

  _drawBarOffset(image, inner, offset, 0.24, 0.24, 0.28, 0.76, (inner * 0.055).round(), 140);
  _drawBarOffset(image, inner, offset, 0.24, 0.78, 0.30, 0.30, (inner * 0.115).round(), 255);
  _drawBarOffset(image, inner, offset, 0.24, 0.64, 0.52, 0.52, (inner * 0.115).round(), 255);
  _drawBarOffset(image, inner, offset, 0.24, 0.50, 0.74, 0.74, (inner * 0.115).round(), 255);

  _save(image, path);
}

// Draw a thick rounded-cap line from (x1f*size, y1f*size) to (x2f*size, y2f*size)
void _drawBar(img.Image image, int size, double x1f, double x2f,
    double y1f, double y2f, int thickness, int alpha) {
  final x1 = (x1f * size).round();
  final x2 = (x2f * size).round();
  final y1 = (y1f * size).round();
  final y2 = (y2f * size).round();
  final r = thickness ~/ 2;
  final color = img.ColorRgba8(255, 255, 255, alpha);

  // End caps
  img.fillCircle(image, x: x1, y: y1, radius: r, color: color);
  img.fillCircle(image, x: x2, y: y2, radius: r, color: color);

  // Fill body between caps
  if (x1 == x2) {
    // Vertical line
    img.fillRect(image,
      x1: x1 - r, y1: math.min(y1, y2),
      x2: x2 + r, y2: math.max(y1, y2),
      color: color);
  } else {
    // Horizontal line
    img.fillRect(image,
      x1: math.min(x1, x2), y1: y1 - r,
      x2: math.max(x1, x2), y2: y2 + r,
      color: color);
  }
}

void _drawBarOffset(img.Image image, int inner, int offset,
    double x1f, double x2f, double y1f, double y2f,
    int thickness, int alpha) {
  final x1 = offset + (x1f * inner).round();
  final x2 = offset + (x2f * inner).round();
  final y1 = offset + (y1f * inner).round();
  final y2 = offset + (y2f * inner).round();
  final r = thickness ~/ 2;
  final color = img.ColorRgba8(255, 255, 255, alpha);

  img.fillCircle(image, x: x1, y: y1, radius: r, color: color);
  img.fillCircle(image, x: x2, y: y2, radius: r, color: color);

  if (x1 == x2) {
    img.fillRect(image,
      x1: x1 - r, y1: math.min(y1, y2),
      x2: x2 + r, y2: math.max(y1, y2),
      color: color);
  } else {
    img.fillRect(image,
      x1: math.min(x1, x2), y1: y1 - r,
      x2: math.max(x1, x2), y2: y2 + r,
      color: color);
  }
}

double _lerp(int a, int b, double t) => a + (b - a) * t;

void _save(img.Image image, String path) {
  Directory(path.substring(0, path.lastIndexOf('/'))).createSync(recursive: true);
  File(path).writeAsBytesSync(img.encodePng(image));
  print('  → $path');
}
