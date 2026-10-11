import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/theme.dart';
import 'package:flutter_gallery_test/widgets/ambient_glass.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  test('OKLab round-trips sRGB colours', () {
    for (final color in [
      const Color(0xFF1A23DE),
      const Color(0xFFFFC94D),
      const Color(0xFF808080),
      const Color(0xFF000000),
      const Color(0xFFFFFFFF),
    ]) {
      final back = Oklab.fromColor(color).toColor();
      expect((back.r - color.r).abs(), lessThan(0.005));
      expect((back.g - color.g).abs(), lessThan(0.005));
      expect((back.b - color.b).abs(), lessThan(0.005));
    }
  });

  test('toning bounds lightness and chroma', () {
    final neon = Oklab.fromColor(const Color(0xFFFFFF00)).toned();
    expect(neon.l, lessThanOrEqualTo(0.65));
    expect(neon.chroma, lessThanOrEqualTo(0.17 + 1e-9));
    final black = Oklab.fromColor(const Color(0xFF000000)).toned();
    expect(black.l, 0.35);
  });

  test('glass keeps white text readable and a fixed stop count', () {
    for (final edge in [
      [Colors.white, Colors.yellow, Colors.white, Colors.yellow],
      [Colors.red, Colors.blue, Colors.orange, Colors.green],
      <Color>[],
    ]) {
      final stops = glassStops(edge);
      expect(stops, hasLength(10));
      for (final stop in stops) {
        expect(contrastRatio(stop, AppColors.foam), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('bottom-edge colours come from the image\'s lower half', () async {
    final dir = await Directory.systemTemp.createTemp('glass');
    addTearDown(() => dir.delete(recursive: true));
    // Red on top, left half green and right half blue at the bottom.
    final image = img.Image(width: 40, height: 40);
    for (var y = 0; y < 40; y++) {
      for (var x = 0; x < 40; x++) {
        image.setPixelRgb(
          x,
          y,
          y < 20 ? 255 : 0,
          y >= 20 && x < 20 ? 255 : 0,
          y >= 20 && x >= 20 ? 255 : 0,
        );
      }
    }
    final file = File(p.join(dir.path, 'edge.png'))
      ..writeAsBytesSync(img.encodePng(image));
    final colors = (await bottomEdgeColors(file.path))!;
    expect(colors, hasLength(4));
    expect(colors.first.g, greaterThan(0.9));
    expect(colors.first.r, lessThan(0.1));
    expect(colors.last.b, greaterThan(0.9));
  });
}
