import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/main.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class _Picker extends FileSelectorPlatform {
  _Picker(this.folder);
  final String folder;
  List<XFile> files = [];
  @override
  Future<String?> getDirectoryPathWithOptions(
    FileDialogOptions options,
  ) async => folder;
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => files;
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (predicate()) return;
  }
  fail('Library UI did not reach the expected state.');
}

bool _idle() => find.byType(CircularProgressIndicator).evaluate().isEmpty;

void main() {
  testWidgets(
    'Delete hides at once, Undo restores, then the file goes to the Recycle Bin',
    (tester) async {
      final previousPicker = FileSelectorPlatform.instance;
      final directory = Directory.systemTemp.createTempSync('umbra-undo-');
      final root = Directory(p.join(directory.path, 'library'))..createSync();
      final picker = _Picker(root.path);
      picker.files = [
        for (var i = 0; i < 4; i++)
          XFile(
            (File(p.join(directory.path, 'image$i.png'))..writeAsBytesSync(
                  img.encodePng(
                    img.fill(
                      img.Image(width: 40, height: 30),
                      color: img.ColorRgb8(40 * i, 60, 90),
                    ),
                  ),
                ))
                .path,
          ),
      ];
      FileSelectorPlatform.instance = picker;
      final recycled = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('umbra_tags/shell'),
        (call) async {
          if (call.method == 'recycleFiles') {
            recycled.addAll((call.arguments as List).cast<String>());
          }
          return true;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('umbra_tags/shell'),
          null,
        );
        FileSelectorPlatform.instance = previousPicker;
        directory.deleteSync(recursive: true);
      });
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const GalleryApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('New library'));
      await _until(tester, () => find.text('Create').evaluate().isNotEmpty);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Deletions',
      );
      await tester.tap(find.text('Create'));
      await _until(
        tester,
        () => find.text('0 images').evaluate().isNotEmpty && _idle(),
      );
      await tester.tap(find.text('Import'));
      await _until(
        tester,
        () => find.byType(GalleryTile).evaluate().length == 4 && _idle(),
      );

      final tiles = find.byType(GalleryTile);
      recycled.clear(); // The import recycled its source files.
      // Select one image (imports leave all new images selected).
      await tester.tap(tiles.at(1), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await _until(tester, () => tiles.evaluate().length == 3 && _idle());
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500)); // toast slides in
      await tester.tap(find.text('Undo'));
      await _until(tester, () => tiles.evaluate().length == 4 && _idle());
      expect(recycled, isEmpty);

      // Delete again and let the undo window pass.
      await tester.tap(tiles.at(1), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await _until(tester, () => tiles.evaluate().length == 3 && _idle());
      await tester.pump(const Duration(seconds: 6));
      await _until(tester, () => recycled.isNotEmpty && _idle());
      expect(
        recycled.single.replaceAll(r'\', '/'),
        matches(RegExp(r'/staging/trash/[0-9a-f-]+/image\d\.png$')),
      );
      expect(tiles, findsNWidgets(3));

      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close library'));
      await _until(
        tester,
        () => find.text('Library closed').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
