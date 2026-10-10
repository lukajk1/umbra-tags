import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/storage/library_store.dart';
import 'package:flutter_gallery_test/widgets/resize_dialog.dart';

LibraryAsset _asset(int width, int height, {int bytes = 12 * 1024 * 1024}) =>
    LibraryAsset.fromMap({
      'id': '00000000-0000-0000-0000-000000000001',
      'relative_path': 'media/00/x.jpg',
      'original_filename': 'big.jpg',
      'width': width,
      'height': height,
      'byte_size': bytes,
      'sha256': 'a' * 64,
    });

Future<ResizeChoice?> _open(WidgetTester tester, Widget dialog) async {
  ResizeChoice? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<ResizeChoice>(
            context: context,
            builder: (_) => dialog,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  test('sizes keep the aspect ratio and at least one pixel', () {
    expect(scaledSize(6000, 4000, 0.5), (3000, 2000));
    expect(scaledSize(6000, 4000, 1 / 3), (2000, 1333));
    expect(scaledSize(3, 1, 0.1), (1, 1));
    expect(fitLongEdge(4000, 6000, 3000), (2000, 3000));
  });

  testWidgets('shows current dimensions and each breakpoint size', (
    tester,
  ) async {
    await _open(tester, ResizeDialog(asset: _asset(6000, 4000)));
    expect(find.text('Current size: 6000 × 4000 px · 12.0 MB'), findsOneWidget);
    for (final size in [
      '4500 × 3000',
      '3000 × 2000',
      '2000 × 1333',
      '1500 × 1000',
      '600 × 400',
    ]) {
      expect(find.text('→  $size px'), findsOneWidget);
    }
    // 50% is the default choice.
    expect(find.text('Resize to 3000 × 2000'), findsOneWidget);
  });

  testWidgets('batch mode preselects the largest size under the threshold '
      'and offers Skip and Stop', (tester) async {
    late ResizeChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showDialog<ResizeChoice>(
              context: context,
              builder: (_) => ResizeDialog(
                asset: _asset(6000, 4000),
                position: 2,
                total: 5,
                suggestedLongEdge: 2500,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Resize large images · 2 of 5'), findsOneWidget);
    expect(find.text('Resize to 2000 × 1333'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(choice?.action, ResizeAction.skip);
  });

  testWidgets('the slider and the options stay in sync', (tester) async {
    await _open(tester, ResizeDialog(asset: _asset(6000, 4000)));
    Slider slider() =>
        tester.widget<Slider>(find.byKey(const ValueKey('resize-slider')));

    // Starts on 50%.
    expect(slider().value, closeTo(0.5, 0.001));
    expect(find.text('50%  ·  3000 × 2000'), findsOneWidget);

    // Near a breakpoint it snaps to that option.
    slider().onChanged!(0.26);
    await tester.pump();
    expect(find.text('Resize to 1500 × 1000'), findsOneWidget);

    // Elsewhere it sets the long edge.
    slider().onChanged!(0.6);
    await tester.pump();
    expect(find.text('Resize to 3600 × 2400'), findsOneWidget);
    expect(find.widgetWithText(TextField, '3600'), findsOneWidget);

    // Picking an option moves the slider.
    await tester.tap(find.text('10%'));
    await tester.pump();
    expect(slider().value, closeTo(0.1, 0.001));
  });

  test('large-image threshold matches by long edge or file size', () {
    const pixels = LargeImageThreshold(LargeImageMeasure.longEdge, 4000);
    const megabytes = LargeImageThreshold(LargeImageMeasure.fileSize, 10);
    expect(pixels.matches(_asset(4001, 10)), isTrue);
    expect(pixels.matches(_asset(4000, 3000)), isFalse);
    expect(megabytes.matches(_asset(10, 10, bytes: 11 * 1024 * 1024)), isTrue);
    expect(megabytes.matches(_asset(9000, 9000, bytes: 1024)), isFalse);
  });
}
