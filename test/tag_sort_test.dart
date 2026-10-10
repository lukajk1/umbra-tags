import 'dart:convert';
import 'dart:io';

import 'package:flutter_gallery_test/ml/tag_sort.dart';
import 'package:flutter_gallery_test/storage/embedding_repository.dart';
import 'package:flutter_gallery_test/storage/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Shared with umbra-tags-ml/tests/test_tag_sort.py; keep both identical.
Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/tag_sort_spec.json').readAsStringSync())
        as Map<String, dynamic>;

List<double>? _vector(Object? raw) =>
    raw == null ? null : [for (final v in raw as List) (v as num).toDouble()];

void main() {
  group('scoring spec', () {
    test('constants match the shared fixture', () {
      final fixture = _fixture();
      final constants = fixture['constants'] as Map;
      expect(fixture['spec'], tagSortSpecVersion);
      expect(constants['NEIGHBOURS'], tagSortNeighbours);
      expect(constants['NEIGHBOUR_TEMPERATURE'], tagSortNeighbourTemperature);
      expect(constants['CENTROID_TEMPERATURE'], tagSortCentroidTemperature);
      expect(constants['NAME_TEMPERATURE'], tagSortNameTemperature);
      expect(constants['KNN_WEIGHT'], tagSortKnnWeight);
      expect(constants['NAME_WEIGHT'], tagSortNameWeight);
    });

    for (final raw in _fixture()['cases'] as List) {
      final scenario = raw as Map;
      test('reproduces the Python reference: ${scenario['name']}', () {
        final index = TagSortIndex([
          for (final c in scenario['candidates'] as List)
            TagSortCandidate(
              nameVector: _vector(c['nameVector']),
              members: [
                for (final m in c['members'] as List)
                  (m['id'] as String, _vector(m['vector'])!),
              ],
            ),
        ]);
        final scores = index.score(
          _vector(scenario['image'])!,
          excludeId: scenario['excludeId'] as String?,
        );
        final expected = scenario['expected'] as List;
        expect(scores, hasLength(expected.length));
        for (var j = 0; j < scores.length; j++) {
          final actual = scores[j].toMap();
          for (final MapEntry(:key, :value) in (expected[j] as Map).entries) {
            expect(
              actual[key],
              closeTo((value as num).toDouble(), 1e-9),
              reason: 'candidate $j $key',
            );
          }
        }
      });
    }

    test('examples outweigh a misleading name', () {
      final scores = combineTagSort(
        nameCos: [0.05, 0.08],
        centroidCos: [0.9, 0.5],
        neighbours: [
          (0.92, {0}),
          (0.9, {0}),
          (0.6, {1}),
        ],
      );
      expect(scores[0].confidence, greaterThan(scores[1].confidence));
      expect(scores[1].name, greaterThan(scores[0].name));
      expect(scores[0].confidence + scores[1].confidence, closeTo(1, 1e-12));
      expect([for (final s in scores) s.votes], [2, 1]);
    });

    test('without examples the name decides; with nothing, zeros', () {
      final named = combineTagSort(
        nameCos: [0.10, 0.12],
        centroidCos: [null, null],
        neighbours: const [],
      );
      expect(named[1].confidence, greaterThan(named[0].confidence));
      final none = combineTagSort(
        nameCos: [null],
        centroidCos: [null],
        neighbours: const [],
      );
      expect(none.single.confidence, 0);
    });
  });

  group('sortScores operation', () {
    late Database db;
    late EmbeddingRepository repository;
    const key = 'siglip';

    void tag(String id, {String? parent, bool reference = false}) => db.execute(
      'INSERT INTO tags(id,name,parent_id,excluded_from_all) VALUES (?,?,?,?)',
      [id, id, parent, reference ? 1 : 0],
    );

    void asset(
      String id,
      List<double>? vector, {
      List<String> tags = const [],
      bool archived = false,
    }) {
      final hash = id.hashCode.toRadixString(16).padLeft(64, '0');
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
      for (final t in tags) {
        db.execute('INSERT INTO asset_tags VALUES (?,?)', [id, t]);
      }
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

    Map<String, List<Map>?> scores(
      List<String> candidates,
      List<String> assets, {
      Map<String, List<double>> names = const {},
      String? session,
    }) =>
        (repository.dispatch({
                  'op': 'sortScores',
                  'key': key,
                  'session': session,
                  'candidates': [
                    for (final c in candidates)
                      {'id': c, 'nameVector': names[c]},
                  ],
                  'assetIds': assets,
                })
                as Map)
            .map(
              (id, rows) =>
                  MapEntry(id as String, (rows as List?)?.cast<Map>()),
            );

    setUp(() {
      db = sqlite3.openInMemory()..execute(createSchema);
      repository = EmbeddingRepository(db);
      repository.dispatch({'op': 'sortEnd'});
      // weapon ⊃ sword; armor is a reference tag.
      tag('weapon');
      tag('sword', parent: 'weapon');
      tag('armor', reference: true);
      asset('w1', [1, 0.1, 0], tags: ['weapon']);
      asset('w2', [1, 0, 0.1], tags: ['sword']); // counts for weapon
      asset('a1', [0, 1, 0.1], tags: ['armor']);
      asset('a2', [0.1, 1, 0], tags: ['armor']);
      asset('old', [1, 0, 0], tags: ['armor'], archived: true);
    });

    tearDown(() => db.close());

    test('ranks top-level tags from the images already in them', () {
      asset('new', [0.95, 0.2, 0]);
      asset('blank', null);
      final result = scores(['weapon', 'armor'], ['new', 'blank']);
      expect(result['blank'], isNull);
      final rows = result['new']!;
      expect([for (final r in rows) r['tagId']], ['weapon', 'armor']);
      expect(rows.first['members'], 2); // w1 plus w2 from the child tag
      expect(rows.last['members'], 2); // archived images do not count
      expect(rows.first['votes'], 2);
      expect(rows.first['confidence'] as double, greaterThan(0.9));
      final total = rows.fold<double>(
        0,
        (s, r) => s + (r['confidence'] as double),
      );
      expect(total, closeTo(1, 1e-9));
    });

    test('narrows a tag into its children', () {
      tag('axe', parent: 'weapon');
      asset('x1', [0.6, 0, 1], tags: ['axe']);
      asset('mystery', [0.7, 0, 0.9], tags: ['weapon']);
      final rows = scores(['sword', 'axe'], ['mystery'])['mystery']!;
      expect(rows.first['tagId'], 'axe');
    });

    test('newly sorted images count on the next request of a session', () {
      tag('shield');
      asset('s1', [0, 0.2, 1], tags: ['shield']);
      asset('q1', [0, 0.1, 1]);
      asset('q2', [0, 0.15, 1]);
      final before = scores(
        ['weapon', 'shield'],
        ['q2'],
        session: 'one',
      )['q2']!.firstWhere((r) => r['tagId'] == 'shield');
      db.execute("INSERT INTO asset_tags VALUES ('q1','shield')");
      final after = scores(
        ['weapon', 'shield'],
        ['q2'],
        session: 'one',
      )['q2']!.firstWhere((r) => r['tagId'] == 'shield');
      expect(before['members'], 1);
      expect(after['members'], 2);
    });

    test('the image never counts as its own example', () {
      final rows = scores(['weapon', 'armor'], ['w1'])['w1']!;
      expect(rows.firstWhere((r) => r['tagId'] == 'weapon')['members'], 1);
    });

    test('tags without images rank by name alone', () {
      tag('helmet');
      asset('h', [0.2, 0.2, 1]);
      final rows = scores(
        ['helmet'],
        ['h'],
        names: {
          'helmet': [0.2, 0.2, 1],
        },
      )['h']!;
      expect(rows.single['members'], 0);
      expect(rows.single['confidence'], closeTo(1, 1e-12));
      expect(rows.single['name'], closeTo(1, 1e-12));
    });
  });
}
