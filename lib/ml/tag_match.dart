import 'dart:math' as math;
import 'dart:typed_data';

/// Scoring for "Find matching images" (one tag, many images). Every image
/// outside the tag is scored from two signals:
///
/// * examples: the images already in the tag or a descendant ("members"):
///   `example = w·cos(x, centroid) + (1-w)·mean of the top-k cos(x, member)`
///   with the centroid the renormalized mean of the members' unit vectors
///   and k capped by the member count;
/// * name: the SigLIP 2 text-image cosine for the tag name.
///
/// Image-image cosines (~0.3–0.95) and text-image cosines (~0.0–0.2) differ
/// in scale, so the name is rescaled to the examples' spread over the scored
/// images: `score = example + w·(sd(example)/sd(name))·(name - mean(name))`.
/// That ranks like z(example) + w·z(name) but stays in cosine units. The
/// name weight w is chosen per tag from the members (d_name / d_example,
/// clamped to [0, [tagMatchMaxNameWeight]]), so a name that does not
/// describe the tag's images is ignored.
///
/// MIRRORS umbra-tags-ml/tag_match.py, where `evaluate_tag_match.py`
/// measured this on a real library. Change both together:
/// test/fixtures/tag_match_spec.json (identical in both repos) pins outputs.
const tagMatchSpecVersion = 1;

/// Nearest members averaged.
const tagMatchTopK = 5;

/// example = w·centroid + (1-w)·top-k mean.
const tagMatchCentroidWeight = 0.5;

/// Cap on the adaptive name weight.
const tagMatchMaxNameWeight = 2.0;

/// Name weight when there is a single member (no leave-one-out possible).
const tagMatchSingleMemberNameWeight = 1.0;

/// The default threshold is this quantile of the members' own scores.
const tagMatchThresholdQuantile = 0.5;

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// The hot loop of a scan: typed lists, so it compiles to plain float math.
double _dot64(Float64List a, Float64List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

Float64List _unit(List<double> vector) {
  final norm = math.sqrt(_dot(vector, vector));
  if (!(norm > 0) || !norm.isFinite) {
    throw StateError('Vector must be finite and non-zero.');
  }
  return Float64List.fromList([for (final v in vector) v / norm]);
}

/// A tag's member vectors, prepared once to score many images.
class TagMatchExamples {
  TagMatchExamples(List<List<double>> members)
    : _members = [for (final m in members) _unit(m)] {
    if (_members.isNotEmpty) {
      _total = Float64List(_members.first.length);
      for (final m in _members) {
        for (var i = 0; i < m.length; i++) {
          _total[i] += m[i];
        }
      }
    }
  }

  final List<Float64List> _members;
  late final Float64List _total;

  int get length => _members.length;

  /// The example score of [image], or null without members.
  double? score(List<double> image) => _score(_unit(image), null);

  /// Each member's leave-one-out score; null with fewer than two members.
  List<double>? memberScores() {
    if (_members.length < 2) return null;
    return [for (var j = 0; j < _members.length; j++) _score(_members[j], j)!];
  }

  double? _score(Float64List x, int? skip) {
    if (_members.length - (skip == null ? 0 : 1) <= 0) return null;
    var dot = 0.0, norm = 0.0;
    final excluded = skip == null ? null : _members[skip];
    for (var i = 0; i < _total.length; i++) {
      final c = _total[i] - (excluded?[i] ?? 0);
      dot += x[i] * c;
      norm += c * c;
    }
    final centroid = norm > 0 ? dot / math.sqrt(norm) : 0.0;
    final k = math.min(tagMatchTopK, _members.length - (skip == null ? 0 : 1));
    // The k largest cosines, kept in descending order.
    final top = <double>[];
    for (var j = 0; j < _members.length; j++) {
      if (j == skip) continue;
      final cosine = _dot64(x, _members[j]);
      if (top.length == k && cosine <= top.last) continue;
      var at = top.length;
      while (at > 0 && cosine > top[at - 1]) {
        at--;
      }
      top.insert(at, cosine);
      if (top.length > k) top.removeLast();
    }
    final mean = top.fold<double>(0, (s, v) => s + v) / k;
    return tagMatchCentroidWeight * centroid +
        (1 - tagMatchCentroidWeight) * mean;
  }
}

/// The scores of a scan; see [combineTagMatch].
class TagMatchResult {
  const TagMatchResult({
    required this.scores,
    this.memberScores,
    this.nameWeight,
    this.threshold,
  });
  final List<double> scores;

  /// The members' leave-one-out scores, in the same units as [scores].
  final List<double>? memberScores;

  /// The adaptive name weight; null when the name is not part of the score.
  final double? nameWeight;

  /// Suggested minimum score: the median member's own score.
  final double? threshold;
}

(double, double) _stats(List<double> values) {
  final mean = values.fold<double>(0, (s, v) => s + v) / values.length;
  final variance =
      values.fold<double>(0, (s, v) => s + (v - mean) * (v - mean)) /
      values.length;
  return (mean, math.sqrt(variance));
}

/// The adaptive name weight (see the library comment).
double tagMatchNameWeight(
  List<double> examples,
  List<double> names,
  List<double>? memberExamples,
  List<double>? memberNames,
) {
  if (examples.length < 2) return 0;
  final (meanE, sdE) = _stats(examples);
  final (meanN, sdN) = _stats(names);
  if (!(sdE > 0) || !(sdN > 0)) return 0;
  if (memberExamples == null || memberNames == null) {
    return tagMatchSingleMemberNameWeight;
  }
  double mean(List<double> v) => v.fold<double>(0, (s, x) => s + x) / v.length;
  final dE = (mean(memberExamples) - meanE) / sdE;
  final dN = (mean(memberNames) - meanN) / sdN;
  if (dN <= 0) return 0;
  if (dE <= 0) return tagMatchMaxNameWeight;
  return math.min(tagMatchMaxNameWeight, dN / dE);
}

/// Linear-interpolation quantile (numpy's default).
double tagMatchQuantile(List<double> values, double q) {
  final sorted = [...values]..sort();
  final at = q * (sorted.length - 1);
  final low = at.floor();
  final high = math.min(low + 1, sorted.length - 1);
  return sorted[low] + (at - low) * (sorted[high] - sorted[low]);
}

/// Final scores from per-image [examples] (null without members) and
/// [names] (null without a name vector), with the members' leave-one-out
/// example scores and name cosines for the name weight and threshold.
TagMatchResult combineTagMatch({
  List<double>? examples,
  List<double>? names,
  List<double>? memberExamples,
  List<double>? memberNames,
}) {
  if (examples == null) {
    if (names == null) throw StateError('Need members or a name vector.');
    return TagMatchResult(scores: [...names]);
  }
  double? weight;
  var scale = 0.0, meanN = 0.0;
  if (names != null) {
    weight = tagMatchNameWeight(examples, names, memberExamples, memberNames);
    if (weight > 0 && examples.length >= 2) {
      final (_, sdE) = _stats(examples);
      final (mean, sdN) = _stats(names);
      meanN = mean;
      scale = sdN > 0 ? weight * sdE / sdN : 0.0;
    }
  }
  double shift(double? name) => name == null ? 0 : scale * (name - meanN);
  final scores = [
    for (var i = 0; i < examples.length; i++) examples[i] + shift(names?[i]),
  ];
  final members = memberExamples == null
      ? null
      : [
          for (var j = 0; j < memberExamples.length; j++)
            memberExamples[j] + shift(memberNames?[j]),
        ];
  return TagMatchResult(
    scores: scores,
    memberScores: members,
    nameWeight: weight,
    threshold: members == null || members.isEmpty
        ? null
        : tagMatchQuantile(members, tagMatchThresholdQuantile),
  );
}

/// Scores [images] for a tag with [members] and an optional [nameVector].
/// Returns the result plus the per-image example scores and name cosines.
(TagMatchResult, List<double>?, List<double>?) scoreTagMatch(
  List<List<double>> images,
  List<List<double>> members, {
  List<double>? nameVector,
}) {
  final index = TagMatchExamples(members);
  final examples = members.isEmpty
      ? null
      : [for (final x in images) index.score(x)!];
  List<double>? names, memberNames;
  if (nameVector != null) {
    final text = _unit(nameVector);
    names = [for (final x in images) _dot(_unit(x), text)];
    memberNames = [for (final m in members) _dot(_unit(m), text)];
  }
  final result = combineTagMatch(
    examples: examples,
    names: names,
    memberExamples: index.memberScores(),
    memberNames: memberNames,
  );
  return (result, examples, names);
}
