import 'package:flutter/material.dart';
import 'package:flutter_gallery_test/storage/library_store.dart';
import 'package:flutter_gallery_test/theme.dart';
import 'package:flutter_gallery_test/widgets/tag_match_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryAsset _asset(String id) => LibraryAsset.fromMap({
  'id': id,
  'relative_path': 'media/$id.png',
  'original_filename': '$id.png',
  'width': 10,
  'height': 10,
  'sha256': 'a' * 64,
  'tag_ids': const <String>[],
});

const _scores = {'a': 0.5, 'b': 0.3, 'c': 0.1, 'd': 0.2};

Finder _tile(String id) => find.byKey(ValueKey('tag-match-tile-$id'));
Finder _check(String id) => find.byKey(ValueKey('tag-match-check-$id'));
bool _checked(WidgetTester tester, String id) =>
    tester.widget<Checkbox>(_check(id)).value!;

Future<List<String>> _openAndScan(
  WidgetTester tester, {
  Size size = const Size(1600, 1200),
  ScanTagMatches? scanSemantic,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final applied = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => TagMatchDialog(
              tagName: 'cat',
              assets: [for (final id in _scores.keys) _asset(id)],
              classifierLabels: const [],
              score: (asset, source, label) async => _scores[asset.id]!,
              scanSemantic: scanSemantic,
              thumbnail: (_) async => null,
              onApply: (assets) async =>
                  applied.addAll(assets.map((a) => a.id)),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan library'));
  await tester.pumpAndSettle();
  return applied;
}

void main() {
  testWidgets('matches show as tiles with checkboxes, best first', (
    tester,
  ) async {
    await _openAndScan(tester);
    // Default semantic threshold 0.15: c (0.1) is hidden.
    for (final id in ['a', 'b', 'd']) {
      expect(_tile(id), findsOneWidget);
      expect(_check(id), findsOneWidget);
      expect(_checked(tester, id), isTrue);
    }
    expect(_tile('c'), findsNothing);
    expect(find.text('3 selected of 3'), findsOneWidget);
    // Sorted by score: a, b, d left to right.
    final xs = [
      for (final id in ['a', 'b', 'd']) tester.getTopLeft(_tile(id)).dx,
    ];
    expect(xs[0] < xs[1] && xs[1] < xs[2], isTrue);
    // The checkbox sits in the tile's top-right corner.
    final tile = tester.getRect(_tile('a'));
    final box = tester.getRect(_check('a'));
    expect(box.right, greaterThan(tile.center.dx));
    expect(box.top, lessThan(tile.center.dy));

    await tester.tap(find.text('Show below threshold'));
    await tester.pumpAndSettle();
    expect(_tile('c'), findsOneWidget);
    expect(_checked(tester, 'c'), isFalse);
    expect(find.text('3 selected of 4'), findsOneWidget);
  });

  testWidgets('typing a minimum score reselects, and the slider follows', (
    tester,
  ) async {
    await _openAndScan(tester);
    final field = find.byKey(const ValueKey('match-threshold-field'));
    Slider slider() => tester.widget<Slider>(
      find.byKey(const ValueKey('match-threshold-slider')),
    );
    // After a scan the slider spans the scores found (0.1 to 0.5).
    expect(slider().min, closeTo(0.1, 1e-9));
    expect(slider().max, closeTo(0.5, 1e-9));

    await tester.enterText(field, '0.25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('2 selected of 2'), findsOneWidget); // a, b
    expect(slider().value, closeTo(0.25, 1e-9));

    // Dragging the slider rewrites the field.
    slider().onChanged!(0.15);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '0.1500');
    expect(find.text('3 selected of 3'), findsOneWidget);
  });

  testWidgets('clicking a tile or its checkbox toggles selection', (
    tester,
  ) async {
    final applied = await _openAndScan(tester);
    await tester.tap(_tile('b'));
    await tester.pump();
    expect(_checked(tester, 'b'), isFalse);
    expect(find.text('2 selected of 3'), findsOneWidget);
    await tester.tap(_check('d'));
    await tester.pump();
    expect(_checked(tester, 'd'), isFalse);
    expect(find.text('1 selected of 3'), findsOneWidget);
    expect(find.text('Add 1 images to tag'), findsOneWidget);

    await tester.tap(find.text('Add 1 images to tag'));
    await tester.pumpAndSettle();
    expect(applied, ['a']);
  });

  testWidgets('select none and select all', (tester) async {
    final applied = await _openAndScan(tester);
    await tester.tap(find.text('Select none'));
    await tester.pump();
    expect(find.text('0 selected of 3'), findsOneWidget);
    for (final id in ['a', 'b', 'd']) {
      expect(_checked(tester, id), isFalse);
    }
    final add = find.widgetWithText(FilledButton, 'Add 0 images to tag');
    expect(tester.widget<FilledButton>(add).onPressed, isNull);

    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('3 selected of 3'), findsOneWidget);

    await tester.tap(find.text('Show below threshold'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('4 selected of 4'), findsOneWidget);
    await tester.tap(find.text('Add 4 images to tag'));
    await tester.pumpAndSettle();
    expect(applied, ['a', 'b', 'c', 'd']);
  });

  testWidgets('double-clicking a tile opens the preview, selection kept', (
    tester,
  ) async {
    await _openAndScan(tester);
    await tester.tap(_tile('a'));
    await tester.tap(_tile('a'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-match-preview')), findsOneWidget);
    expect(find.textContaining('a.png · Match score 0.500'), findsOneWidget);
    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-match-preview')), findsNothing);
    expect(_checked(tester, 'a'), isTrue);
  });

  testWidgets('lays out without overflow in a small window', (tester) async {
    await _openAndScan(tester, size: const Size(1024, 680));
    expect(find.text('3 selected of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scans by the tag name alone without the batch scorer', (
    tester,
  ) async {
    await _openAndScan(tester);
    expect(find.text('Matching by the tag name.'), findsOneWidget);
  });

  testWidgets('matches by the images in the tag plus the name', (tester) async {
    var stoppedAsked = false;
    await _openAndScan(
      tester,
      scanSemantic: (progress, stopped) async {
        progress(0, 2);
        progress(2, 2);
        stoppedAsked = !stopped();
        return const TagMatchBatch(
          scores: {'a': 0.9, 'b': 0.7, 'c': 0.4, 'd': 0.55, 'other': 1.0},
          members: 41,
          nameWeight: 0.5,
          threshold: 0.6,
          errors: {'d': 'ignored: d has a score', 'zz': 'not in this dialog'},
        );
      },
    );
    expect(stoppedAsked, isTrue);
    expect(
      find.text('Matching by 41 images in this tag + the tag name'),
      findsOneWidget,
    );
    // The suggested threshold (a typical member's score) preselects a and b.
    expect(find.text('2 selected of 2'), findsOneWidget);
    expect(find.text('Minimum Match score 0.600'), findsOneWidget);
    expect(find.text('4 / 4 scanned · 0 failed'), findsOneWidget);
    final field = find.byKey(const ValueKey('match-threshold-field'));
    expect(tester.widget<TextField>(field).controller!.text, '0.6000');
    // A threshold the user picks survives the next scan.
    await tester.enterText(field, '0.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('3 selected of 3'), findsOneWidget);
    await tester.tap(find.text('Scan again'));
    await tester.pumpAndSettle();
    expect(find.text('3 selected of 3'), findsOneWidget);
  });

  testWidgets('says when the tag name is ignored or the only signal', (
    tester,
  ) async {
    var batch = const TagMatchBatch(
      scores: {'a': 0.9},
      members: 3,
      nameWeight: 0,
      threshold: 0.8,
    );
    await _openAndScan(tester, scanSemantic: (_, _) async => batch);
    expect(
      find.text(
        'Matching by 3 images in this tag (the tag name does not describe them, so it is not used)',
      ),
      findsOneWidget,
    );
    batch = const TagMatchBatch(scores: {'a': 0.1}, members: 0);
    await tester.tap(find.text('Scan again'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Matching by the tag name only: this tag has no indexed images yet.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('falls back to per-image name scores without the index', (
    tester,
  ) async {
    await _openAndScan(tester, scanSemantic: (_, _) async => null);
    expect(
      find.text(
        'Matching by the tag name only: the similarity index is unavailable.',
      ),
      findsOneWidget,
    );
    expect(find.text('3 selected of 3'), findsOneWidget);
  });
}
