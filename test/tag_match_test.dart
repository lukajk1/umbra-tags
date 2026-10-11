import 'dart:convert';
import 'dart:io';

import 'package:flutter_gallery_test/ml/tag_match.dart';
import 'package:flutter_gallery_test/storage/embedding_repository.dart';
import 'package:flutter_gallery_test/storage/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Shared with umbra-tags-ml/tests/test_tag_match.py; keep both identical.
Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/tag_match_spec.json').readAsStringSync())
        as Map<String, dynamic>;

List<double>? _vector(Object? raw) =>
    raw == null ? null : [for (final v in raw as List) (v as num).toDouble()];

void _expectList(List<double>? actual, Object? expected, String reason) {
  if (expected == null) {
    expect(actual, isNull, reason: reason);
    return;
  }
  final values = expected as List;
  expect(actual, hasLength(values.length), reason: reason);
  for (var i = 0; i < values.length; i++) {
    expect(
      actual![i],
      closeTo((values[i] as num).toDouble(), 1e-9),
      reason: '$reason[$i]',
    );
  }
}

void main() {
  group('scoring spec', () {
    test('constants match the shared fixture', () {
      final fixture = _fixture();
      final constants = fixture['constants'] as Map;
      expect(fixture['spec'], tagMatchSpecVersion);
      expect(constants['TOP_K'], tagMatchTopK);
      expect(constants['CENTROID_WEIGHT'], tagMatchCentroidWeight);
      expect(constants['MAX_NAME_WEIGHT'], tagMatchMaxNameWeight);
      expect(
        constants['SINGLE_MEMBER_NAME_WEIGHT'],
        tagMatchSingleMemberNameWeight,
      );
      expect(constants['THRESHOLD_QUANTILE'], tagMatchThresholdQuantile);
    });

    for (final raw in _fixture()['cases'] as List) {
      final scenario = raw as Map;
      test('reproduces the Python reference: ${scenario['name']}', () {
        final (result, examples, names) = scoreTagMatch(
          [for (final v in scenario['images'] as List) _vector(v)!],
          [for (final v in scenario['members'] as List) _vector(v)!],
          nameVector: _vector(scenario['nameVector']),
        );
        final expected = scenario['expected'] as Map;
        _expectList(result.scores, expected['scores'], 'scores');
        _expectList(
          result.memberScores,
          expected['memberScores'],
          'memberScores',
        );
        _expectList(examples, expected['examples'], 'examples');
        _expectList(names, expected['names'], 'names');
        for (final (actual, key) in [
          (result.nameWeight, 'nameWeight'),
          (result.threshold, 'threshold'),
        ]) {
          final value = expected[key] as num?;
          expect(
            actual,
            value == null ? isNull : closeTo(value.toDouble(), 1e-9),
            reason: key,
          );
        }
      });
    }

    test('a misleading name gets no weight; a fitting one does', () {
      const examples = [0.9, 0.5, 0.4, 0.3];
      const names = [0.10, 0.05, 0.02, 0.01];
      final misleading = combineTagMatch(
        examples: examples,
        names: names,
        memberExamples: [0.8, 0.7],
        memberNames: [0.0, 0.01],
      );
      expect(misleading.nameWeight, 0);
      expect(misleading.scores, examples);
      final helpful = combineTagMatch(
        examples: examples,
        names: names,
        memberExamples: [0.8, 0.7],
        memberNames: [0.12, 0.09],
      );
      expect(helpful.nameWeight, greaterThan(0));
      expect(helpful.nameWeight, lessThanOrEqualTo(tagMatchMaxNameWeight));
      // The name shifts scores around its mean, keeping cosine units.
      final mean = helpful.scores.reduce((a, b) => a + b) / 4;
      expect(mean, closeTo(0.525, 1e-12));
    });

    test('quantile interpolates like numpy', () {
      expect(tagMatchQuantile([0.3, 0.9, 0.1, 0.5, 0.7], 0.5), 0.5);
      expect(tagMatchQuantile([0.1, 0.2], 0.5), closeTo(0.15, 1e-12));
      expect(tagMatchQuantile([0.4], 0.5), 0.4);
    });
  });

  group('matchScores operation', () {
    late Database db;
    late EmbeddingRepository repository;
    const key = 'siglip';
    final vectors = <String, List<double>>{};

    void tag(String id, {String? parent}) => db.execute(
      'INSERT INTO tags(id,name,parent_id) VALUES (?,?,?)',
      [id, id, parent],
    );

    void asset(
      String id,
      List<double>? vector, {
      List<String> tags = const [],
      bool archived = false,
      bool missing = false,
      String? error,
    }) {
      final hash = id.hashCode.toRadixString(16).padLeft(64, '0');
      db.execute(
        '''INSERT INTO assets (id,relative_path,original_filename,media_type,width,
        height,byte_size,imported_at,sha256,archived,missing) VALUES (?,?,?,?,?,?,?,?,?,?,?)''',
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
          missing ? 1 : 0,
        ],
      );
      for (final t in tags) {
        db.execute('INSERT INTO asset_tags VALUES (?,?)', [id, t]);
      }
      if (vector != null || error != null) {
        if (vector != null) vectors[id] = vector;
        repository.dispatch({
          'op': 'save',
          'key': key,
          'assetId': id,
          'hash': hash,
          'vector': vector,
          'error': error,
        });
      }
    }

    Map match(String tagId, {List<double>? name}) =>
        repository.dispatch({
              'op': 'matchScores',
              'key': key,
              'tagId': tagId,
              'nameVector': name,
            })
            as Map;

    setUp(() {
      vectors.clear();
      db = sqlite3.openInMemory()..execute(createSchema);
      repository = EmbeddingRepository(db);
      // weapon ⊃ sword.
      tag('weapon');
      tag('sword', parent: 'weapon');
      tag('armor');
      asset('w1', [1, 0.1, 0], tags: ['weapon']);
      asset('w2', [1, 0, 0.1], tags: ['sword']); // counts for weapon
      asset('w3', [0.9, 0.2, 0.1], tags: ['weapon'], missing: true);
      asset('old', [0, 0, 1], tags: ['weapon'], archived: true);
      asset('a1', [0, 1, 0.1], tags: ['armor']);
      asset('near', [0.95, 0.15, 0]);
      asset('far', [0, 0.9, 0.3]);
      asset('mid', [0.5, 0.5, 0.2]);
      asset('gone', [1, 0, 0], missing: true);
      asset('hidden', [1, 0, 0], archived: true);
      asset('blank', null);
      asset('broken', null, error: 'decode failed');
    });

    tearDown(() => db.close());

    test('scores images outside the tag by its images, in one pass', () {
      final result = match('weapon');
      final scores = (result['scores'] as Map).cast<String, double>();
      // Members (with the child tag and a missing file) are not candidates,
      // nor are missing or archived images.
      expect(scores.keys.toSet(), {'a1', 'near', 'far', 'mid'});
      expect(result['members'], 3); // w1, w2, w3; archived images do not count
      expect(result['nameWeight'], isNull);
      expect(result['unindexed'], ['blank']);
      expect(result['failed'], {'broken': 'decode failed'});
      final ranked = scores.keys.toList()
        ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
      expect(ranked.take(2), ['near', 'mid']);
      // Same as the spec on the same vectors (stored as float32).
      final (expected, _, _) = scoreTagMatch(
        [
          for (final id in ['a1', 'far', 'mid', 'near']) vectors[id]!,
        ],
        [
          for (final id in ['w1', 'w2', 'w3']) vectors[id]!,
        ],
      );
      for (final (i, id) in ['a1', 'far', 'mid', 'near'].indexed) {
        expect(scores[id], closeTo(expected.scores[i], 1e-5));
      }
      expect(result['threshold'], closeTo(expected.threshold!, 1e-5));
    });

    test('adds the tag name with an adaptive weight', () {
      final result = match('weapon', name: [1, 0.1, 0.05]);
      expect(result['nameWeight'] as double, greaterThan(0));
      final scores = (result['scores'] as Map).cast<String, double>();
      expect(scores['near']!, greaterThan(scores['far']!));
      // A name that points away from the tag's images is ignored.
      final misleading = match('weapon', name: [0, 1, 0.3]);
      expect(misleading['nameWeight'], 0);
      expect(misleading['scores'], match('weapon')['scores']);
    });

    test('a tag without indexed images matches by name only', () {
      tag('shield');
      final result = match('shield', name: [0, 1, 0]);
      expect(result['members'], 0);
      expect(result['nameWeight'], isNull);
      expect(result['threshold'], isNull);
      final scores = (result['scores'] as Map).cast<String, double>();
      // Every non-archived, present image with a vector, as a raw cosine.
      expect(scores['a1'], closeTo(1 / 1.00499, 1e-4));
      expect(scores.keys.toSet(), {'w1', 'w2', 'a1', 'near', 'far', 'mid'});
      expect(match('shield')['scores'], isEmpty);
    });
  });
}
