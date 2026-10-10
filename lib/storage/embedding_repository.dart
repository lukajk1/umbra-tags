import 'dart:math' as math;
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';

import '../ml/tag_sort.dart';

/// Runs only in the library isolate, alongside all other catalog mutations.
class EmbeddingRepository {
  EmbeddingRepository(this.db);
  final Database db;

  Object? dispatch(Map args) {
    final key = args['key'] as String? ?? '';
    switch (args['op']) {
      case 'vector':
        final rows = db.select(
          """SELECT e.vector FROM embeddings e JOIN assets a ON a.id=e.asset_id
          WHERE e.asset_id=? AND e.model_key=? AND e.analyzed_sha256=a.sha256 AND e.vector IS NOT NULL""",
          [args['assetId'], key],
        );
        if (rows.isEmpty) return null;
        final data = ByteData.sublistView(rows.first['vector'] as Uint8List);
        return List<double>.generate(
          data.lengthInBytes ~/ 4,
          (i) => data.getFloat32(i * 4, Endian.little),
        );
      case 'register':
        db.execute(
          '''INSERT OR IGNORE INTO embedding_models
          (model_key,model_id,revision,preprocessing,dimension) VALUES (?,?,?,?,?)''',
          [
            key,
            args['modelId'],
            args['revision'],
            args['preprocessing'],
            args['dimension'],
          ],
        );
        return null;
      case 'settings':
        if (args['enabled'] is bool) {
          db.execute(
            'INSERT OR REPLACE INTO similarity_settings(id,enabled) VALUES (1,?)',
            [args['enabled'] == true ? 1 : 0],
          );
        }
        return db
                .select('SELECT enabled FROM similarity_settings WHERE id=1')
                .first['enabled'] ==
            1;
      case 'state':
        final rows = db.select(
          '''SELECT COUNT(*) AS total,
          COALESCE(SUM(e.vector IS NOT NULL),0) AS ready,
          COALESCE(SUM(e.error IS NOT NULL),0) AS failed
          FROM assets a LEFT JOIN embeddings e ON e.asset_id=a.id
          AND e.model_key=? AND e.analyzed_sha256=a.sha256
          WHERE a.archived=0 AND a.missing=0''',
          [key],
        );
        return Map<String, Object?>.from(rows.first);
      case 'next':
        final rows = db.select(
          '''SELECT a.* FROM assets a
          LEFT JOIN embeddings e ON e.asset_id=a.id AND e.model_key=?
          AND e.analyzed_sha256=a.sha256
          WHERE a.archived=0 AND a.missing=0 AND e.asset_id IS NULL
          ORDER BY a.imported_at DESC,a.id LIMIT 1''',
          [key],
        );
        return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
      case 'has':
        return db
            .select(
              '''SELECT 1 FROM embeddings e JOIN assets a ON a.id=e.asset_id
          WHERE a.id=? AND e.model_key=? AND e.analyzed_sha256=a.sha256
          AND e.vector IS NOT NULL''',
              [args['assetId'], key],
            )
            .isNotEmpty;
      case 'save':
        final rows = db.select('SELECT sha256 FROM assets WHERE id=?', [
          args['assetId'],
        ]);
        // A deletion or content change during inference must not resurrect data.
        if (rows.isEmpty || rows.first['sha256'] != args['hash']) return false;
        final raw = args['vector'] as List?;
        Uint8List? bytes;
        if (raw != null) {
          if (raw.isEmpty || raw.length > 16384) {
            throw StateError('Invalid embedding dimension.');
          }
          final values = raw.map((v) => (v as num).toDouble()).toList();
          if (values.any((v) => !v.isFinite)) {
            throw StateError('Invalid embedding value.');
          }
          final norm = math.sqrt(values.fold<double>(0, (s, v) => s + v * v));
          if (norm <= 0) throw StateError('Empty embedding.');
          final data = ByteData(values.length * 4);
          for (var i = 0; i < values.length; i++) {
            data.setFloat32(i * 4, values[i] / norm, Endian.little);
          }
          bytes = data.buffer.asUint8List();
        }
        if (key.isEmpty || (bytes == null && args['error'] == null)) {
          throw StateError('Incomplete embedding result.');
        }
        db.execute(
          '''INSERT OR REPLACE INTO embeddings
          (asset_id,model_key,analyzed_sha256,dimension,vector,error,created_at)
          VALUES (?,?,?,?,?,?,?)''',
          [
            args['assetId'],
            key,
            args['hash'],
            raw?.length,
            bytes,
            bytes == null ? args['error'].toString() : null,
            DateTime.now().toUtc().millisecondsSinceEpoch,
          ],
        );
        return true;
      case 'retry':
        db.execute(
          'DELETE FROM embeddings WHERE model_key=? AND error IS NOT NULL',
          [key],
        );
        return null;
      case 'errors':
        return db
            .select(
              '''SELECT a.original_filename,e.error FROM embeddings e
          JOIN assets a ON a.id=e.asset_id WHERE e.model_key=? AND e.error IS NOT NULL
          AND e.analyzed_sha256=a.sha256 ORDER BY e.created_at DESC LIMIT 100''',
              [key],
            )
            .map((r) => Map<String, Object?>.from(r))
            .toList();
      case 'searchVector':
        // Text-to-image search: every indexed image ranked by cosine
        // similarity to a query vector. Returns ids and scores only.
        final raw = (args['vector'] as List)
            .map((v) => (v as num).toDouble())
            .toList();
        if (raw.isEmpty || raw.length > 16384 || raw.any((v) => !v.isFinite)) {
          throw StateError('Invalid query vector.');
        }
        final norm = math.sqrt(raw.fold<double>(0, (s, v) => s + v * v));
        if (norm <= 0) throw StateError('Empty query vector.');
        final query = [for (final v in raw) v / norm];
        final limit = (args['limit'] as int?) ?? 100;
        final scored = <(String, double)>[];
        final statement = db.prepare(
          '''SELECT a.id,e.vector FROM assets a JOIN embeddings e ON e.asset_id=a.id
          WHERE e.model_key=? AND e.analyzed_sha256=a.sha256 AND e.dimension=?
          AND e.vector IS NOT NULL AND a.archived=0 AND a.missing=0''',
        );
        try {
          final cursor = statement.selectCursor([key, query.length]);
          while (cursor.moveNext()) {
            final row = cursor.current;
            final vector = ByteData.sublistView(row['vector'] as Uint8List);
            var score = 0.0;
            for (var i = 0; i < query.length; i++) {
              score += query[i] * vector.getFloat32(i * 4, Endian.little);
            }
            scored.add((row['id'] as String, score.clamp(-1.0, 1.0)));
          }
        } finally {
          statement.close();
        }
        scored.sort((a, b) => b.$2.compareTo(a.$2));
        return [
          for (final (id, score) in scored.take(limit))
            <String, Object?>{'id': id, 'score': score},
        ];
      case 'sortScores':
        return _sortScores(key, args);
      case 'sortEnd':
        _sortSession = null;
        _sortVectors.clear();
        return null;
      case 'search':
        final source = db.select(
          '''SELECT e.vector,e.dimension FROM embeddings e
          JOIN assets a ON a.id=e.asset_id WHERE a.id=? AND e.model_key=?
          AND e.analyzed_sha256=a.sha256 AND e.vector IS NOT NULL''',
          [args['assetId'], key],
        );
        if (source.isEmpty) return <Map<String, Object?>>[];
        final dimension = source.first['dimension'] as int;
        final query = ByteData.sublistView(source.first['vector'] as Uint8List);
        final result = <Map<String, Object?>>[];
        final statement = db.prepare(
          '''SELECT a.*,e.vector FROM assets a JOIN embeddings e ON e.asset_id=a.id
          WHERE e.model_key=? AND e.analyzed_sha256=a.sha256 AND e.dimension=?
          AND e.vector IS NOT NULL AND a.id!=? AND a.archived=0 AND a.missing=0''',
        );
        try {
          final cursor = statement.selectCursor([
            key,
            dimension,
            args['assetId'],
          ]);
          while (cursor.moveNext()) {
            final row = cursor.current;
            final vector = ByteData.sublistView(row['vector'] as Uint8List);
            var score = 0.0;
            for (var i = 0; i < dimension; i++) {
              score +=
                  query.getFloat32(i * 4, Endian.little) *
                  vector.getFloat32(i * 4, Endian.little);
            }
            if (result.length < 50 ||
                score > (result.last['score'] as double)) {
              final item = Map<String, Object?>.from(row)..remove('vector');
              item['score'] = score.clamp(-1.0, 1.0);
              result.add(item);
              result.sort(
                (a, b) =>
                    (b['score'] as double).compareTo(a['score'] as double),
              );
              if (result.length > 50) result.removeLast();
            }
          }
        } finally {
          statement.close();
        }
        return result;
    }
    throw StateError('Unknown embedding operation.');
  }

  // One AI sort session's vectors, kept between its per-image requests so
  // each request only re-reads tag membership. Keyed by asset id and hash.
  static String? _sortSession;
  static final _sortVectors = <String, Float32List>{};

  /// Ranks candidate tags for images (see `ml/tag_sort.dart`). Arguments:
  /// `candidates`: [{id: tag id, nameVector: text vector or null}];
  /// `assetIds`: the images to score; optional `session` to reuse vectors.
  /// Members of a candidate are the non-archived images tagged with it or a
  /// descendant, read fresh on every call so newly sorted images count.
  /// Returns {asset id: [score map + tagId, best first]}; an image without
  /// a current embedding maps to null.
  Map<String, Object?> _sortScores(String key, Map args) {
    final session = args['session'] as String?;
    if (session == null || session != _sortSession) {
      _sortVectors.clear();
      _sortSession = session;
    }
    final candidateArgs = (args['candidates'] as List).cast<Map>();
    final candidateIds = [for (final c in candidateArgs) c['id'] as String];
    final assetIds = (args['assetIds'] as List).cast<String>();
    // Each tag's candidates: the candidates it is, or lies beneath.
    final parent = {
      for (final row in db.select('SELECT id,parent_id FROM tags'))
        row['id'] as String: row['parent_id'] as String?,
    };
    final position = {
      for (var j = 0; j < candidateIds.length; j++) candidateIds[j]: j,
    };
    final under = <String, Set<int>>{};
    for (final tag in parent.keys) {
      final found = <int>{};
      final seen = <String>{};
      for (String? at = tag; at != null && seen.add(at); at = parent[at]) {
        if (position[at] case final j?) found.add(j);
      }
      if (found.isNotEmpty) under[tag] = found;
    }
    final membership = <String, Set<int>>{};
    final hashes = <String, String>{};
    for (final row in db.select('''SELECT at.asset_id,at.tag_id,a.sha256
        FROM asset_tags at JOIN assets a ON a.id=at.asset_id
        WHERE a.archived=0''')) {
      final labels = under[row['tag_id']];
      if (labels == null) continue;
      final asset = row['asset_id'] as String;
      (membership[asset] ??= {}).addAll(labels);
      hashes[asset] = row['sha256'] as String;
    }
    for (final row in _select(
      'SELECT id,sha256 FROM assets WHERE id IN',
      assetIds,
    )) {
      hashes[row['id'] as String] = row['sha256'] as String;
    }
    String cacheKey(String asset) => '$key|$asset|${hashes[asset]}';
    final missing = [
      for (final asset in {...membership.keys, ...assetIds})
        if (hashes.containsKey(asset) &&
            !_sortVectors.containsKey(cacheKey(asset)))
          asset,
    ];
    for (final row in _select(
      '''SELECT a.id,e.vector FROM assets a JOIN embeddings e ON e.asset_id=a.id
      WHERE e.model_key=? AND e.analyzed_sha256=a.sha256
      AND e.vector IS NOT NULL AND a.id IN''',
      missing,
      [key],
    )) {
      final bytes = row['vector'] as Uint8List;
      final data = ByteData.sublistView(bytes);
      _sortVectors[cacheKey(row['id'] as String)] = Float32List.fromList([
        for (var i = 0; i < bytes.length ~/ 4; i++)
          data.getFloat32(i * 4, Endian.little),
      ]);
    }
    final members = [
      for (var j = 0; j < candidateIds.length; j++) <(String, List<double>)>[],
    ];
    int? dimension;
    for (final MapEntry(key: asset, value: labels) in membership.entries) {
      final vector = _sortVectors[cacheKey(asset)];
      if (vector == null) continue;
      dimension ??= vector.length;
      if (vector.length != dimension) continue;
      for (final j in labels) {
        members[j].add((asset, vector));
      }
    }
    List<double>? nameVector(Object? raw) {
      if (raw is! List || raw.isEmpty) return null;
      final values = [for (final v in raw) (v as num).toDouble()];
      if (values.any((v) => !v.isFinite)) {
        throw StateError('Invalid tag name vector.');
      }
      return values;
    }

    final index = TagSortIndex([
      for (var j = 0; j < candidateIds.length; j++)
        TagSortCandidate(
          nameVector: nameVector(candidateArgs[j]['nameVector']),
          members: members[j],
        ),
    ]);
    final result = <String, Object?>{};
    for (final asset in assetIds) {
      final vector = hashes.containsKey(asset)
          ? _sortVectors[cacheKey(asset)]
          : null;
      if (vector == null ||
          (dimension != null && vector.length != dimension) ||
          index.candidates.any(
            (c) =>
                c.nameVector != null && c.nameVector!.length != vector.length,
          )) {
        result[asset] = null;
        continue;
      }
      final scores = index.score(vector, excludeId: asset);
      // Best first; equal confidences keep candidate order.
      final order = List.generate(scores.length, (j) => j)
        ..sort((a, b) {
          final by = scores[b].confidence.compareTo(scores[a].confidence);
          return by != 0 ? by : a.compareTo(b);
        });
      result[asset] = [
        for (final j in order) {...scores[j].toMap(), 'tagId': candidateIds[j]},
      ];
    }
    return result;
  }

  /// Runs `[sql] (?,?,…)` for [ids] in chunks under SQLite's variable limit.
  Iterable<Row> _select(
    String sql,
    List<String> ids, [
    List<Object?> leading = const [],
  ]) sync* {
    for (var start = 0; start < ids.length; start += 500) {
      final chunk = ids.skip(start).take(500).toList();
      yield* db.select('$sql (${List.filled(chunk.length, '?').join(',')})', [
        ...leading,
        ...chunk,
      ]);
    }
  }
}
