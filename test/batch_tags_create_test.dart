import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/storage/library_store.dart';
import 'package:flutter_gallery_test/storage/tag_repository.dart';
import 'package:flutter_gallery_test/widgets/tag_widgets.dart';

void main() {
  testWidgets('new top-level and child tags are created and ticked', (
    tester,
  ) async {
    final created = <(String, String?)>[];
    List<String>? added;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => BatchTagsDialog(
                  tags: [
                    LibraryTag.fromMap({
                      'id': 'env',
                      'name': 'env',
                      'parent_id': null,
                    }),
                  ],
                  assets: [
                    LibraryAsset.fromMap({
                      'id': '1',
                      'relative_path': 'media/1.png',
                      'original_filename': '1.png',
                      'width': 10,
                      'height': 10,
                      'sha256': 'hash',
                    }),
                  ],
                  onCreateTag: (name, parent) async {
                    created.add((name, parent));
                    return 'new-${created.length}';
                  },
                  onSave: (add, remove) async => added = add,
                ),
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    Future<void> saveTag(String name) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(TagDetailsDialog),
          matching: find.byType(TextField),
        ),
        name,
      );
      await tester.tap(find.text('Save tag'));
      await tester.pumpAndSettle();
    }

    // A new top-level tag from the button beside the search box.
    await tester.tap(find.text('New tag'));
    await tester.pumpAndSettle();
    await saveTag('props');
    // A child tag from env's row.
    await tester.tap(find.byTooltip('Add child tag to “env”'));
    await tester.pumpAndSettle();
    await saveTag('ruins');

    expect(created, [('props', null), ('ruins', 'env')]);
    for (final id in ['new-1', 'new-2']) {
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(ValueKey('assign-tag-$id')))
            .value,
        isTrue,
      );
    }
    await tester.tap(find.text('Apply tags'));
    await tester.pumpAndSettle();
    expect(added, unorderedEquals(['new-1', 'new-2']));
  });
}
