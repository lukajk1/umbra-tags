import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gallery_test/storage/library_store.dart';
import 'package:flutter_gallery_test/storage/tag_repository.dart';
import 'package:flutter_gallery_test/widgets/ai_sort_dialog.dart';
import 'package:flutter_gallery_test/widgets/tag_widgets.dart';
import 'package:flutter_gallery_test/widgets/view_breadcrumbs.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryTag _tag(String id, {String? parent, bool reference = false}) =>
    LibraryTag.fromMap({
      'id': id,
      'name': id,
      'parent_id': parent,
      'excluded_from_all': reference ? 1 : 0,
    });

LibraryAsset _asset(String id, [List<String> tags = const []]) =>
    LibraryAsset.fromMap({
      'id': id,
      'relative_path': 'media/$id.png',
      'original_filename': '$id.png',
      'width': 10,
      'height': 10,
      'sha256': 'a' * 64,
      'tag_ids': tags,
    });

final _weapon = _tag('weapon');
final _armor = _tag('armor', reference: true);
final _typography = _tag('typography');
final _candidates = [_weapon, _armor, _typography];

/// Fixed ranking: weapon, armor, typography.
Future<List<AiSortSuggestion>> _score(LibraryAsset asset) async => [
  AiSortSuggestion(
    tag: _weapon,
    confidence: 0.7,
    votes: 7,
    neighbours: 10,
    members: 12,
  ),
  AiSortSuggestion(tag: _armor, confidence: 0.2, votes: 3, neighbours: 10),
  AiSortSuggestion(tag: _typography, confidence: 0.1, name: 0.8),
];

class _Harness {
  final applied = <String>[];
  final undone = <String>[];
  AiSortResult? result;
  bool closed = false;

  Future<void> open(WidgetTester tester, List<LibraryAsset> queue) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<AiSortResult>(
                context: context,
                barrierDismissible: false,
                builder: (_) => AiSortDialog(
                  title: 'Sort untagged images',
                  queue: queue,
                  candidates: _candidates,
                  score: _score,
                  apply: (asset, tag) async =>
                      applied.add('${asset.id}:${tag.id}'),
                  undo: (asset, tag) async =>
                      undone.add('${asset.id}:${tag.id}'),
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('1/2/3 accept, S skips, and the summary counts both', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.open(tester, [_asset('a'), _asset('b'), _asset('c')]);
    expect(find.text('Sort untagged images · 1 of 3'), findsOneWidget);
    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('7 of 10 most similar sorted images'), findsOneWidget);
    expect(find.text('no images yet: name match only'), findsOneWidget);
    expect(find.text('  reference tag'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.digit1);
    expect(find.text('Sort untagged images · 2 of 3'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.digit2);
    await _press(tester, LogicalKeyboardKey.keyS);
    expect(harness.applied, ['a:weapon', 'b:armor']);
    expect(find.text('Tagged 2, skipped 1.'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.enter);
    expect(harness.closed, isTrue);
    expect(harness.result!.accepted, 2);
    expect(harness.result!.skipped, 1);
    expect(harness.result!.remaining, 0);
  });

  testWidgets('3 accepts the third suggestion; Esc stops early', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.open(tester, [_asset('a'), _asset('b'), _asset('c')]);
    await _press(tester, LogicalKeyboardKey.digit3);
    expect(harness.applied, ['a:typography']);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.text('Tagged 1, skipped 0, 2 not reviewed.'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(harness.closed, isTrue);
    expect(harness.result!.remaining, 2);
  });

  testWidgets('Backspace undoes the last accepted tag and returns to it', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.open(tester, [_asset('a'), _asset('b')]);
    await _press(tester, LogicalKeyboardKey.digit1);
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(harness.undone, ['a:weapon']);
    expect(find.text('Sort untagged images · 1 of 2'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.keyS);
    await _press(tester, LogicalKeyboardKey.keyS);
    expect(find.text('Tagged 0, skipped 2.'), findsOneWidget);
  });

  testWidgets('Other… applies any candidate tag', (tester) async {
    final harness = _Harness();
    await harness.open(tester, [_asset('a')]);
    await _press(tester, LogicalKeyboardKey.keyO);
    expect(find.text('Choose a tag'), findsOneWidget);
    await tester.tap(find.text('armor').last);
    await tester.pumpAndSettle();
    expect(harness.applied, ['a:armor']);
    expect(find.text('Tagged 1, skipped 0.'), findsOneWidget);
  });

  testWidgets('clicking a suggestion accepts it', (tester) async {
    final harness = _Harness();
    await harness.open(tester, [_asset('a')]);
    final second = find.byKey(const ValueKey('ai-sort-suggestion-2'));
    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(harness.applied, ['a:armor']);
  });

  test('narrowing lists images with the parent tag but no child tag', () {
    final parent = _tag('ark');
    final tags = [
      parent,
      _tag('weapon', parent: 'ark'),
      _tag('sword', parent: 'weapon'),
      _tag('other'),
    ];
    final queue = narrowQueue(parent, tags, [
      _asset('direct', ['ark']),
      _asset('child', ['ark', 'weapon']),
      _asset('grandchild', ['ark', 'sword']),
      _asset('elsewhere', ['other']),
      _asset('also', ['ark', 'other']),
    ]);
    expect([for (final a in queue) a.id], ['direct', 'also']);
    expect([for (final t in childTags('ark', tags)) t.id], ['weapon']);
    expect([for (final t in childTags(null, tags)) t.id], ['ark', 'other']);
  });

  testWidgets('setup dialog picks a mode', (tester) async {
    AiSortPlan? plan;
    final parent = _tag('ark');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => plan = await showDialog<AiSortPlan>(
              context: context,
              builder: (_) => AiSortSetupDialog(
                tags: [
                  parent,
                  _tag('weapon', parent: 'ark'),
                ],
                untagged: 5,
                narrowable: {'ark': 3},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Start (5)'), findsOneWidget);
    await tester.tap(find.text('Narrow a tag into its child tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start (3)'));
    await tester.pumpAndSettle();
    expect(plan!.parent!.id, 'ark');
  });

  testWidgets('the breadcrumb strip offers an AI sort action', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewBreadcrumbs(
            tags: const [],
            view: LibraryView.untagged,
            tagId: null,
            onView: (_) {},
            onTag: (_) {},
            action: ViewAction('AI sort into tags…', () => pressed++),
          ),
        ),
      ),
    );
    await tester.tap(find.text('AI sort into tags…'));
    expect(pressed, 1);
  });
}
