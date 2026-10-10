import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/storage/library_store.dart';
import 'package:flutter_gallery_test/storage/tag_repository.dart';
import 'package:flutter_gallery_test/widgets/tag_widgets.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  group('reference tags', () {
    late Directory folder;
    late LibraryStore store;
    setUp(() async {
      folder = await Directory.systemTemp.createTemp('umbra-reference-test-');
      final root = await Directory(p.join(folder.path, 'library')).create();
      store = await LibraryStore.create(root.path, 'Reference');
    });
    tearDown(() async {
      await store.close();
      await folder.delete(recursive: true);
    });
    var width = 8;
    Future<String> image() async {
      final file = File(p.join(folder.path, '${width++}.png'));
      await file.writeAsBytes(
        img.encodePng(img.Image(width: width, height: 8)),
      );
      return (await store.importImage(file.path)).asset.id;
    }

    Future<Set<String>> view({String? tagId, bool archived = false}) async => {
      for (final asset in await store.assets(
        tagId: tagId,
        archived: archived,
        excludeHidden: tagId == null && !archived,
      ))
        asset.id,
    };

    // art
    // ├ refs (reference)
    // │ ├ poses
    // │ └ private (reference)
    // └ sketches
    // other
    late String art, refs, poses, private, sketches, other;
    late String plain, sketch, ref, pose, sketchRef, priv, otherOnly, archived;
    setUp(() async {
      art = await store.saveTag(name: 'art');
      refs = await store.saveTag(name: 'refs', parentId: art);
      poses = await store.saveTag(name: 'poses', parentId: refs);
      private = await store.saveTag(name: 'private', parentId: refs);
      sketches = await store.saveTag(name: 'sketches', parentId: art);
      other = await store.saveTag(name: 'other');
      plain = await image();
      sketch = await image();
      ref = await image();
      pose = await image();
      sketchRef = await image();
      priv = await image();
      otherOnly = await image();
      archived = await image();
      await store.editTags([sketch], add: [sketches]);
      await store.editTags([ref], add: [refs]);
      await store.editTags([pose], add: [poses, other]);
      await store.editTags([sketchRef], add: [sketches, refs]);
      await store.editTags([priv], add: [private, poses]);
      await store.editTags([otherOnly], add: [other]);
      await store.editTags([archived], add: [refs]);
      await store.archive([archived], true);
      await store.setTagExcludedFromAll(refs, true);
      await store.setTagExcludedFromAll(private, true);
    });

    test('All images hides images under reference tags', () async {
      expect(await view(), {plain, sketch, otherOnly});
      expect((await store.viewCounts())['all'], 3);
    });

    test('filtering by the reference tag shows its images', () async {
      // Images with the nested reference tag stay hidden.
      expect(await view(tagId: refs), {ref, pose, sketchRef});
    });

    test('filtering by a child of a reference tag shows its images', () async {
      expect(await view(tagId: poses), {pose});
      expect(await view(tagId: private), {priv});
    });

    test(
      'unrelated tag views hide images that carry a reference tag',
      () async {
        expect(await view(tagId: art), {sketch});
        expect(await view(tagId: sketches), {sketch});
        expect(await view(tagId: other), {otherOnly});
      },
    );

    test('tag counts match their views', () async {
      final tags = await store.tags();
      for (final tag in tags) {
        expect(
          tag.assetCount,
          (await view(tagId: tag.id)).length,
          reason: tag.name,
        );
      }
      expect(
        {for (final tag in tags) tag.name: tag.assetCount},
        {
          'art': 1,
          'refs': 3,
          'poses': 1,
          'private': 1,
          'sketches': 1,
          'other': 1,
        },
      );
      expect(tags.where((t) => t.isReference).map((t) => t.name).toSet(), {
        'refs',
        'private',
      });
    });

    test('the archive ignores reference tags', () async {
      expect(await view(tagId: refs, archived: true), {archived});
      expect(await view(tagId: art, archived: true), {archived});
      expect(await view(archived: true), {archived});
    });

    test('unmarking restores ordinary views and counts', () async {
      await store.setTagExcludedFromAll(refs, false);
      await store.setTagExcludedFromAll(private, false);
      expect(await view(), {
        plain,
        sketch,
        ref,
        pose,
        sketchRef,
        priv,
        otherOnly,
      });
      expect(await view(tagId: art), {sketch, ref, pose, sketchRef, priv});
      final counts = {
        for (final tag in await store.tags()) tag.name: tag.assetCount,
      };
      expect(counts['art'], 5);
      expect(counts['other'], 2);
    });

    test('starred filter combines with the reference rule', () async {
      await store.setStarred([sketch, ref, pose], true);
      Future<Set<String>> starred(String tagId) async => {
        for (final asset in await store.assets(tagId: tagId, starredOnly: true))
          asset.id,
      };
      expect(await starred(art), {sketch});
      expect(await starred(refs), {ref, pose});
    });
  });

  group('sidebar', () {
    LibraryTag tag(String id, [String? parent, bool reference = false]) =>
        LibraryTag.fromMap({
          'id': id,
          'name': id,
          'parent_id': parent,
          'excluded_from_all': reference ? 1 : 0,
        });
    Widget sidebar(
      List<LibraryTag> tags,
      ValueChanged<LibraryTag> toggle, {
      double width = 220,
    }) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: TagSidebar(
            width: width,
            tags: tags,
            view: LibraryView.all,
            selectedTag: null,
            busy: false,
            onView: (_) {},
            onSelect: (_) {},
            onCreate: (_) {},
            onEdit: (_) {},
            onDelete: (_) {},
            onToggleExcluded: toggle,
          ),
        ),
      ),
    );

    testWidgets('the sidebar lays out at narrow and wide widths', (
      tester,
    ) async {
      final long = 'a very long tag name that cannot possibly fit ' * 3;
      final tags = [
        tag('art'),
        tag('refs', 'art', true),
        tag('poses', 'refs'),
        tag('deep', 'poses'),
        LibraryTag.fromMap({'id': 'long', 'name': long, 'parent_id': 'deep'}),
      ];
      for (final width in [160.0, 220.0, 480.0]) {
        await tester.pumpWidget(sidebar(tags, (_) {}, width: width));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$width');
        expect(tester.getSize(find.byType(TagSidebar)).width, width);
        expect(find.byKey(const ValueKey('tag-filter-long')), findsOneWidget);
      }
    });

    testWidgets('reference tags look different and toggle from the menu', (
      tester,
    ) async {
      final toggled = <String>[];
      await tester.pumpWidget(
        sidebar([
          tag('art'),
          tag('refs', 'art', true),
          tag('poses', 'refs'),
        ], (t) => toggled.add(t.id)),
      );
      expect(
        find.byKey(const ValueKey('reference-tag-icon-refs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reference-tag-icon-art')),
        findsNothing,
      );
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
      expect(
        find.byTooltip(
          'Reference tag: its images only appear when you filter by it',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Manage refs'));
      await tester.pumpAndSettle();
      expect(find.text('Unmark reference tag'), findsOneWidget);
      await tester.tap(find.text('Unmark reference tag'));
      await tester.pumpAndSettle();
      expect(toggled, ['refs']);

      await tester.tap(find.byTooltip('Manage art'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as reference tag'));
      await tester.pumpAndSettle();
      expect(toggled, ['refs', 'art']);
    });
  });
}
