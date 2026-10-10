import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/storage/library_store.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late LibraryStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('umbra-resize-');
    final root = await Directory('${temp.path}/library').create();
    store = await LibraryStore.create(root.path, 'Resize test');
  });
  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });

  img.Image gradient(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (final pixel in image) {
      pixel
        ..r = pixel.x * 255 ~/ width
        ..g = pixel.y * 255 ~/ height
        ..b = 90;
    }
    return image;
  }

  Future<LibraryAsset> importBytes(String name, Uint8List bytes) async {
    final file = await File(p.join(temp.path, name)).writeAsBytes(bytes);
    return (await store.importImage(file.path)).asset;
  }

  Future<img.Image> decodeStored(LibraryAsset asset) async => img.decodeImage(
    await File(store.absolutePath(asset.relativePath)).readAsBytes(),
  )!;

  test('PNG downscale updates the record and keeps tags and star', () async {
    final asset = await importBytes(
      'photo.png',
      img.encodePng(gradient(40, 20)),
    );
    expect(asset.byteSize, greaterThan(0));
    final tag = await store.saveTag(name: 'Keep');
    await store.editTags([asset.id], add: [tag]);
    await store.setStarred([asset.id], true);
    final thumbnail = await store.thumbnail(asset);
    final originalBytes = await File(
      store.absolutePath(asset.relativePath),
    ).readAsBytes();

    final resized = await store.resizeAsset(asset.id, width: 20, height: 10);
    expect(resized.width, 20);
    expect(resized.height, 10);
    expect(resized.relativePath, asset.relativePath);
    expect(resized.contentHash, isNot(asset.contentHash));
    expect(resized.tagIds, [tag]);
    expect(resized.starred, isTrue);
    expect(resized.importedAt, asset.importedAt);
    final file = File(store.absolutePath(resized.relativePath));
    final bytes = await file.readAsBytes();
    expect(resized.byteSize, bytes.length);
    expect(resized.contentHash, sha256.convert(bytes).toString());
    final decoded = await decodeStored(resized);
    expect([decoded.width, decoded.height], [20, 10]);
    expect(await File(thumbnail!).exists(), isFalse);

    final listed = (await store.assets()).single;
    expect(listed.contentHash, resized.contentHash);
    expect(listed.byteSize, resized.byteSize);
    expect(listed.tagIds, [tag]);
    expect(listed.starred, isTrue);

    final trashed = await store.trashFiles();
    expect(trashed, hasLength(1));
    expect(
      trashed.single.replaceAll(r'\', '/'),
      endsWith('/staging/trash/${asset.id}/photo.png'),
    );
    expect(await File(trashed.single).readAsBytes(), originalBytes);

    // A second resize keeps the first original in the trash too.
    await store.resizeAsset(asset.id, width: 10, height: 5);
    expect(await store.trashFiles(), hasLength(2));
    final staging = Directory(
      '${store.root}/staging',
    ).listSync().whereType<File>().map((f) => p.basename(f.path));
    expect(staging, isEmpty);
  });

  test('JPEG stays JPEG', () async {
    final asset = await importBytes(
      'shot.jpg',
      img.encodeJpg(gradient(64, 48), quality: 90),
    );
    final resized = await store.resizeAsset(asset.id, width: 32, height: 24);
    expect(resized.relativePath, asset.relativePath);
    expect(resized.relativePath, endsWith('.jpg'));
    final bytes = await File(
      store.absolutePath(resized.relativePath),
    ).readAsBytes();
    expect(img.findFormatForData(bytes), img.ImageFormat.jpg);
    final decoded = img.decodeJpg(bytes)!;
    expect([decoded.width, decoded.height], [32, 24]);
  });

  for (final lossless in [true, false]) {
    test('WebP (${lossless ? 'lossless' : 'lossy'}) stays WebP', () async {
      final asset = await importBytes(
        'web.webp',
        img.encodeWebP(gradient(40, 30), lossless: lossless),
      );
      final resized = await store.resizeAsset(asset.id, width: 20, height: 15);
      expect(resized.relativePath, asset.relativePath);
      expect(resized.relativePath, endsWith('.webp'));
      final bytes = await File(
        store.absolutePath(resized.relativePath),
      ).readAsBytes();
      expect(img.findFormatForData(bytes), img.ImageFormat.webp);
      final info = img.WebPDecoder().startDecode(bytes) as img.WebPInfo;
      expect(
        info.format,
        lossless ? img.WebPFormat.lossless : img.WebPFormat.lossy,
      );
      final decoded = img.decodeWebP(bytes)!;
      expect([decoded.width, decoded.height], [20, 15]);
    });
  }

  test('animated GIF keeps all frames', () async {
    final first = gradient(40, 20)..frameDuration = 100;
    first.addFrame(img.Image(width: 40, height: 20)..frameDuration = 100);
    first.addFrame(gradient(40, 20)..frameDuration = 100);
    final asset = await importBytes('anim.gif', img.encodeGif(first));
    final resized = await store.resizeAsset(asset.id, width: 20, height: 10);
    expect(resized.relativePath, endsWith('.gif'));
    final decoded = await decodeStored(resized);
    expect(decoded.numFrames, 3);
    expect([decoded.width, decoded.height], [20, 10]);
  });

  test('rejects sizes that are not smaller', () async {
    final asset = await importBytes('a.png', img.encodePng(gradient(40, 20)));
    for (final (w, h) in [(80, 40), (40, 20), (40, 10), (0, 10), (20, 0)]) {
      await expectLater(
        store.resizeAsset(asset.id, width: w, height: h),
        throwsA(isA<LibraryException>()),
      );
    }
    await expectLater(
      store.resizeAsset(asset.id, width: 80, height: 40),
      throwsA(
        isA<LibraryException>().having(
          (e) => e.message,
          'message',
          'Choose a size smaller than the original.',
        ),
      ),
    );
    final unchanged = (await store.assets()).single;
    expect(unchanged.contentHash, asset.contentHash);
    expect(await store.trashFiles(), isEmpty);
  });

  group('recovery', () {
    late LibraryAsset asset;
    late Uint8List newBytes;
    late String root;
    late Map<String, Object?> journal;
    setUp(() async {
      asset = await importBytes('photo.png', img.encodePng(gradient(40, 20)));
      newBytes = img.encodePng(
        img.copyResize(gradient(40, 20), width: 20, height: 10),
      );
      root = store.root;
      journal = {
        'operation': 'resize',
        'id': asset.id,
        'old_relative_path': asset.relativePath,
        'old_sha256': asset.contentHash,
        'relative_path': asset.relativePath,
        'sha256': sha256.convert(newBytes).toString(),
        'width': 20,
        'height': 10,
        'byte_size': newBytes.length,
        'media_type': 'image/png',
        'original_filename': 'photo.png',
        'trash_path': 'staging/trash/${asset.id}/photo.png',
      };
      await store.close();
    });

    Future<void> writeJournal() => File(
      '$root/staging/resize-${asset.id}.json',
    ).writeAsString(jsonEncode(journal));

    Future<void> expectResized() async {
      store = await LibraryStore.open(root);
      final recovered = (await store.assets()).single;
      expect([recovered.width, recovered.height], [20, 10]);
      expect(recovered.contentHash, journal['sha256']);
      expect(recovered.byteSize, newBytes.length);
      expect(await File('$root/${asset.relativePath}').readAsBytes(), newBytes);
      expect(await store.trashFiles(), hasLength(1));
      expect(Directory('$root/staging').listSync().whereType<File>(), isEmpty);
    }

    test('completes a resize interrupted before files moved', () async {
      await File(
        '$root/staging/resize-${asset.id}.part',
      ).writeAsBytes(newBytes);
      await writeJournal();
      await expectResized();
    });

    test('completes a resize interrupted before the catalog update', () async {
      final trashed = File('$root/${journal['trash_path']}');
      await trashed.parent.create(recursive: true);
      await File('$root/${asset.relativePath}').rename(trashed.path);
      await File('$root/${asset.relativePath}').writeAsBytes(newBytes);
      await writeJournal();
      await expectResized();
    });

    test('rolls back a resize whose new bytes never arrived', () async {
      await File(
        '$root/staging/resize-${asset.id}.part',
      ).writeAsBytes(newBytes.sublist(0, 10));
      await writeJournal();
      store = await LibraryStore.open(root);
      final kept = (await store.assets()).single;
      expect(kept.contentHash, asset.contentHash);
      expect([kept.width, kept.height], [40, 20]);
      expect(kept.missing, isFalse);
      expect(await store.trashFiles(), isEmpty);
      expect(Directory('$root/staging').listSync().whereType<File>(), isEmpty);
    });
  });
}
