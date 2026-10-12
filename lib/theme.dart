import 'package:flutter/material.dart';

/// Crimson: one deep, saturated red on the title bar and icon; oxblood for
/// the working surfaces, darkest under the images so photos keep their own
/// colour; warm white for text and selection.
abstract final class AppColors {
  static const brand = Color(0xFFA50E1E); // Title bar, icon
  static const well = Color(0xFF1E0407); // Gallery background
  static const panel = Color(0xFF3A0910); // Sidebar, preview, status, dialogs
  static const raised = Color(0xFF5A0E18); // Hover, selected rows, chips
  static const rule = Color(0xFF74202A); // Dividers, outlines
  static const foam = Color(0xFFFFF2F1); // Text, selection, primary actions
  static const mist = Color(0xFFE6A3A6); // Secondary text
  static const haze = Color(0xFFB86A70); // Counts, guides, hints
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
      onPrimary: AppColors.brand,
      secondary: AppColors.foam,
      onSecondary: AppColors.brand,
      surface: AppColors.panel,
      onSurface: AppColors.foam,
      onSurfaceVariant: AppColors.mist,
      surfaceContainerHighest: AppColors.raised,
      outline: AppColors.rule,
      outlineVariant: AppColors.rule,
      error: Color(0xFFFFC46B), // Amber: red error text would vanish on red
    ),
    scaffoldBackgroundColor: AppColors.well,
    canvasColor: AppColors.panel,
    dividerColor: AppColors.rule,
    textTheme: text,
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _serif),
    dividerTheme: const DividerThemeData(color: AppColors.rule, space: 1),
    // The one saturated band.
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.brand,
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
      checkColor: const WidgetStatePropertyAll(AppColors.brand),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.foam,
      inactiveTrackColor: Color(0x66FFF2F1),
      thumbColor: AppColors.foam,
      overlayColor: Color(0x29FFF2F1),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(square),
        side: const WidgetStatePropertyAll(
          BorderSide(color: Color(0x73FFF2F1)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.foam : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.brand
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
