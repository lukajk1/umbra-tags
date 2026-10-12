import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/main.dart';
import 'package:flutter_gallery_test/theme.dart';

Widget _tile(List<String> tags, {LayoutMode layout = LayoutMode.crop}) =>
    MaterialApp(
      theme: buildAppTheme(),
      home: Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: GalleryTile(
            path: 'a.png',
            thumbnail: Future.value(null),
            aspectRatio: 1,
            filename: 'a.png',
            tileSize: 200,
            layout: layout,
            selected: false,
            tagNames: tags,
          ),
        ),
      ),
    );

void main() {
  testWidgets('tiles list their tags along the bottom edge', (tester) async {
    await tester.pumpWidget(_tile(['ARKVAIN', 'weapon']));
    await tester.pump();
    final caption = find.byKey(const ValueKey('tile-tags-a.png'));
    expect(caption, findsOneWidget);
    expect(tester.widget<Text>(caption).data, 'ARKVAIN  ·  weapon');
    final tile = tester.getRect(find.byType(GalleryTile));
    final text = tester.getRect(caption);
    expect(tile.bottom - text.bottom, lessThan(12));
    expect(tester.widget<Text>(caption).style!.shadows, isNotEmpty);
  });

  testWidgets('untagged tiles have no caption', (tester) async {
    await tester.pumpWidget(_tile(const []));
    await tester.pump();
    expect(find.byKey(const ValueKey('tile-tags-a.png')), findsNothing);
  });
}
