import 'classifier.dart';
import '../storage/library_store.dart';

class TagSuggestion {
  const TagSuggestion(this.label, this.score);
  final String label;
  final double score;
}

class TagSuggestionModel {
  TagSuggestionModel(Map<String, dynamic> data)
    : id = data['modelId'] as String,
      version = data['modelVersion'] as String,
      compatibleEmbeddingKey = data['compatibleEmbeddingKey'] as String?;
  final String id, version;
  final String? compatibleEmbeddingKey;
}

/// A search query embedded by the text encoder, comparable with stored image
/// vectors whose model key is [embeddingKey].
class TextQueryVector {
  const TextQueryVector(this.vector, this.embeddingKey);
  final List<double> vector;
  final String? embeddingKey;
}

/// Suggestions are advisory. Callers decide what to accept and persist.
/// A backend may rank candidate labels or generate its own labels.
abstract interface class TagSuggester {
  Future<TagSuggestionModel> info();
  Future<void> load();
  Future<List<TagSuggestion>> suggest({
    required LibraryAsset asset,
    required String imagePath,
    required List<String> candidates,
    bool includeDefaults = true,
    String? embeddingKey,
    List<double>? vector,
  });

  /// Embeds [text] into the image embedding space for text-to-image search.
  Future<TextQueryVector> embedText(String text);
  Future<void> dispose();
}

class PythonTagSuggester implements TagSuggester {
  PythonTagSuggester({String? home, String? python})
    : _transport = PythonImageClassifier(home: home, python: python);
  final PythonImageClassifier _transport;
  @override
  Future<TagSuggestionModel> info() async =>
      TagSuggestionModel(await _transport.requestTags('info'));
  @override
  Future<void> load() async {
    await _transport.requestTags('load');
  }

  @override
  Future<List<TagSuggestion>> suggest({
    required LibraryAsset asset,
    required String imagePath,
    required List<String> candidates,
    bool includeDefaults = true,
    String? embeddingKey,
    List<double>? vector,
  }) async {
    final expected = await info();
    final data = await _transport.requestTags('suggest', {
      'assetId': asset.id,
      'contentHash': asset.contentHash,
      'imagePath': imagePath,
      'candidates': candidates,
      'includeDefaults': includeDefaults,
      'embeddingKey': embeddingKey,
      'vector': vector,
    });
    if (data['assetId'] != asset.id ||
        data['contentHash'] != asset.contentHash ||
        data['modelVersion'] != expected.version) {
      throw StateError('Tag suggestions do not match this image or model.');
    }
    final result = <TagSuggestion>[];
    final seen = <String>{};
    for (final row in data['suggestions'] as List) {
      final name = (row['label'] as String).trim();
      final score = (row['score'] as num).toDouble();
      if (name.isEmpty || name.length > 120 || !score.isFinite) {
        throw StateError('Invalid tag suggestion returned by model.');
      }
      if (seen.add(name.toLowerCase())) result.add(TagSuggestion(name, score));
    }
    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  @override
  Future<TextQueryVector> embedText(String text) async {
    final data = await _transport.requestTags('embedText', {'text': text});
    final raw = data['vector'];
    if (raw is! List || raw.isEmpty) {
      throw StateError('The text encoder returned no vector.');
    }
    final vector = [for (final value in raw) (value as num).toDouble()];
    if (vector.any((value) => !value.isFinite)) {
      throw StateError('The text encoder returned an invalid vector.');
    }
    return TextQueryVector(vector, data['compatibleEmbeddingKey'] as String?);
  }

  @override
  Future<void> dispose() => _transport.dispose();
}
