// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  _generateFullIcon();
  _generateForeground();
  print('✅  App icons written to assets/icons/');
}

/// Full 1024×1024 icon — used for iOS and as fallback.
void _generateFullIcon() {
  const size = 1024;
  final image = img.Image(width: size, height: size, numChannels: 4);

  // Transparent base
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  // Green rounded-square background
  img.fillRect(
    image,
    x1: 0, y1: 0, x2: size, y2: size,
    color: img.ColorRgba8(0x2E, 0x7D, 0x32, 0xFF),
  );

  // White inventory-box silhouette (top lid)
  img.fillRect(image,
    x1: 212, y1: 270, x2: 812, y2: 380,
    color: img.ColorRgba8(255, 255, 255, 255));

  // Box body
  img.fillRect(image,
    x1: 232, y1: 380, x2: 792, y2: 680,
    color: img.ColorRgba8(255, 255, 255, 255));

  // Box divider line (darker white stripe across the middle of body)
  img.fillRect(image,
    x1: 232, y1: 490, x2: 792, y2: 510,
    color: img.ColorRgba8(0x2E, 0x7D, 0x32, 180));

  // Barcode lines below box
  final bars = [
    (280, 710, 320, 740), (330, 710, 360, 740), (370, 710, 420, 740),
    (430, 710, 450, 740), (460, 710, 510, 740), (520, 710, 540, 740),
    (550, 710, 580, 740), (590, 710, 640, 740), (650, 710, 680, 740),
    (690, 710, 744, 740),
  ];
  for (final b in bars) {
    img.fillRect(image,
      x1: b.$1, y1: b.$2, x2: b.$3, y2: b.$4,
      color: img.ColorRgba8(255, 255, 255, 220));
  }

  _save(image, 'assets/icons/app_icon.png');
}

/// Foreground layer for Android adaptive icon — white icon on transparent.
void _generateForeground() {
  const size = 1024;
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  // Same shapes but centred in the safe zone (108dp of 162dp = 66.7%)
  // Safe zone offset: ~170px on each side for 1024px canvas
  img.fillRect(image,
    x1: 330, y1: 310, x2: 694, y2: 400,
    color: img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(image,
    x1: 346, y1: 400, x2: 678, y2: 650,
    color: img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(image,
    x1: 346, y1: 510, x2: 678, y2: 525,
    color: img.ColorRgba8(0xBB, 0xFF, 0xBB, 120));

  // Barcode accent
  final bars = [
    (360, 668, 390, 688), (400, 668, 424, 688), (434, 668, 468, 688),
    (478, 668, 494, 688), (504, 668, 534, 688), (544, 668, 558, 688),
    (568, 668, 598, 688), (608, 668, 630, 688), (640, 668, 664, 688),
  ];
  for (final b in bars) {
    img.fillRect(image,
      x1: b.$1, y1: b.$2, x2: b.$3, y2: b.$4,
      color: img.ColorRgba8(255, 255, 255, 200));
  }

  _save(image, 'assets/icons/app_icon_foreground.png');
}

void _save(img.Image image, String path) {
  Directory(path.substring(0, path.lastIndexOf('/'))).createSync(recursive: true);
  File(path).writeAsBytesSync(img.encodePng(image));
  print('  → $path');
}
