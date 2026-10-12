import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../theme.dart';

/// The image's bottom edge as [columns] colours, left to right: the image is
/// reduced to a 4-row grid and the bottom two rows are averaged per column,
/// so the panel beneath the preview continues the colours it sits under.
/// Ported from the WinForms GradientPanel. Runs off the UI isolate.
Future<List<Color>?> bottomEdgeColors(String imagePath, {int columns = 4}) =>
    Isolate.run(() {
      final bytes = File(imagePath).readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final grid = img.copyResize(
        decoded,
        width: columns,
        height: 4,
        interpolation: img.Interpolation.average,
      );
      return [
        for (var x = 0; x < columns; x++)
          () {
            final a = grid.getPixel(x, 2), b = grid.getPixel(x, 3);
            return Color.fromARGB(
              255,
              ((a.r + b.r) / 2).round(),
              ((a.g + b.g) / 2).round(),
              ((a.b + b.b) / 2).round(),
            );
          }(),
      ];
    });

// ---------------------------------------------------------------- OKLab

/// A colour in OKLab (Björn Ottosson's perceptual space). Mixing here keeps
/// blends from going grey or brown the way sRGB mixing does.
class Oklab {
  const Oklab(this.l, this.a, this.b);
  final double l, a, b;

  factory Oklab.fromColor(Color color) {
    double lin(double c) =>
        c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
    final r = lin(color.r), g = lin(color.g), bl = lin(color.b);
    double cbrt(double v) =>
        (v < 0 ? -math.pow(-v, 1 / 3) : math.pow(v, 1 / 3)).toDouble();
    final l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl);
    final m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl);
    final s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl);
    return Oklab(
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    );
  }

  Color toColor() {
    final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = l - 0.0894841775 * a - 1.2914855480 * b;
    final l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_;
    double srgb(double c) {
      final v = c <= 0.0031308
          ? 12.92 * c
          : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
      return v.clamp(0.0, 1.0);
    }

    return Color.from(
      alpha: 1,
      red: srgb(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
      green: srgb(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
      blue: srgb(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3),
    );
  }

  double get chroma => math.sqrt(a * a + b * b);

  Oklab mix(Oklab other, double t) => Oklab(
    l + (other.l - l) * t,
    a + (other.a - a) * t,
    b + (other.b - b) * t,
  );

  /// Lightness and chroma brought into a band that reads as a tint on the
  /// dark panel: greys still register, neon does not glare.
  Oklab toned({
    double minL = 0.35,
    double maxL = 0.65,
    double maxChroma = 0.17,
  }) {
    final c = chroma;
    final scale = c == 0 ? 0.0 : math.min(c * 1.5, maxChroma) / c;
    return Oklab(l.clamp(minL, maxL), a * scale, b * scale);
  }
}

/// WCAG contrast ratio between two opaque colours.
double contrastRatio(Color x, Color y) {
  final lx = x.computeLuminance(), ly = y.computeLuminance();
  return (math.max(lx, ly) + 0.05) / (math.min(lx, ly) + 0.05);
}

/// Gradient stops for the glass: each edge colour toned, mixed into the
/// panel colour, and interpolated in OKLab. The mix strength backs off until
/// [text] keeps at least [minContrast] against every stop.
List<Color> glassStops(
  List<Color> edge, {
  Color base = AppColors.panel,
  Color text = AppColors.foam,
  double strength = 0.55,
  double minContrast = 4.5,
  int stepsBetween = 3,
}) {
  if (edge.isEmpty) return List.filled(stepsBetween * 3 + 1, base);
  final panel = Oklab.fromColor(base);
  final toned = [for (final c in edge) Oklab.fromColor(c).toned()];
  var alpha = strength;
  late List<Color> stops;
  while (true) {
    final keys = [for (final t in toned) panel.mix(t, alpha)];
    stops = [
      for (var i = 0; i < keys.length - 1; i++)
        for (var s = 0; s < stepsBetween; s++)
          keys[i].mix(keys[i + 1], s / stepsBetween).toColor(),
      keys.last.toColor(),
    ];
    if (alpha <= 0.05 ||
        stops.every((c) => contrastRatio(c, text) >= minContrast)) {
      break;
    }
    alpha -= 0.04;
  }
  // A fixed stop count keeps gradients animatable between images.
  final count = stepsBetween * 3 + 1;
  if (stops.length == count) return stops;
  return [
    for (var i = 0; i < count; i++)
      stops[(i * (stops.length - 1) / (count - 1)).round()],
  ];
}

/// A panel softly tinted by the image above it, like frosted glass: the
/// image's bottom-edge colours run left to right, strongest at the top where
/// the panel meets the image and settling into the panel colour below, under
/// a fine grain. Colours cross-fade when the image changes.
class AmbientGlass extends StatelessWidget {
  const AmbientGlass({super.key, required this.colors, required this.child});

  /// The image's bottom-edge colours, or null while loading or unavailable.
  final Future<List<Color>?>? colors;
  final Widget child;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Color>?>(
    future: colors,
    builder: (context, snapshot) {
      final stops = glassStops(snapshot.data ?? const []);
      return Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: stops),
              ),
            ),
          ),
          // The tint settles into the panel colour toward the bottom.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x003A0910), Color(0x8C3A0910)],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: _Grain())),
            ),
          ),
          child,
        ],
      );
    },
  );
}

/// Fixed one-pixel grain, light and dark specks at low opacity.
class _Grain extends CustomPainter {
  const _Grain();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final light = Paint()..color = const Color(0x0DFFFFFF);
    final dark = Paint()..color = const Color(0x12000000);
    final count = (size.width * size.height / 10).round();
    for (var i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawRect(
        Rect.fromLTWH(x.floorToDouble(), y.floorToDouble(), 1, 1),
        i.isEven ? light : dark,
      );
    }
  }

  @override
  bool shouldRepaint(_Grain old) => false;
}
