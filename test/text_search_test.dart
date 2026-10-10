import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gallery_test/storage/embedding_repository.dart';
import 'package:flutter_gallery_test/storage/schema.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late EmbeddingRepository repository;
  const key = 'siglip';

  void addAsset(String id, List<double>? vector, {bool archived = false}) {
    final hash = id.codeUnits.first.toRadixString(16).padLeft(64, '0');
    db.execute(
      '''INSERT INTO assets (id,relative_path,original_filename,media_type,width,
      height,byte_size,imported_at,sha256,archived) VALUES (?,?,?,?,?,?,?,?,?,?)''',
      [
        id,
        'media/$id.png',
        '$id.png',
        'image/png',
        1,
        1,
        1,
        0,
        hash,
        archived ? 1 : 0,
      ],
    );
    if (vector != null) {
      repository.dispatch({
        'op': 'save',
        'key': key,
        'assetId': id,
        'hash': hash,
        'vector': vector,
      });
    }
  }

  setUp(() {
    db = sqlite3.openInMemory()..execute(createSchema);
    repository = EmbeddingRepository(db);
    repository.dispatch({
      'op': 'register',
      'key': key,
      'modelId': 'test',
      'revision': '1',
      'preprocessing': 'none',
      'dimension': 3,
    });
  });

  tearDown(() => db.close());

  List<Map> search(List<double> vector, {int? limit}) =>
      (repository.dispatch({
                'op': 'searchVector',
                'key': key,
                'vector': vector,
                'limit': ?limit,
              })
              as List)
          .cast<Map>();

  test('ranks indexed images by cosine similarity to the query', () {
    addAsset('city', [1, 0, 0]);
    addAsset('statue', [0, 1, 0]);
    addAsset('mixed', [1, 1, 0]);
    addAsset('unindexed', null);
    addAsset('archived', [1, 0, 0], archived: true);

    // An unnormalized query ranks the same as its unit vector.
    final results = search([4, 0.4, 0]);
    expect([for (final row in results) row['id']], ['city', 'mixed', 'statue']);
    expect(results.first['score'] as double, closeTo(0.995, 0.001));
    expect(results.last['score'] as double, closeTo(0.0995, 0.001));
  });

  test('respects the result limit', () {
    for (var i = 0; i < 5; i++) {
      addAsset(String.fromCharCode(97 + i), [1, i.toDouble(), 0]);
    }
    expect(search([1, 0, 0], limit: 2), hasLength(2));
  });

  test('rejects empty or invalid query vectors', () {
    expect(() => search([]), throwsStateError);
    expect(() => search([0, 0, 0]), throwsStateError);
    expect(() => search([double.nan, 1, 0]), throwsStateError);
  });

  test('stored vectors stay comparable as little-endian float32', () {
    addAsset('x', [0, 0, 2]);
    final stored = db.select('SELECT vector FROM embeddings').first['vector'];
    expect(
      ByteData.sublistView(stored as Uint8List).getFloat32(8, Endian.little),
      1.0,
    );
  });
}
