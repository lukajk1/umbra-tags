import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/storage/tag_repository.dart';
import 'package:flutter_gallery_test/widgets/tag_widgets.dart';

LibraryTag _tag(String id, [String? parent]) =>
    LibraryTag.fromMap({'id': id, 'name': id, 'parent_id': parent});

// arkvain
// ├ reference
// │ └ artsy
// └ weapon
// photos
final _tags = [
  _tag('arkvain'),
  _tag('reference', 'arkvain'),
  _tag('artsy', 'reference'),
  _tag('weapon', 'arkvain'),
  _tag('photos'),
];

Widget _sidebar(Set<String> collapsed, ValueChanged<String> onToggle) =>
    MaterialApp(
      home: Scaffold(
        body: TagSidebar(
          tags: _tags,
          view: LibraryView.all,
          selectedTag: null,
          busy: false,
          onView: (_) {},
          onSelect: (_) {},
          onCreate: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          collapsedTags: collapsed,
          onToggleCollapsed: onToggle,
        ),
      ),
    );

void main() {
  test('collapsing a tag hides its whole subtree only', () {
    List<String> names(Set<String> collapsed) => [
      for (final row in visibleTagRows(tagTree(_tags), collapsed)) row.tag.id,
    ];
    expect(names({}), ['arkvain', 'reference', 'artsy', 'weapon', 'photos']);
    expect(names({'reference'}), ['arkvain', 'reference', 'weapon', 'photos']);
    expect(names({'arkvain'}), ['arkvain', 'photos']);
    // A collapsed tag inside a collapsed tag changes nothing further.
    expect(names({'arkvain', 'reference'}), ['arkvain', 'photos']);
  });

  testWidgets('only tags with children get an expander, which toggles', (
    tester,
  ) async {
    final toggled = <String>[];
    await tester.pumpWidget(_sidebar({'reference'}, toggled.add));

    expect(find.byKey(const ValueKey('tag-expander-arkvain')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tag-expander-reference')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tag-expander-weapon')), findsNothing);
    expect(find.byKey(const ValueKey('tag-filter-artsy')), findsNothing);
    expect(find.byKey(const ValueKey('tag-filter-weapon')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag-expander-reference')));
    expect(toggled, ['reference']);
  });

  testWidgets('searching shows matches inside collapsed tags', (tester) async {
    await tester.pumpWidget(_sidebar({'arkvain'}, (_) {}));
    expect(find.byKey(const ValueKey('tag-filter-artsy')), findsNothing);

    await tester.enterText(find.byType(TextField), 'art');
    await tester.pump();
    expect(find.byKey(const ValueKey('tag-filter-artsy')), findsOneWidget);
  });
}
