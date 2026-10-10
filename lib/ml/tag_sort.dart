import 'dart:math' as math;
import 'dart:typed_data';

/// Scoring for "AI sort into existing tags": ranks candidate tags (the
/// top-level tags, or one tag's children) for an image from two signals:
///
/// * examples: the images already in each candidate's subtree, as a soft
///   k-nearest-neighbour vote blended with a softmax over the cosine to each
///   candidate's centroid;
/// * name: the SigLIP 2 text-image cosine for the tag name.
///
/// Each signal becomes a distribution over the candidates, so their different
/// scales (image-image cosine ~0.4–0.95, text-image ~0.0–0.2) never meet.
///
/// MIRRORS umbra-tags-ml/tag_sort.py, where `evaluate_tag_sort.py` measured
/// these constants on a real library. Change both together:
/// test/fixtures/tag_sort_spec.json (identical in both repos) pins outputs.
const tagSortSpecVersion = 1;

/// Labelled images that vote.
const tagSortNeighbours = 10;

/// A neighbour's vote weighs exp((cosine - 1) / T).
const tagSortNeighbourTemperature = 0.05;
const tagSortCentroidTemperature = 0.03;
const tagSortNameTemperature = 0.01;

/// examples = w·kNN + (1-w)·centroid.
const tagSortKnnWeight = 0.5;

/// confidence = (examples + w·name) / (1 + w).
const tagSortNameWeight = 0.2;

/// One candidate's result. Shares are in [0, 1] and sum to 1 over the
/// candidates (all zero when nothing is known).
class TagSortScore {
  const TagSortScore({
    required this.confidence,
    required this.example,
    required this.knn,
    required this.centroid,
    required this.name,
    required this.votes,
    required this.neighbours,
    required this.members,
  });

  final double confidence, example, knn, centroid, name;

  /// Nearest labelled images that belong to the candidate.
  final int votes;

  /// Nearest labelled images that voted, over all candidates.
  final int neighbours;

  /// Labelled images in the candidate, excluding the image itself.
  final int members;

  Map<String, Object?> toMap() => {
    'confidence': confidence,
    'example': example,
    'knn': knn,
    'centroid': centroid,
    'name': name,
    'votes': votes,
    'neighbours': neighbours,
    'members': members,
  };
}

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

List<double> _unit(List<double> vector) {
  final norm = math.sqrt(_dot(vector, vector));
  if (!(norm > 0) || !norm.isFinite) {
    throw StateError('Vector must be finite and non-zero.');
  }
  return [for (final v in vector) v / norm];
}

/// Softmax over the non-null values; null stays 0. All null gives zeros.
List<double> tagSortSoftmax(List<double?> values, double temperature) {
  final present = values.whereType<double>();
  if (present.isEmpty) return List.filled(values.length, 0.0);
  final top = present.reduce(math.max);
  final weights = [
    for (final v in values) v == null ? 0.0 : math.exp((v - top) / temperature),
  ];
  final total = weights.fold<double>(0, (s, w) => s + w);
  return [for (final w in weights) w / total];
}

/// Ranks candidates from precomputed similarities. [nameCos] and
/// [centroidCos] hold null where a candidate has no name vector or no
/// members; [neighbours] are the [tagSortNeighbours] most similar labelled
/// images with the candidate indices each belongs to.
List<TagSortScore> combineTagSort({
  required List<double?> nameCos,
  required List<double?> centroidCos,
  required List<(double, Set<int>)> neighbours,
  List<int>? members,
}) {
  final count = centroidCos.length;
  final mass = List.filled(count, 0.0);
  final votes = List.filled(count, 0);
  for (final (cosine, labels) in neighbours) {
    final weight = math.exp((cosine - 1) / tagSortNeighbourTemperature);
    for (final j in labels) {
      mass[j] += weight;
      votes[j]++;
    }
  }
  final total = mass.fold<double>(0, (s, m) => s + m);
  final centroid = tagSortSoftmax(centroidCos, tagSortCentroidTemperature);
  final name = tagSortSoftmax(nameCos, tagSortNameTemperature);
  final hasExamples = centroidCos.any((c) => c != null);
  final hasNames = nameCos.any((n) => n != null);
  return [
    for (var j = 0; j < count; j++)
      () {
        final knn = total > 0 ? mass[j] / total : 0.0;
        final example =
            tagSortKnnWeight * knn + (1 - tagSortKnnWeight) * centroid[j];
        return TagSortScore(
          confidence: hasExamples && hasNames
              ? (example + tagSortNameWeight * name[j]) /
                    (1 + tagSortNameWeight)
              : hasExamples
              ? example
              : name[j],
          example: example,
          knn: knn,
          centroid: centroid[j],
          name: name[j],
          votes: votes[j],
          neighbours: neighbours.length,
          members: members?[j] ?? 0,
        );
      }(),
  ];
}

/// A candidate tag: its name's text vector (null when unavailable) and the
/// labelled images in its subtree as (asset id, unit vector).
class TagSortCandidate {
  const TagSortCandidate({this.nameVector, this.members = const []});
  final List<double>? nameVector;
  final List<(String, List<double>)> members;
}

/// Precomputes centroid sums and the neighbour pool once for many images.
class TagSortIndex {
  TagSortIndex(this.candidates) {
    final pool = <String, (List<double>, Set<int>)>{};
    for (var j = 0; j < candidates.length; j++) {
      final candidate = candidates[j];
      _names.add(
        candidate.nameVector == null ? null : _unit(candidate.nameVector!),
      );
      Float64List? sum;
      for (final (id, vector) in candidate.members) {
        sum ??= Float64List(vector.length);
        for (var i = 0; i < vector.length; i++) {
          sum[i] += vector[i];
        }
        pool.putIfAbsent(id, () => (vector, <int>{})).$2.add(j);
      }
      _sums.add(sum);
    }
    _pool = pool.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  }

  final List<TagSortCandidate> candidates;
  final _names = <List<double>?>[];
  final _sums = <Float64List?>[];
  late final List<MapEntry<String, (List<double>, Set<int>)>> _pool;

  /// Scores [image] against every candidate. Members equal to [excludeId]
  /// (the image itself) are ignored. Neighbour ties break by asset id.
  List<TagSortScore> score(List<double> image, {String? excludeId}) {
    final x = _unit(image);
    final nameCos = <double?>[
      for (final name in _names) name == null ? null : _dot(x, name),
    ];
    final centroidCos = <double?>[];
    final members = <int>[];
    for (var j = 0; j < candidates.length; j++) {
      var count = 0;
      List<double>? excluded;
      for (final (id, vector) in candidates[j].members) {
        if (id == excludeId) {
          excluded = vector;
        } else {
          count++;
        }
      }
      members.add(count);
      final sum = _sums[j];
      if (sum == null || count == 0) {
        centroidCos.add(null);
        continue;
      }
      var dot = 0.0, norm = 0.0;
      for (var i = 0; i < sum.length; i++) {
        final v = sum[i] - (excluded?[i] ?? 0);
        dot += x[i] * v;
        norm += v * v;
      }
      centroidCos.add(norm > 0 ? dot / math.sqrt(norm) : null);
    }
    // Top neighbours by cosine, then id; the pool is sorted by id, so a
    // strict comparison keeps the earlier id on ties.
    final top = <(double, String, Set<int>)>[];
    for (final entry in _pool) {
      if (entry.key == excludeId) continue;
      final cosine = _dot(x, entry.value.$1);
      if (top.length == tagSortNeighbours && cosine <= top.last.$1) continue;
      var at = top.length;
      while (at > 0 && cosine > top[at - 1].$1) {
        at--;
      }
      top.insert(at, (cosine, entry.key, entry.value.$2));
      if (top.length > tagSortNeighbours) top.removeLast();
    }
    return combineTagSort(
      nameCos: nameCos,
      centroidCos: centroidCos,
      neighbours: [for (final (cosine, _, labels) in top) (cosine, labels)],
      members: members,
    );
  }
}
