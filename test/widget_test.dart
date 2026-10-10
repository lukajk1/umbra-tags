import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/main.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets(
    'empty app exposes library creation and opening, not demo assets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const GalleryApp());
      await tester.pumpAndSettle();
      expect(find.text('New library'), findsOneWidget);
      expect(find.text('Open library'), findsOneWidget);
      expect(find.text('Your images. Your library.'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('window buttons stay at the right edge at any width', (
    tester,
  ) async {
    for (final width in [1024.0, 1280.0, 1920.0, 2560.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(const GalleryApp());
      await tester.pumpAndSettle();
      final close = tester.getRect(find.byType(WindowCaptionButton).last);
      expect(close.right, width, reason: 'at $width px');
      expect(close.top, 0);
      // The search stays centred between the menus and the tools.
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
