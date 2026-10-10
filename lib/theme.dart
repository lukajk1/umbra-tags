import 'package:flutter/material.dart';

/// Ultramarine: colours from the dithered-waves reference. Full ultramarine
/// only on the top bar; deep blues for the working surfaces, darkest under
/// the images so photos keep their own colour; white for text and selection.
abstract final class AppColors {
  static const ultra = Color(0xFF1A23DE); // Top bar, dither ink
  static const well = Color(0xFF070A33); // Gallery background
  static const panel = Color(0xFF0C1163); // Sidebar, preview, status, dialogs
  static const raised = Color(0xFF141B8A); // Hover, selected rows, chips
  static const rule = Color(0xFF262DA0); // Dividers, outlines
  static const foam = Color(0xFFF3F5FF); // Text, selection, primary actions
  static const mist = Color(0xFFA3ABEE); // Secondary text
  static const haze = Color(0xFF6870C9); // Counts, guides, hints
  static const star = Color(0xFFFFC94D); // Stars only

  // Roles the rest of the app was written against.
  static const darker = panel;
  static const lighter = well;
  static const accent = foam;
}

const _serif = 'LibreBaskerville';

ThemeData buildAppTheme() {
  final base = ThemeData.dark();
  final text = base.textTheme
      .apply(
        fontFamily: _serif,
        bodyColor: AppColors.foam,
        displayColor: AppColors.foam,
      )
      .copyWith(
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontFamily: _serif,
          color: AppColors.mist,
        ),
      );
  const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: const BorderSide(color: AppColors.rule),
  );
  return base.copyWith(
    colorScheme: const ColorScheme.dark(
      primary: AppColors.foam,
      onPrimary: AppColors.ultra,
      secondary: AppColors.foam,
      onSecondary: AppColors.ultra,
      surface: AppColors.panel,
      onSurface: AppColors.foam,
      onSurfaceVariant: AppColors.mist,
      surfaceContainerHighest: AppColors.raised,
      outline: AppColors.rule,
      outlineVariant: AppColors.rule,
      error: Color(0xFFFF8A80),
    ),
    scaffoldBackgroundColor: AppColors.well,
    canvasColor: AppColors.panel,
    dividerColor: AppColors.rule,
    textTheme: text,
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _serif),
    dividerTheme: const DividerThemeData(color: AppColors.rule, space: 1),
    // The one saturated band.
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ultra,
      foregroundColor: AppColors.foam,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: square,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(side: BorderSide(color: AppColors.rule)),
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.panel),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: AppColors.rule)),
        shape: WidgetStatePropertyAll(square),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.raised),
      textStyle: TextStyle(color: AppColors.foam, fontFamily: _serif),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.raised,
      contentTextStyle: TextStyle(color: AppColors.foam, fontFamily: _serif),
      actionTextColor: AppColors.foam,
    ),
    listTileTheme: const ListTileThemeData(
      selectedColor: AppColors.foam,
      selectedTileColor: AppColors.raised,
      iconColor: AppColors.mist,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.well,
      hintStyle: const TextStyle(
        color: AppColors.haze,
        fontStyle: FontStyle.italic,
      ),
      prefixIconColor: AppColors.mist,
      suffixIconColor: AppColors.mist,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: AppColors.foam),
      ),
    ),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(square)),
    ),
    outlinedButtonTheme: const OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(square),
        side: WidgetStatePropertyAll(BorderSide(color: AppColors.rule)),
        foregroundColor: WidgetStatePropertyAll(AppColors.foam),
      ),
    ),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(AppColors.foam),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.raised,
      side: BorderSide(color: AppColors.rule),
      shape: square,
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: AppColors.mist, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? AppColors.foam : null,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.ultra),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.foam,
      inactiveTrackColor: Color(0x66F3F5FF),
      thumbColor: AppColors.foam,
      overlayColor: Color(0x29F3F5FF),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(square),
        side: const WidgetStatePropertyAll(
          BorderSide(color: Color(0x73F3F5FF)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.foam : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ultra
              : AppColors.foam,
        ),
      ),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(AppColors.rule),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.foam,
      linearTrackColor: AppColors.well,
    ),
  );
}

/// A 1-bit ordered-dither band of white on ultramarine, like the waves in the
/// reference image. [density] is the mean share of white pixels.
class DitherStrip extends StatelessWidget {
  const DitherStrip({super.key, this.height = 4, this.density = 0.22});
  final double height, density;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _DitherPainter(density)),
  );
}

class _DitherPainter extends CustomPainter {
  _DitherPainter(this.density);
  final double density;

  // 4×4 Bayer thresholds.
  static const _bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.ultra);
    const cell = 1.0; // One logical pixel per dither dot.
    final white = Paint()..color = AppColors.foam;
    final rows = (size.height / cell).ceil(),
        columns = (size.width / cell).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        // Slow waves along the strip, brighter toward its top edge.
        final wave = 0.5 + 0.5 * _sin(x / 9) * _sin(x / 31 + y * 0.7);
        final value = density * (0.4 + 1.2 * wave) * (1.2 - y / rows * 0.5);
        if (value > (_bayer[(y % 4) * 4 + x % 4] + 0.5) / 16) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), white);
        }
      }
    }
  }

  static double _sin(double v) {
    // Cheap, smooth periodic function; exact sine is not needed here.
    final t = (v / 6.283185307) % 1.0;
    final u = t < 0.5 ? t * 4 - 1 : 3 - t * 4;
    return u * (2 - u.abs());
  }

  @override
  bool shouldRepaint(_DitherPainter old) => old.density != density;
}

/// A square slider thumb, matching the theme's square corners.
class SquareSliderThumb extends SliderComponentShape {
  const SquareSliderThumb({this.size = 12});
  final double size;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.square(size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: size, height: size),
      Paint()..color = sliderTheme.thumbColor ?? AppColors.foam,
    );
  }
}
