import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'storage/library_store.dart';
import 'storage/tag_repository.dart';
import 'widgets/tag_widgets.dart';
import 'widgets/tag_match_dialog.dart';
import 'widgets/hierarchy_dialog.dart';
import 'receiver_server.dart';
import 'ml/classifier.dart';
import 'ml/image_embedder.dart';
import 'ml/tag_suggester.dart';
import 'ml/similarity_controller.dart';
import 'widgets/similarity_widgets.dart';
import 'widgets/ml_settings_dialog.dart';
import 'widgets/options_dialog.dart';
import 'widgets/preview_details.dart';
import 'widgets/gallery_drop_target.dart';
import 'widgets/downloads_import_dialog.dart';
import 'widgets/exact_masonry.dart';
import 'widgets/view_breadcrumbs.dart';
import 'widgets/resize_dialog.dart';
import 'widgets/ai_sort_dialog.dart';
import 'theme.dart';
import 'widgets/ambient_glass.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('Umbra Tags');
  await windowManager.setMinimumSize(const Size(1024, 600));
  await windowManager.setPreventClose(true);
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  runApp(const GalleryApp(startReceiver: true));
}

Future<File> _sessionFile() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'Umbra Tags'));
  await dir.create(recursive: true);
  return File(p.join(dir.path, 'flutter-session.json'));
}

Future<Map<String, dynamic>> _loadSession([File? sessionFile]) async {
  try {
    final file = sessionFile ?? await _sessionFile();
    if (await file.exists()) {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
  } catch (_) {}
  return {};
}

Future<void> _saveSession(
  Map<String, dynamic> data, [
  File? sessionFile,
]) async {
  try {
    final file = sessionFile ?? await _sessionFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    // Windows refuses to replace a file another process is reading (e.g. a
    // virus scanner, or a test polling it); retry briefly instead of
    // silently dropping the save.
    for (var attempt = 0; ; attempt++) {
      try {
        await temporary.rename(file.path);
        break;
      } on FileSystemException {
        if (attempt >= 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  } catch (_) {}
}

enum LayoutMode { crop, letterbox, masonry }

double _settingNumber(Object? value, double fallback, double min, double max) =>
    value is num && value.isFinite
    ? value.toDouble().clamp(min, max)
    : fallback;

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key, this.startReceiver = false, this.sessionFile});
  final bool startReceiver;
  final File? sessionFile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umbra Tags',
      theme: buildAppTheme(),
      home: AppShell(startReceiver: startReceiver, sessionFile: sessionFile),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, this.startReceiver = false, this.sessionFile});
  final bool startReceiver;
  final File? sessionFile;
  @override
  Widget build(BuildContext context) =>
      GalleryPage(startReceiver: startReceiver, sessionFile: sessionFile);
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, this.startReceiver = false, this.sessionFile});
  final bool startReceiver;
  final File? sessionFile;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage>
    with WindowListener, tray.TrayListener {
  double _tileSize = 200;
  LayoutMode _layout = LayoutMode.crop;
  double _committedWidth = 0;
  double _pendingWidth = 0;
  Timer? _resizeTimer;
  final Set<String> _selectedPaths = {};
  double _previewWidth = 300;

  /// Tag sidebar width, dragged from its right edge.
  double _sidebarWidth = 220;
  static const _sidebarMinWidth = 160.0, _sidebarMaxWidth = 480.0;
  bool _previewVisible = true;

  // Marquee selection state
  // Alt + left-drag draws a selection box (marquee).
  Offset? _dragStart;
  Offset? _dragCurrent;
  // A plain left-drag starting on a tile drags its files out to other apps.
  Offset? _fileDragOrigin;
  String? _fileDragPath;
  bool _draggingOut = false;
  // Ctrl/Cmd state when the button went down. Tiles also accept double-clicks,
  // so their tap callback runs only after the double-click window, by which
  // time a quick Ctrl-click has usually released the key.
  bool _toggleOnTap = false;
  // Pressing an image that is part of a multi-selection keeps the selection
  // (it may be dragged out); releasing without a drag then selects just it.
  String? _collapseOnRelease;
  // Shift at pointer down selects a range, in gallery order, from the anchor:
  // the image last clicked without Shift.
  bool _rangeOnTap = false;
  String? _selectionAnchor;
  static const _dragChannel = MethodChannel('umbra_tags/drag');
  final _gridKey = GlobalKey();
  final _scrollController = ScrollController();
  final _galleryFocus = FocusNode(debugLabel: 'Gallery');

  LibraryStore? _library;
  List<LibraryAsset> _assets = [];
  List<String> _imagePaths = [];
  final Map<String, LibraryAsset> _assetsByPath = {};
  final Map<String, GlobalKey> _tileKeys = {};
  final Map<String, Future<String?>> _thumbnails = {};

  /// Natural-language search: the query, its embedding, and each result's
  /// similarity. While set, the gallery lists the closest images, best first.
  String? _textQuery;
  TextQueryVector? _queryVector;

  /// While set, the gallery lists the images most similar to this one.
  LibraryAsset? _similarTo;
  Map<String, double> _searchScores = {};
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();
  static const _searchPage = 30;
  int _searchLimit = _searchPage;
  bool _searchHasMore = false, _loadingMoreResults = false;

  /// Whether the text encoder is loaded; the first search otherwise waits
  /// several seconds for it.
  bool _searchModelReady = false;
  Future<void>? _searchModelLoading;

  /// Whether gallery tiles list their tags along the bottom edge.
  bool _showTileTags = true;

  /// Sidebar tags whose children are hidden; kept across sessions.
  final Set<String> _collapsedTags = {};
  bool _busy = false;
  Completer<void>? _operationIdle;
  Future<void>? _applyingOptions;
  bool _closeRequested = false;
  bool _closingWindow = false;
  bool _showArchived = false;
  bool _untagged = false;
  // Starred-only filter; combines with whichever view is open.
  bool _starredOnly = false;
  GalleryOrder _order = GalleryOrder.newest;
  // Random order is a stable shuffle keyed by this seed, so reloads (after
  // tagging, starring, imports) keep positions; choosing Random reshuffles.
  int _shuffleSeed = DateTime.now().microsecondsSinceEpoch;
  // Deleted images stay in the catalog for a short undo window, hidden from
  // the gallery, then are removed and their files sent to the Recycle Bin.
  static const _undoWindow = Duration(seconds: 5);
  ({Set<String> ids, Timer timer})? _pendingDelete;
  final Set<String> _hiddenIds = {};
  // A status message that names one image; clicking it reveals the image.
  ({String text, String assetId})? _statusLink;
  String? _tagFilter;
  List<LibraryTag> _tags = [];
  Map<LibraryView, int> _viewCounts = const {};
  List<LibraryAsset> get _selection => _selectedPaths
      .map((path) => _assetsByPath[path])
      .whereType<LibraryAsset>()
      .toList();
  String _status = 'Create or open a library to begin';
  String? _lastLibraryPath;
  Timer? _sessionTimer;
  Future<void> _sessionWrite = Future.value();
  bool _sessionRestored = false;
  final Map<String, double> _scrollPositions = {};
  double? _pendingScrollOffset;
  String? get _scrollKey => _library == null
      ? null
      : '${_library!.id}/${_showArchived
            ? 'archive'
            : _untagged
            ? 'untagged'
            : _tagFilter != null
            ? 'tag/$_tagFilter'
            : 'all'}';

  void _rememberScrollPosition() {
    if (_pendingScrollOffset != null ||
        !_scrollController.hasClients ||
        _scrollKey == null) {
      return;
    }
    _scrollPositions[_scrollKey!] = _scrollController.offset;
    _persistSession();
  }

  void _queueScrollRestore() {
    _pendingScrollOffset = _scrollPositions[_scrollKey] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restoreScrollPosition(),
    );
  }

  void _restoreScrollPosition() {
    if (!mounted ||
        _pendingScrollOffset == null ||
        !_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      return;
    }
    _scrollController.jumpTo(
      _pendingScrollOffset!.clamp(
        0,
        _scrollController.position.maxScrollExtent,
      ),
    );
    _pendingScrollOffset = null;
  }

  final Map<String, Map<String, String>> _knownLibraries = {};
  ReceiverServer? _receiver;
  String _receiverStatus = 'Web receiver starting';
  MlSettings _mlSettings = const MlSettings();
  final Set<String> _startupModels = {};
  bool _reopenLastLibrary = true;
  // Closing the window hides it to the tray instead of quitting, so the
  // browser receiver keeps running. File → Quit or the tray's Quit exit.
  bool _minimizeToTray = false;
  bool _quitRequested = false;
  bool _inTray = false;
  bool _receiverEnabled = true;
  int _receiverPort = kPort;
  bool _warmingModels = false;
  ImageEmbedder? _standbyEmbedder;
  final Map<String, String> _modelStartupStatus = {
    'Artwork / photo classifier': 'On demand',
    'Similarity image encoder': 'On demand / indexing',
    'Tag suggestion text encoder': 'On demand',
  };

  Future<void> _warmModels([Set<String>? selectedModels]) async {
    final selected = Set<String>.from(selectedModels ?? _startupModels);
    if (_warmingModels || !mounted || _closingWindow) return;
    setState(() => _warmingModels = true);
    final loaders = <String, Future<void> Function()>{
      'Artwork / photo classifier': () =>
          _imageClassifier.loadModel(_mlSettings.modelId),
      'Similarity image encoder': () async {
        final controller = _similarity;
        if (controller != null) {
          await controller.warmUp();
        } else {
          final embedder = _standbyEmbedder ??= PythonImageEmbedder(
            home: _mlSettings.home,
            python: _mlSettings.python,
          );
          await embedder.load();
        }
      },
      'Tag suggestion text encoder': () => _suggestionBackend.load(),
    };
    try {
      for (final entry in loaders.entries) {
        if (!selected.any((id) => startupModels[id] == entry.key)) continue;
        if (!mounted || _closingWindow) return;
        setState(() {
          _modelStartupStatus[entry.key] = 'Loading…';
          _status = 'Loading ${entry.key}…';
        });
        try {
          await entry.value();
          if (mounted && !_closingWindow) {
            setState(() => _modelStartupStatus[entry.key] = 'Loaded');
          }
        } catch (error) {
          if (mounted && !_closingWindow) {
            setState(() => _modelStartupStatus[entry.key] = 'Failed: $error');
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _warmingModels = false;
          final failures = selected
              .map((id) => _modelStartupStatus[startupModels[id]])
              .whereType<String>()
              .where((status) => status.startsWith('Failed:'))
              .toList();
          _status = failures.isEmpty
              ? 'Selected ML models loaded'
              : failures.first;
        });
      }
    }
  }

  ImageClassifier? _classifier;
  TagSuggester? _tagSuggester;
  TagSuggester get _suggestionBackend => _tagSuggester ??= PythonTagSuggester(
    home: _mlSettings.home,
    python: _mlSettings.python,
  );

  Future<List<TagSuggestion>> _suggestTags(
    LibraryAsset asset, {
    String? matchingTag,
    List<String>? candidateLabels,
  }) async {
    if (_closingWindow) throw StateError('Application is closing.');
    final library = _library!;
    final backend = _suggestionBackend;
    final similarity = _similarity;
    final candidates =
        candidateLabels ??
        (matchingTag == null
            ? _tags.map((tag) => tag.name).toList()
            : [matchingTag]);
    final model = await backend.info();
    if (!identical(library, _library)) throw StateError('Library changed.');
    List<double>? vector;
    String? key;
    if (similarity != null) {
      await similarity.start();
      if (model.compatibleEmbeddingKey != null &&
          similarity.model?.key == model.compatibleEmbeddingKey &&
          similarity.error == null) {
        await similarity.ensure(asset);
        key = model.compatibleEmbeddingKey;
        vector =
            (await library.similarity({
                      'op': 'vector',
                      'key': key,
                      'assetId': asset.id,
                    })
                    as List?)
                ?.cast<double>();
      }
    }
    return backend.suggest(
      asset: asset,
      imagePath: library.absolutePath(asset.relativePath),
      candidates: candidates,
      includeDefaults: matchingTag == null && candidateLabels == null,
      embeddingKey: key,
      vector: vector,
    );
  }

  SimilarityController? _similarity;

  /// Shows the images closest to a description, e.g. "blue city at night".
  /// The text encoder maps the query into the same space as the indexed
  /// image vectors, so the closest vectors are the best matches.
  void _searchByText(String text) => _run(() async {
    final query = text.trim();
    final similarity = _similarity;
    if (_library == null) return;
    if (query.isEmpty) {
      _endTextSearch();
      await _reload();
      return;
    }
    if (similarity == null) {
      throw LibraryException('Similarity search is not running.');
    }
    await similarity.start();
    if (similarity.error != null) {
      throw LibraryException(
        'The similarity index needs attention: ${similarity.error}',
      );
    }
    setState(
      () => _status = _searchModelReady
          ? 'Searching for “$query”…'
          : 'Loading the search model (first search only)…',
    );
    await _warmSearchModel();
    final vector = await _suggestionBackend.embedText(query);
    if (vector.embeddingKey == null ||
        vector.embeddingKey != similarity.model?.key) {
      throw LibraryException(
        'The bundled text and image models do not match, so text search is unavailable.',
      );
    }
    _textQuery = query;
    _queryVector = vector;
    _searchLimit = _searchPage;
    _selectedPaths.clear();
    await _reload();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  });

  void _endTextSearch() {
    _similarTo = null;
    _textQuery = null;
    _queryVector = null;
    _searchScores = {};
    _searchField.clear();
  }

  Future<List<LibraryAsset>> _textSearchResults() async {
    final library = _library!;
    final query = _queryVector!;
    final ranked =
        (await library.similarity({
                  'op': 'searchVector',
                  'key': query.embeddingKey,
                  'vector': query.vector,
                  // One extra row tells whether more results exist.
                  'limit': _searchLimit + 1,
                })
                as List)
            .cast<Map>();
    _searchHasMore = ranked.length > _searchLimit;
    if (_searchHasMore) ranked.removeLast();
    // Reference-tag images stay hidden, as in All images.
    final visible = {
      for (final asset in await library.assets(excludeHidden: true))
        asset.id: asset,
    };
    _searchScores = {
      for (final row in ranked) row['id'] as String: row['score'] as double,
    };
    return [
      for (final row in ranked) ?visible[row['id']],
    ].where((asset) => !_hiddenIds.contains(asset.id)).toList();
  }

  /// Loads the text encoder in the background, e.g. from the first keystroke
  /// in the search field, so the first search does not wait for it.
  Future<void> _warmSearchModel() {
    if (_searchModelReady) return Future.value();
    return _searchModelLoading ??= _suggestionBackend
        .load()
        .then((_) {
          _searchModelReady = true;
        })
        .whenComplete(() => _searchModelLoading = null);
  }

  /// Search results keep loading near the bottom while they stay relevant:
  /// at least half as similar as the best match. Below that, the
  /// "Show more" button takes over.
  bool get _resultsStillRelevant {
    if (_searchScores.isEmpty) return false;
    final scores = _searchScores.values;
    final best = scores.reduce((a, b) => a > b ? a : b);
    final last = scores.reduce((a, b) => a < b ? a : b);
    return best > 0 && last >= best * 0.5;
  }

  void _maybeLoadMoreResults() {
    if (_queryVector == null ||
        !_searchHasMore ||
        _loadingMoreResults ||
        _busy ||
        !_resultsStillRelevant ||
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter > 800) {
      return;
    }
    unawaited(_loadMoreResults());
  }

  Future<void> _loadMoreResults() async {
    if (_loadingMoreResults || _queryVector == null) return;
    _loadingMoreResults = true;
    try {
      _searchLimit += _searchPage;
      await _reload();
    } finally {
      _loadingMoreResults = false;
    }
    // Short results may not fill the view; keep going while relevant.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeLoadMoreResults(),
    );
  }

  String _textSearchStatus(int count) {
    final similarity = _similarity;
    final best = _searchScores.values.fold<double?>(
      null,
      (best, score) => best == null || score > best ? score : best,
    );
    return '${_searchHasMore ? 'Top' : 'All'} $count matches for “$_textQuery”'
        '${best == null ? '' : ' · best match ${best.toStringAsFixed(3)}'}'
        '${similarity != null && similarity.ready < similarity.total ? ' · ${similarity.ready} of ${similarity.total} images indexed so far' : ''}';
  }

  Future<void> _stopSimilarity() async {
    final controller = _similarity;
    _similarity = null;
    if (controller != null) {
      await controller.stop();
      controller.dispose();
    }
  }

  void _startSimilarity() {
    if (_closingWindow) return;
    if (_library == null) return;
    final embedder =
        _standbyEmbedder ??
        PythonImageEmbedder(home: _mlSettings.home, python: _mlSettings.python);
    _standbyEmbedder = null;
    final controller = SimilarityController(
      _library!,
      embedder,
      shouldYield: () => _busy || _closingWindow,
    );
    _similarity = controller;
    unawaited(controller.start());
  }

  /// Shows the images closest to [asset] in the gallery, so every image
  /// action works on the results. Ends like a text search: the search
  /// field's clear button or any sidebar view.
  void _findSimilar(LibraryAsset asset) => _run(() async {
    final controller = _similarity;
    if (controller == null) {
      throw LibraryException('Similarity search is not running.');
    }
    setState(
      () => _status = 'Finding images similar to ${asset.originalFilename}…',
    );
    await controller.ensure(asset);
    if (!mounted) return;
    _endTextSearch();
    _similarTo = asset;
    _selectedPaths.clear();
    await _reload();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  });

  Future<List<LibraryAsset>> _similarResults() async {
    final library = _library!;
    final controller = _similarity;
    if (controller == null) return [];
    final rows = await controller.search(_similarTo!);
    // Reference-tag images stay hidden, as in All images.
    final visible = {
      for (final asset in await library.assets(excludeHidden: true))
        asset.id: asset,
    };
    _searchScores = {
      for (final row in rows) row['id'] as String: row['score'] as double,
    };
    return [
      for (final row in rows) ?visible[row['id']],
    ].where((asset) => !_hiddenIds.contains(asset.id)).toList();
  }

  bool _classifying = false;
  bool _cancelClassification = false;

  ImageClassifier get _imageClassifier => _classifier ??= PythonImageClassifier(
    home: _mlSettings.home,
    python: _mlSettings.python,
  );

  void _configureOptions() => _run(() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OptionsDialog(
        options: AppOptions(
          ml: _mlSettings,
          preloadModels: Set.of(_startupModels),
          reopenLastLibrary: _reopenLastLibrary,
          minimizeToTray: _minimizeToTray,
          receiverEnabled: _receiverEnabled,
          receiverPort: _receiverPort,
        ),
        receiverStatus: _receiverStatus,
        modelStatus: Map.of(_modelStartupStatus),
        onSave: _applyOptions,
      ),
    );
  });

  Future<void> _applyOptions(AppOptions options, bool loadNow) {
    if (_closingWindow) return Future.value();
    return _applyingOptions ??= _applyOptionsNow(
      options,
      loadNow,
    ).whenComplete(() => _applyingOptions = null);
  }

  Future<void> _applyOptionsNow(AppOptions options, bool loadNow) async {
    // Bind a replacement before closing the current receiver so an occupied
    // port leaves the working connection and saved options intact.
    final restartReceiver =
        options.receiverEnabled != _receiverEnabled ||
        options.receiverPort != _receiverPort ||
        (options.receiverEnabled && _receiver?.port == null);
    if (restartReceiver && widget.startReceiver) {
      ReceiverServer? replacement;
      if (options.receiverEnabled) {
        replacement = _createWebReceiver();
        try {
          await replacement.start(port: options.receiverPort);
        } catch (_) {
          await replacement.close();
          rethrow;
        }
      }
      await _receiver?.close();
      if (_closingWindow) {
        await replacement?.close();
        return;
      }
      _receiver = replacement;
      _receiverStatus = replacement == null
          ? 'Browser extension connection disabled'
          : 'Web receiver ready · localhost:${options.receiverPort}';
    }
    final runtimeChanged =
        options.ml.home != _mlSettings.home ||
        options.ml.python != _mlSettings.python ||
        options.ml.modelId != _mlSettings.modelId;
    if (runtimeChanged) {
      await _standbyEmbedder?.dispose();
      _standbyEmbedder = null;
      await _tagSuggester?.dispose();
      _tagSuggester = null;
      await _classifier?.dispose();
      _classifier = null;
      await _stopSimilarity();
      _modelStartupStatus.updateAll((key, value) => 'On demand');
    }
    if (_closingWindow || !mounted) return;
    setState(() {
      _mlSettings = options.ml;
      _startupModels
        ..clear()
        ..addAll(options.preloadModels);
      _reopenLastLibrary = options.reopenLastLibrary;
      _minimizeToTray = options.minimizeToTray;
      _receiverEnabled = options.receiverEnabled;
      _receiverPort = options.receiverPort;
    });
    if (runtimeChanged) _startSimilarity();
    _writeSession();
    await _sessionWrite;
    if (loadNow) unawaited(_warmModels(Set.of(_startupModels)));
  }

  /// ML classify (artwork / photo) is built but hidden from the menus.
  static const _mlClassifyEnabled = false;

  void _classifySelection() => _run(() async {
    final selected = _selection;
    final library = _library;
    if (selected.isEmpty || library == null) return;
    _cancelClassification = false;
    setState(() {
      _classifying = true;
      _status = 'Loading ML classifier…';
    });
    final details = <({String filename, String result})>[];
    var tagged = 0, predicted = 0, failed = 0;
    try {
      final classifier = _imageClassifier;
      await classifier.loadModel(_mlSettings.modelId);
      for (var index = 0; index < selected.length; index++) {
        if (_cancelClassification || !mounted) break;
        final asset = selected[index];
        setState(
          () => _status =
              'ML classify ${index + 1} of ${selected.length}: ${asset.originalFilename}',
        );
        try {
          final result = await classifier.classify(
            assetId: asset.id,
            imagePath: library.absolutePath(asset.relativePath),
            contentHash: asset.contentHash,
            modelId: _mlSettings.modelId,
          );
          if (result.assetId != asset.id ||
              result.contentHash != asset.contentHash) {
            throw StateError(
              'Classifier returned a result for a different image.',
            );
          }
          final tags = await library.applyClassification(
            assetId: result.assetId,
            contentHash: result.contentHash,
            modelId: result.modelId,
            modelVersion: result.modelVersion,
            scores: result.scores,
            threshold: _mlSettings.threshold,
            assignTags: _mlSettings.assignTags,
          );
          predicted++;
          if (tags.isNotEmpty) tagged++;
          final scores = result.scores.toList()
            ..sort(
              (a, b) =>
                  (b['confidence'] as num).compareTo(a['confidence'] as num),
            );
          final best = scores.first;
          details.add((
            filename: asset.originalFilename,
            result:
                '${best['label']} · ${((best['confidence'] as num) * 100).toStringAsFixed(1)}% · ${tags.isEmpty ? 'prediction saved; no tag added' : 'tag assigned'}',
          ));
        } catch (error) {
          failed++;
          details.add((
            filename: asset.originalFilename,
            result: error.toString(),
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _classifying = false);
      await _reload();
    }
    if (!mounted) return;
    final summary =
        '$predicted classified · $tagged tagged · $failed failed${_cancelClassification ? ' · stopped' : ''}';
    setState(() => _status = summary);
    if (_closeRequested) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ML classification'),
        content: SizedBox(
          width: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: details.length,
                  itemBuilder: (_, index) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      details[index].filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(details[index].result),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  });

  Future<T> _withWebLibrary<T>(
    String id,
    Future<T> Function(LibraryStore) operation,
  ) async {
    if (_busy || _closingWindow || !mounted) {
      throw ReceiverException(409, 'Umbra Tags is busy. Try again shortly.');
    }
    final entry = _knownLibraries[id];
    if (entry == null) {
      throw ReceiverException(404, 'Open this library in Umbra Tags first.');
    }
    _operationIdle = Completer<void>();
    setState(() => _busy = true);
    LibraryStore? store;
    try {
      store = _library?.id == id
          ? _library!
          : await LibraryStore.open(entry['path']!);
      if (store.id != id) {
        throw ReceiverException(
          409,
          'The library at this location has changed. Open it again in Umbra Tags.',
        );
      }
      return await operation(store);
    } finally {
      try {
        if (store != null && !identical(store, _library)) await store.close();
      } finally {
        if (mounted) setState(() => _busy = false);
        _operationIdle?.complete();
        _operationIdle = null;
      }
    }
  }

  ReceiverServer _createWebReceiver() => ReceiverServer(
    libraries: () async => _knownLibraries.entries
        .map(
          (entry) => <String, Object?>{
            'id': entry.key,
            'name': entry.value['name'],
            'active': entry.key == _library?.id,
          },
        )
        .toList(),
    tags: (id) => _withWebLibrary(
      id,
      (store) async => (await store.tags())
          .map(
            (tag) => <String, Object?>{
              'id': tag.id,
              'name': tag.name,
              'parentId': tag.parentId,
            },
          )
          .toList(),
    ),
    capture: (capture) => _withWebLibrary(capture.libraryId, (store) async {
      final current = identical(store, _library);
      final result = await store.importCapture(
        capture.bytes,
        filename: capture.filename,
        // Like disk imports, captures into the open library join its tag view.
        tagIds: {
          ...capture.tagIds,
          if (current && _tagFilter != null) _tagFilter!,
        }.toList(),
        maxDimension: capture.maxDimension,
      );
      if (current) {
        await _reload();
        _showNewestImports(
          reveal: store.absolutePath(result.asset.relativePath),
        );
      }
      if (mounted) {
        final text =
            '${result.duplicate ? 'Already in' : 'Received in'} ${store.name}: ${result.asset.originalFilename}';
        setState(() {
          _status = text;
          // Only images in the open library can be shown in the gallery.
          _statusLink = current ? (text: text, assetId: result.asset.id) : null;
        });
      }
      return <String, Object?>{
        'assetId': result.asset.id,
        'duplicate': result.duplicate,
        'libraryName': store.name,
        'width': result.asset.width,
        'height': result.asset.height,
      };
    }),
  );
  Future<void> _startWebReceiver() async {
    if (!widget.startReceiver || !mounted || _closingWindow) return;
    if (!_receiverEnabled) {
      setState(() => _receiverStatus = 'Browser extension connection disabled');
      return;
    }
    final receiver = _createWebReceiver();
    _receiver = receiver;
    try {
      await receiver.start(port: _receiverPort);
      if (!mounted || _closingWindow) {
        await receiver.close();
        return;
      }
      setState(
        () => _receiverStatus = 'Web receiver ready · localhost:$_receiverPort',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _receiverStatus = 'Web receiver unavailable: $error');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    tray.trayManager.addListener(this);
    // Windows ending the session, or an installer closing the app, must quit
    // even when closing normally minimizes to the tray.
    const MethodChannel('umbra_tags/session').setMethodCallHandler((
      call,
    ) async {
      if (call.method == 'endSession') _quit();
    });
    _scrollController.addListener(_rememberScrollPosition);
    HardwareKeyboard.instance.addHandler(_focusSearchOnCtrlK);
    _scrollController.addListener(_maybeLoadMoreResults);
    windowManager.isMaximized().then(
      (value) {
        if (mounted) setState(() => _maximized = value);
      },
      onError: (_) {}, // No window plugin in tests.
    );
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final data = await _loadSession(widget.sessionFile);
    if (!mounted) return;
    setState(() {
      _tileSize = _settingNumber(data['tileSize'], 200, 50, 400);
      _showTileTags = data['tileTags'] != false;
      _previewWidth = _settingNumber(data['previewWidth'], 300, 150, 800);
      _sidebarWidth = _settingNumber(
        data['sidebarWidth'],
        220,
        _sidebarMinWidth,
        _sidebarMaxWidth,
      );
      _layout =
          LayoutMode.values
              .where((value) => value.name == data['layout'])
              .firstOrNull ??
          LayoutMode.crop;
      _previewVisible = data['previewVisible'] is bool
          ? data['previewVisible'] as bool
          : true;
      _lastLibraryPath = data['lastLibraryPath'] is String
          ? data['lastLibraryPath'] as String
          : null;
      if (data['scrollPositions'] is Map) {
        for (final entry in (data['scrollPositions'] as Map).entries) {
          if (entry.key is String && entry.value is num) {
            _scrollPositions[entry.key as String] = _settingNumber(
              entry.value,
              0,
              0,
              1e9,
            );
          }
        }
      }
      final startup = data['startupModels'];
      _startupModels.clear();
      if (startup is List) {
        _startupModels.addAll(
          startup.whereType<String>().where(startupModels.containsKey),
        );
      } else if (data['preloadMlOnLaunch'] == true) {
        _startupModels.addAll(startupModels.keys);
      }
      _reopenLastLibrary = data['reopenLastLibrary'] != false;
      _collapsedTags
        ..clear()
        ..addAll(
          data['collapsedTags'] is List
              ? (data['collapsedTags'] as List).whereType<String>()
              : const <String>[],
        );
      _minimizeToTray = data['minimizeToTray'] == true;
      _order = GalleryOrder.values.firstWhere(
        (value) => value.name == data['galleryOrder'],
        orElse: () => GalleryOrder.newest,
      );
      _receiverEnabled = data['receiverEnabled'] != false;
      final port = data['receiverPort'];
      _receiverPort = port is int && port >= 1024 && port <= 65535
          ? port
          : kPort;
      _sessionRestored = true;
      final ml = data['ml'];
      if (ml is Map) {
        _mlSettings = MlSettings(
          home: ml['home'] is String ? ml['home'] as String : null,
          python: ml['python'] is String ? ml['python'] as String : null,
          modelId: ml['modelId'] is String ? ml['modelId'] as String : null,
          threshold: _settingNumber(ml['threshold'], 0.8, 0, 1),
          assignTags: ml['assignTags'] != false,
        );
      }
      if (!Platform.isMacOS && data['webLibraries'] is List) {
        for (final entry in data['webLibraries'] as List) {
          if (entry is Map &&
              entry['id'] is String &&
              entry['name'] is String &&
              entry['path'] is String) {
            _knownLibraries[entry['id'] as String] = {
              'name': entry['name'] as String,
              'path': entry['path'] as String,
            };
          }
        }
      }
    });
    // A sandboxed Mac must reselect the folder to grant access for this session.
    if (_reopenLastLibrary &&
        !Platform.isMacOS &&
        _lastLibraryPath != null &&
        !_busy &&
        _library == null) {
      await _run(() async {
        await _attach(await LibraryStore.open(_lastLibraryPath!));
      });
    }
    await _startWebReceiver();
    if (_startupModels.isNotEmpty && mounted && !_closingWindow) {
      unawaited(_warmModels());
    }
  }

  void _persistSession() {
    if (!_sessionRestored || _closingWindow) return;
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(milliseconds: 350), _writeSession);
  }

  void _writeSession() {
    if (!_sessionRestored) return;
    final data = <String, dynamic>{
      'startupModels': _startupModels.toList(),
      'reopenLastLibrary': _reopenLastLibrary,
      'minimizeToTray': _minimizeToTray,
      'galleryOrder': _order.name,
      'receiverEnabled': _receiverEnabled,
      'receiverPort': _receiverPort,
      'tileSize': _tileSize,
      'tileTags': _showTileTags,
      'collapsedTags': _collapsedTags.toList(),
      'previewWidth': _previewWidth,
      'sidebarWidth': _sidebarWidth,
      'layout': _layout.name,
      'ml': {
        'home': _mlSettings.home,
        'python': _mlSettings.python,
        'modelId': _mlSettings.modelId,
        'threshold': _mlSettings.threshold,
        'assignTags': _mlSettings.assignTags,
      },
      'previewVisible': _previewVisible,
      'scrollPositions': Map<String, double>.from(_scrollPositions),
      'lastLibraryPath': _lastLibraryPath,
      'webLibraries': _knownLibraries.entries
          .map((entry) => {'id': entry.key, ...entry.value})
          .toList(),
    };
    final sessionFile = widget.sessionFile;
    _sessionWrite = _sessionWrite.then((_) => _saveSession(data, sessionFile));
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || _closingWindow) return;
    _operationIdle = Completer<void>();
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted && !_closingWindow) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Library operation could not finish'),
            content: SelectableText(error.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _operationIdle?.complete();
      _operationIdle = null;
    }
  }

  Future<void> _attach(LibraryStore library) async {
    if (!mounted || _closingWindow) {
      await library.close();
      return;
    }
    await _commitPendingDelete();
    _rememberScrollPosition();
    await _stopSimilarity();
    await _library?.close();
    if (_closingWindow || !mounted) {
      await library.close();
      return;
    }
    _library = library;
    // Finish sending anything a previous session left in the trash folder.
    unawaited(_emptyLibraryTrash(library).catchError((_) {}));
    _startSimilarity();
    _lastLibraryPath = library.root;
    _knownLibraries[library.id] = {'name': library.name, 'path': library.root};
    _showArchived = false;
    _untagged = false;
    _tagFilter = null;
    _thumbnails.clear();
    await _reload();
    _queueScrollRestore();
    _persistSession();
  }

  Future<void> _reload() async {
    if (_closingWindow) return;
    final tags = await _library!.tags();
    final counts = await _library!.viewCounts();
    if (_tagFilter != null && !tags.any((tag) => tag.id == _tagFilter)) {
      _tagFilter = null;
    }
    final List<LibraryAsset> assets;
    if (_similarTo != null) {
      assets = await _similarResults();
    } else if (_queryVector != null) {
      assets = await _textSearchResults();
    } else {
      assets = (await _library!.assets(
        archived: _showArchived,
        untagged: _untagged,
        tagId: _tagFilter,
        excludeHidden: !_showArchived && !_untagged,
        starredOnly: _starredOnly,
      )).where((asset) => !_hiddenIds.contains(asset.id)).toList();
      _applyOrder(assets);
    }
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _tags = tags;
      _viewCounts = {
        LibraryView.all: counts['all']!,
        LibraryView.untagged: counts['untagged']!,
        LibraryView.archived: counts['archived']!,
      };
      _imagePaths = assets
          .map((a) => _library!.absolutePath(a.relativePath))
          .toList();
      _assetsByPath.clear();
      for (var i = 0; i < assets.length; i++) {
        _assetsByPath[_imagePaths[i]] = assets[i];
      }
      _tileKeys.removeWhere((key, _) => !_assetsByPath.containsKey(key));
      for (final path in _imagePaths) {
        _tileKeys.putIfAbsent(path, () => GlobalKey());
      }
      _selectedPaths.removeWhere((path) => !_assetsByPath.containsKey(path));
      _status = _similarTo != null
          ? '${assets.length} closest to ${_similarTo!.originalFilename}'
          : _textQuery != null
          ? _textSearchStatus(assets.length)
          : '${assets.length} images${_showArchived ? ' archived' : ''}'
                '${assets.any((a) => a.missing) ? ' · ${assets.where((a) => a.missing).length} missing' : ''}';
    });
  }

  String? _pathOfAsset(String assetId) {
    for (final entry in _assetsByPath.entries) {
      if (entry.value.id == assetId) return entry.key;
    }
    return null;
  }

  /// Selects an image and scrolls the gallery to it. When the open view does
  /// not include it, switches to All images (or Archived), or, if an
  /// excluded tag hides it from All images, to one of its tags.
  void _revealAsset(String assetId) => _run(() async {
    final library = _library;
    if (library == null) return;
    var path = _pathOfAsset(assetId);
    if (path == null) {
      final archived = (await library.assets(
        archived: true,
      )).any((asset) => asset.id == assetId);
      final active = archived
          ? null
          : (await library.assets()).where((a) => a.id == assetId).firstOrNull;
      if (!archived && active == null) {
        throw LibraryException('This image is no longer in the library.');
      }
      _rememberScrollPosition();
      _pendingScrollOffset = null;
      _showArchived = archived;
      _untagged = false;
      _tagFilter = null;
      _starredOnly = false;
      await _reload();
      path = _pathOfAsset(assetId);
      if (path == null && active != null && active.tagIds.isNotEmpty) {
        _tagFilter = active.tagIds.first;
        await _reload();
        path = _pathOfAsset(assetId);
      }
      if (path == null) return;
    }
    final target = path;
    setState(() {
      _selectedPaths
        ..clear()
        ..add(target);
      _selectionAnchor = target;
    });
    await _scrollToPath(target);
  });

  /// Scrolls until [path]'s tile is built, then brings it into view. Tiles
  /// are built lazily, so first jump near its proportional position.
  Future<void> _scrollToPath(String path) async {
    final index = _imagePaths.indexOf(path);
    if (index < 0) return;
    for (var attempt = 0; attempt < 6; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final tile = _tileKeys[path]?.currentContext;
      if (tile != null && tile.mounted) {
        await Scrollable.ensureVisible(
          tile,
          alignment: 0.3,
          duration: const Duration(milliseconds: 200),
        );
        return;
      }
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final fraction = _imagePaths.length > 1
          ? index / (_imagePaths.length - 1)
          : 0.0;
      position.jumpTo(position.maxScrollExtent * fraction);
    }
  }

  /// The images a star action on [path] affects: the selection when [path]
  /// is part of it, otherwise just [path].
  List<LibraryAsset> _starTargets(String path) => [
    for (final target
        in _selectedPaths.contains(path) ? _selectedPaths : {path})
      ?_assetsByPath[target],
  ];

  /// Whether starring [path] would star (true) or unstar (false): unstar only
  /// when every target is already starred.
  bool _starWillSet(String path) =>
      !_starTargets(path).every((asset) => asset.starred);

  void _toggleStar(String path) => _run(() async {
    final targets = _starTargets(path);
    if (targets.isEmpty) return;
    final star = _starWillSet(path);
    await _library!.setStarred([for (final a in targets) a.id], star);
    await _reload();
    if (mounted) {
      setState(
        () => _status =
            '${star ? 'Starred' : 'Unstarred'} ${targets.length} '
            '${targets.length == 1 ? 'image' : 'images'}',
      );
    }
  });

  void _toggleStarredOnly() => _run(() async {
    _rememberScrollPosition();
    _starredOnly = !_starredOnly;
    _selectedPaths.clear();
    await _reload();
    _queueScrollRestore();
  });

  /// A tag dropped on a selected image applies to the whole selection;
  /// dropped on any other image, to just that one.
  void _applyDroppedTag(String path, LibraryTag tag) => _run(() async {
    final paths = _selectedPaths.contains(path) ? _selectedPaths : {path};
    final ids = [
      for (final target in paths)
        if (_assetsByPath[target] case final asset?) asset.id,
    ];
    if (ids.isEmpty) return;
    await _library!.editTags(ids, add: [tag.id], remove: const []);
    await _reload();
    if (mounted) {
      setState(
        () => _status =
            'Tagged ${ids.length} ${ids.length == 1 ? 'image' : 'images'} '
            '“${tag.name}”',
      );
    }
  });

  /// Scrolls to the top, where the newest imports are listed, optionally
  /// selecting them.
  void _showNewestImports({Set<String>? select, String? reveal}) {
    if (!mounted) return;
    if (select != null && select.isNotEmpty) {
      setState(
        () => _selectedPaths
          ..clear()
          ..addAll(select),
      );
    }
    _pendingScrollOffset = null;
    // Newest first lists imports at the top; other orders place them
    // elsewhere, so scroll to the first of them instead.
    final targets = {...?select, ?reveal};
    if (_order != GalleryOrder.newest && targets.isNotEmpty) {
      unawaited(
        _scrollToPath(
          _imagePaths.firstWhere(targets.contains, orElse: () => ''),
        ),
      );
    } else if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// Orders [assets] in place. The catalog lists newest first.
  void _applyOrder(List<LibraryAsset> assets) {
    switch (_order) {
      case GalleryOrder.newest:
        break;
      case GalleryOrder.oldest:
        final reversed = assets.reversed.toList();
        assets
          ..clear()
          ..addAll(reversed);
      case GalleryOrder.random:
        int rank(LibraryAsset asset) =>
            Object.hash(_shuffleSeed, asset.id) & 0x3fffffff;
        assets.sort((a, b) => rank(a).compareTo(rank(b)));
    }
  }

  void _setOrder(GalleryOrder order) => _run(() async {
    // Picking Random again reshuffles.
    if (order == GalleryOrder.random) {
      _shuffleSeed = DateTime.now().microsecondsSinceEpoch;
    }
    _order = order;
    _persistSession();
    await _reload();
    _pendingScrollOffset = null;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  });

  /// Bottom-edge colours for the preview panel's glass tint, per image.
  final Map<String, Future<List<Color>?>> _ambient = {};

  Future<List<Color>?> _ambientFor(String path) {
    final asset = _assetsByPath[path];
    if (asset == null) return Future.value(null);
    if (_ambient.length > 64) _ambient.remove(_ambient.keys.first);
    return _ambient.putIfAbsent('${asset.id}-${asset.contentHash}', () async {
      try {
        // The cached thumbnail is plenty for a 4×4 colour grid.
        final thumbnail = await _thumbnailFor(path);
        return thumbnail == null ? null : await bottomEdgeColors(thumbnail);
      } catch (_) {
        return null; // Untinted panel; nothing else depends on it.
      }
    });
  }

  /// An image's tag names for its tile caption, alphabetical.
  List<String> _tileTagNames(LibraryAsset asset) {
    if (asset.tagIds.isEmpty) return const [];
    final names = {for (final tag in _tags) tag.id: tag.name};
    return [for (final id in asset.tagIds) ?names[id]]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<String?> _thumbnailFor(String path) {
    if (_thumbnails.length > 256) _thumbnails.remove(_thumbnails.keys.first);
    return _thumbnails.putIfAbsent(
      path,
      () => _library!.thumbnail(_assetsByPath[path]!),
    );
  }

  void _createLibrary() => _run(() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Use empty folder',
    );
    if (folder == null || !mounted || _closingWindow) return;
    final input = TextEditingController(text: p.basename(folder));
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New library'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Library name'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    // Wait until the closing dialog has detached its editable text.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
    if (name != null && !_closingWindow) {
      await _attach(await LibraryStore.create(folder, name));
    }
  });

  void _openLibrary() => _run(() async {
    final folder = await getDirectoryPath(
      initialDirectory: _lastLibraryPath,
      confirmButtonText: 'Open library',
    );
    if (folder != null && !_closingWindow) {
      await _attach(await LibraryStore.open(folder));
    }
  });

  void _closeLibrary() => _run(() async {
    await _commitPendingDelete();
    _rememberScrollPosition();
    await _stopSimilarity();
    await _library?.close();
    if (!mounted) return;
    setState(() {
      _library = null;
      _tags = [];
      _tagFilter = null;
      _untagged = false;
      _assets = [];
      _imagePaths = [];
      _assetsByPath.clear();
      _tileKeys.clear();
      _selectedPaths.clear();
      _thumbnails.clear();
      _status = 'Library closed';
    });
  });

  void _importImages() => _run(() async {
    final library = _library;
    if (library == null) return;
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: LibraryStore.supportedExtensions,
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
    await _importImageFiles(files);
  });

  void _importFromDownloads() => _run(() async {
    if (_library == null) return;
    final folder = (await getDownloadsDirectory())?.path;
    if (folder == null) {
      throw LibraryException('Could not find the Downloads folder.');
    }
    final files = <File>[];
    await for (final entity in Directory(folder).list(followLinks: false)) {
      final extension = p.extension(entity.path).toLowerCase();
      if (entity is File &&
          LibraryStore.supportedExtensions.contains(
            extension.replaceFirst('.', ''),
          )) {
        files.add(entity);
      }
    }
    if (files.isEmpty) {
      if (mounted) setState(() => _status = 'No images found in Downloads');
      return;
    }
    final modified = await Future.wait(
      files.map((file) => file.lastModified()),
    );
    final order = {
      for (var i = 0; i < files.length; i++) files[i].path: modified[i],
    };
    files.sort((a, b) => order[b.path]!.compareTo(order[a.path]!));
    if (!mounted) return;
    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (_) => DownloadsImportDialog(
        folder: folder,
        files: files,
        accent: AppColors.accent,
        onOpen: (path) => unawaited(
          _shellChannel
              .invokeMethod<bool>('openFile', path)
              .catchError((_) => null),
        ),
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    await _importImageFiles([for (final path in chosen) XFile(path)]);
  });

  // Once imported (or found already in the library), source files move to the
  // Recycle Bin. Files inside the library folder are never touched.
  //
  // Imports land in the gallery that is open: a tag view assigns its tag so
  // they appear there, and the archive view switches to all images. The
  // gallery then scrolls to the top with the imported images selected.
  Future<void> _importImageFiles(List<XFile> files) async {
    final library = _library;
    if (library == null || files.isEmpty) return;
    final tagIds = [?_tagFilter];
    final imported = <String>{};
    var added = 0;
    var duplicates = 0;
    final errors = <String>[];
    final sources = <String>[];
    for (var i = 0; i < files.length; i++) {
      if (_closingWindow) break;
      if (mounted) {
        setState(() => _status = 'Importing ${i + 1} of ${files.length}…');
      }
      try {
        final result = await library.importImage(files[i].path, tagIds: tagIds);
        imported.add(library.absolutePath(result.asset.relativePath));
        final source = p.absolute(files[i].path);
        if (!p.isWithin(library.root, source) &&
            !p.equals(library.root, source)) {
          sources.add(source);
        }
        if (result.duplicate) {
          duplicates++;
        } else {
          added++;
        }
      } catch (error) {
        errors.add('${files[i].name}: $error');
      }
    }
    var recycled = 0;
    if (sources.isNotEmpty) {
      try {
        await _shellChannel.invokeMethod<bool>('recycleFiles', sources);
        recycled = sources.length;
      } on MissingPluginException {
        // Only the Windows runner provides this; elsewhere originals stay put.
      } on PlatformException catch (error) {
        errors.add(
          'Imported, but the originals were not moved to the Recycle Bin: '
          '${error.message}',
        );
      }
    }
    _thumbnails.clear();
    if (imported.isNotEmpty && _showArchived) _showArchived = false;
    // New imports are unstarred, so leave the starred filter to show them.
    if (imported.isNotEmpty && _starredOnly) _starredOnly = false;
    await _reload();
    if (imported.isNotEmpty) {
      _showNewestImports(
        select: imported.where(_assetsByPath.containsKey).toSet(),
      );
    }
    if (mounted) {
      setState(
        () => _status =
            '$added imported · $duplicates already in library'
            '${recycled > 0 ? ' · $recycled originals moved to Recycle Bin' : ''}'
            '${errors.isNotEmpty ? ' · ${errors.length} failed' : ''}',
      );
    }
    if (errors.isNotEmpty) throw LibraryException(errors.join('\n'));
  }

  void _setFilter(LibraryView view, [String? tag]) => _run(() async {
    _endTextSearch();
    _rememberScrollPosition();
    _showArchived = view == LibraryView.archived;
    _untagged = view == LibraryView.untagged;
    _tagFilter = tag;
    _selectedPaths.clear();
    await _reload();
    _queueScrollRestore();
  });

  void _editTag({LibraryTag? tag, String? parent}) => _run(() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TagDetailsDialog(
        tags: _tags,
        tag: tag,
        parentId: parent,
        onSave: (name, parentId) async {
          await _library!.saveTag(id: tag?.id, name: name, parentId: parentId);
        },
      ),
    );
    await _reload();
  });

  void _deleteTag(LibraryTag tag) => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${tag.name}”?'),
        content: const Text(
          'This removes the tag from all images. Child tags move up one level. Images are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete tag'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _library!.deleteTag(tag.id);
      await _reload();
    }
  });

  void _editSelectionTags() => _run(() async {
    final selected = _selection;
    if (selected.isEmpty) return;
    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchTagsDialog(
        tags: _tags,
        onCreateTag: (name, parentId) =>
            _library!.saveTag(name: name, parentId: parentId),
        assets: selected,
        // Tag suggestions (the dialog's Suggestions tab) are switched off.
        // Pass onSuggest, thumbnail and onApplyReviewed to bring it back.
        onSave: (add, remove) => _library!.editTags(
          selected.map((a) => a.id).toList(),
          add: add,
          remove: remove,
        ),
      ),
    );
    await _reload();
  });

  /// The breadcrumb strip's AI sort shortcut for the open view: sort
  /// Untagged into top-level tags, or a tag with children into them.
  ViewAction? get _aiSortAction {
    if (!_aiSortEnabled ||
        _library == null ||
        _showArchived ||
        _textQuery != null) {
      return null;
    }
    if (_untagged) {
      return ViewAction(
        'AI sort into tags…',
        _busy ? null : () => _aiSort(),
        key: const ValueKey('ai-sort-untagged'),
      );
    }
    final tag = _tags.where((t) => t.id == _tagFilter).firstOrNull;
    if (tag == null || !_tags.any((t) => t.parentId == tag.id)) return null;
    return ViewAction(
      'Sort into child tags…',
      _busy ? null : () => _aiSort(parent: tag),
      key: const ValueKey('ai-sort-children'),
    );
  }

  bool _canRefineSelection() => _selection.any(
    (asset) =>
        !asset.missing &&
        _tags.any((tag) => asset.tagIds.contains(tag.parentId)),
  );

  /// AI refine tags is built but hidden; Find matching images covers it.
  static const _refineEnabled = false;

  void _refineSelection() => _run(() async {
    final library = _library;
    if (library == null || _closingWindow) return;
    final selected = _selection.toList();
    final tags = List<LibraryTag>.of(_tags);
    final children = <String, List<LibraryTag>>{};
    for (final tag in tags) {
      if (tag.parentId != null) {
        children.putIfAbsent(tag.parentId!, () => []).add(tag);
      }
    }
    final eligible = selected
        .where(
          (asset) => !asset.missing && asset.tagIds.any(children.containsKey),
        )
        .toList();
    if (eligible.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HierarchyDialog(
        assets: eligible,
        skipped: selected.length - eligible.length,
        thumbnail: library.thumbnail,
        find: (asset) async {
          final matches = <HierarchyMatch>[];
          for (final parent in tags.where(
            (tag) =>
                asset.tagIds.contains(tag.id) && children.containsKey(tag.id),
          )) {
            final candidates = children[parent.id]!;
            final scores = <TagSuggestion>[];
            // The generic suggestion protocol accepts at most 512 candidates.
            for (var offset = 0; offset < candidates.length; offset += 512) {
              if (_closingWindow || !identical(library, _library)) {
                throw StateError('Library closed.');
              }
              scores.addAll(
                await _suggestTags(
                  asset,
                  candidateLabels: candidates
                      .skip(offset)
                      .take(512)
                      .map((tag) => tag.name)
                      .toList(),
                ),
              );
            }
            final byName = {
              for (final child in candidates) child.name.toLowerCase(): child,
            };
            final ranked =
                scores
                    .where(
                      (score) => byName.containsKey(score.label.toLowerCase()),
                    )
                    .toList()
                  ..sort((a, b) => b.score.compareTo(a.score));
            for (var i = 0; i < ranked.length && i < 3; i++) {
              final score = ranked[i];
              matches.add(
                HierarchyMatch(
                  asset,
                  parent,
                  byName[score.label.toLowerCase()]!,
                  score.score,
                  i == 0,
                ),
              );
            }
          }
          return matches;
        },
        apply: (accepted) async {
          if (_closingWindow || !identical(library, _library)) {
            throw StateError('Library closed.');
          }
          await library.applyReviewedTags(
            eligible.where((asset) => accepted.containsKey(asset.id)).toList(),
            [],
            [],
            accepted,
          );
        },
      ),
    );
    await _reload();
  });

  void _toggleTagExcluded(LibraryTag tag) => _run(() async {
    await _library!.setTagExcludedFromAll(tag.id, !tag.excludedFromAll);
    await _reload();
    if (mounted) {
      setState(
        () => _status = tag.excludedFromAll
            ? '“${tag.name}” is no longer a reference tag'
            : '“${tag.name}” is now a reference tag: its images only show when you filter by it',
      );
    }
  });

  void _findTagMatches(LibraryTag tag) => _run(() async {
    final library = _library;
    if (library == null) return;
    // Images in the tag's view (the tag or a descendant) are its examples,
    // not candidates.
    final subtree = <String>{tag.id};
    for (var grew = true; grew;) {
      grew = false;
      for (final other in _tags) {
        if (other.parentId != null &&
            subtree.contains(other.parentId) &&
            subtree.add(other.id)) {
          grew = true;
        }
      }
    }
    final assets = (await library.assets())
        .where((asset) => !asset.missing && !asset.tagIds.any(subtree.contains))
        .toList();
    if (_closingWindow) return;
    final classifier = _imageClassifier;
    final modelId = _mlSettings.modelId;
    List<String> labels = [];
    String? classifierError;
    try {
      labels = (await classifier.labels(modelId)).toSet().toList();
    } catch (error) {
      classifierError = error.toString();
    }
    if (!mounted || _closingWindow || !identical(library, _library)) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TagMatchDialog(
        tagName: tag.name,
        imagePath: (a) => library.absolutePath(a.relativePath),
        assets: assets,
        classifierLabels: labels,
        classifierError: classifierError,
        classifierThreshold: _mlSettings.threshold,
        thumbnail: library.thumbnail,
        scanSemantic: (progress, stopped) =>
            _scanTagMatches(library, tag, assets, progress, stopped),
        score: (asset, source, label) async {
          if (_closingWindow) throw StateError('Application is closing.');
          if (!identical(library, _library)) {
            throw StateError('Library changed.');
          }
          if (source == TagMatchSource.semantic) {
            final suggestions = await _suggestTags(asset, matchingTag: label);
            return suggestions
                .firstWhere(
                  (suggestion) =>
                      suggestion.label.toLowerCase() == label.toLowerCase(),
                  orElse: () => throw StateError(
                    'The model did not return a score for this tag.',
                  ),
                )
                .score;
          }
          final result = await classifier.classify(
            assetId: asset.id,
            imagePath: library.absolutePath(asset.relativePath),
            contentHash: asset.contentHash,
            modelId: modelId,
          );
          if (result.assetId != asset.id ||
              result.contentHash != asset.contentHash) {
            throw StateError('Classifier result does not match this image.');
          }
          final row = result.scores.firstWhere(
            (row) => row['label'] == label,
            orElse: () =>
                throw StateError('The classifier does not support this label.'),
          );
          return (row['confidence'] as num).toDouble();
        },
        onApply: (selected) async {
          if (!identical(library, _library)) {
            throw StateError('Library changed.');
          }
          await library.applyReviewedTags(selected, [tag.id], [], {});
        },
      ),
    );
    await _reload();
  });

  /// The semantic scan of "Find matching images": one worker pass over the
  /// stored vectors scores every image by the images already in [tag] and
  /// its name (see `ml/tag_match.dart`). Images without a vector are indexed
  /// first. Returns null without a working similarity index; the dialog
  /// then scores by the tag name, image by image.
  Future<TagMatchBatch?> _scanTagMatches(
    LibraryStore library,
    LibraryTag tag,
    List<LibraryAsset> assets,
    void Function(int done, int total) progress,
    bool Function() stopped,
  ) async {
    final similarity = _similarity;
    if (similarity == null) return null;
    await similarity.start();
    final key = similarity.model?.key;
    if (similarity.error != null || key == null) return null;
    void check() {
      if (_closingWindow || !identical(library, _library)) {
        throw StateError('Library closed.');
      }
    }

    check();
    List<double>? name;
    String? nameError;
    try {
      final cacheKey = '$key|${tag.name}';
      name = _tagNameVectors[cacheKey];
      if (name == null) {
        final embedded = await _suggestionBackend.embedText(tag.name);
        if (embedded.embeddingKey != key) {
          throw StateError('the text and image models do not match');
        }
        name = _tagNameVectors[cacheKey] = embedded.vector;
      }
    } catch (error) {
      name = null;
      nameError = error.toString();
    }
    check();
    Future<Map> run() async =>
        await library.similarity({
              'op': 'matchScores',
              'key': key,
              'tagId': tag.id,
              'nameVector': name,
            })
            as Map;
    var result = await run();
    final byId = {for (final asset in assets) asset.id: asset};
    final pending = [
      for (final id in (result['unindexed'] as List).cast<String>()) ?byId[id],
    ];
    final errors = <String, String>{};
    if (pending.isNotEmpty) {
      for (var i = 0; i < pending.length && !stopped(); i++) {
        progress(i, pending.length);
        check();
        try {
          await similarity.ensure(pending[i]);
        } catch (error) {
          errors[pending[i].id] = error.toString();
        }
      }
      progress(pending.length, pending.length);
      check();
      result = await run();
    }
    final members = result['members'] as int;
    if (members == 0 && name == null) {
      throw LibraryException(
        'This tag has no indexed images yet and its name could not be used: $nameError',
      );
    }
    return TagMatchBatch(
      scores: (result['scores'] as Map).cast<String, double>(),
      errors: {...(result['failed'] as Map).cast<String, String>(), ...errors},
      members: members,
      nameWeight: (result['nameWeight'] as num?)?.toDouble(),
      nameError: name == null ? nameError : null,
      threshold: (result['threshold'] as num?)?.toDouble(),
    );
  }

  void _selectImage(String path) {
    if (_busy) return;
    _galleryFocus.requestFocus();
    setState(() {
      final from = _selectionAnchor == null
          ? -1
          : _imagePaths.indexOf(_selectionAnchor!);
      final to = _imagePaths.indexOf(path);
      if (_rangeOnTap && from >= 0 && to >= 0) {
        // Ctrl+Shift adds the range to the selection; Shift alone replaces it.
        if (!_toggleOnTap) _selectedPaths.clear();
        _selectedPaths.addAll(
          _imagePaths.sublist(
            from < to ? from : to,
            (from < to ? to : from) + 1,
          ),
        );
        return;
      }
      _selectionAnchor = path;
      if (_toggleOnTap) {
        if (!_selectedPaths.add(path)) _selectedPaths.remove(path);
      } else {
        _selectedPaths
          ..clear()
          ..add(path);
      }
    });
  }

  void _selectContextImage(String path) {
    if (_busy) return;
    _galleryFocus.requestFocus();
    if (!_selectedPaths.contains(path)) {
      _selectionAnchor = path;
      setState(
        () => _selectedPaths
          ..clear()
          ..add(path),
      );
    }
  }

  void _deleteSelection() => _run(() async {
    final selected = _selection;
    if (selected.isEmpty || _library == null) return;
    if (selected.length > 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${selected.length} images?'),
          content: const Text(
            'Remove these images and their tag assignments from this library. '
            'Their files go to the Recycle Bin. You can undo for a few seconds.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete images'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    // One undo window at a time: an earlier pending delete completes now.
    await _commitPendingDelete();
    final ids = selected.map((asset) => asset.id).toSet();
    _hiddenIds.addAll(ids);
    _pendingDelete = (
      ids: ids,
      timer: Timer(_undoWindow, _commitPendingDelete),
    );
    setState(() => _selectedPaths.clear());
    await _reload();
    if (!mounted) return;
    final label =
        '${ids.length} ${ids.length == 1 ? 'image' : 'images'} '
        'moved to the Recycle Bin';
    setState(() => _status = label);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(label),
          duration: _undoWindow,
          // With an action, snack bars otherwise stay until dismissed.
          persist: false,
          behavior: SnackBarBehavior.floating,
          width: 440,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undoDelete(ids),
          ),
        ),
      );
    _galleryFocus.requestFocus();
  });

  void _undoDelete(Set<String> ids) {
    final pending = _pendingDelete;
    if (pending == null || !identical(pending.ids, ids)) return;
    pending.timer.cancel();
    _pendingDelete = null;
    _hiddenIds.removeAll(ids);
    _run(() async {
      await _reload();
      if (mounted) {
        setState(
          () => _status =
              'Restored ${ids.length} ${ids.length == 1 ? 'image' : 'images'}',
        );
      }
    });
  }

  /// Completes the pending delete, if any: removes the images from the
  /// library and sends their files to the Recycle Bin.
  Future<void> _commitPendingDelete() async {
    final pending = _pendingDelete;
    if (pending == null) return;
    _pendingDelete = null;
    pending.timer.cancel();
    final library = _library;
    if (library == null) return;
    // Detach file-backed images first: Windows can retain file mappings until
    // the preview, thumbnail and cached codec are disposed.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    try {
      await library.deleteAssets(pending.ids.toList());
      await _emptyLibraryTrash(library);
    } catch (error) {
      if (mounted) setState(() => _status = 'Delete failed: $error');
    } finally {
      _hiddenIds.removeAll(pending.ids);
      _thumbnails.clear();
      if (mounted && !_closingWindow && identical(library, _library)) {
        await _reload();
      }
    }
  }

  /// Sends the library's trashed media to the Recycle Bin. Where there is no
  /// Recycle Bin integration they are deleted; if the user declines a
  /// permanent-deletion prompt they stay for the next attempt.
  Future<void> _emptyLibraryTrash(LibraryStore library) async {
    final files = await library.trashFiles();
    if (files.isEmpty) return;
    try {
      await _shellChannel.invokeMethod<bool>('recycleFiles', files);
    } on MissingPluginException {
      await library.purgeTrash();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _status = 'Recycle Bin: ${error.message}');
      }
    }
    await library.trashFiles(); // Clears the emptied folders.
  }

  /// Opens the resize wizard for one image.
  void _resizeImage(LibraryAsset asset) => _run(() async {
    final library = _library;
    if (library == null) return;
    final thumbnail = await library.thumbnail(asset);
    if (!mounted) return;
    final choice = await showDialog<ResizeChoice>(
      context: context,
      builder: (context) =>
          ResizeDialog(asset: asset, thumbnailPath: thumbnail),
    );
    if (choice?.action != ResizeAction.resize || !mounted) return;
    await _applyResize(library, asset, choice!.width!, choice.height!);
    await _reload();
    if (mounted) {
      setState(
        () => _status =
            'Resized ${asset.originalFilename} to ${choice.width} × ${choice.height}',
      );
    }
  });

  /// Walks through every image above a size threshold, largest first, opening
  /// the resize wizard for each so it can be resized or skipped.
  void _resizeLargeImages() => _run(() async {
    final library = _library;
    if (library == null) return;
    final all = await library.assets();
    if (!mounted) return;
    final threshold = await showDialog<LargeImageThreshold>(
      context: context,
      builder: (context) => LargeImagesDialog(assets: all),
    );
    if (threshold == null) return;
    int weight(LibraryAsset a) =>
        threshold.measure == LargeImageMeasure.fileSize
        ? a.byteSize
        : a.width * a.height;
    final queue = all.where(threshold.matches).toList()
      ..sort((a, b) => weight(b).compareTo(weight(a)));
    var resized = 0, skipped = 0;
    final failures = <String>[];
    try {
      for (var i = 0; i < queue.length; i++) {
        final asset = queue[i];
        final thumbnail = await library.thumbnail(asset);
        if (!mounted || _closingWindow) break;
        final choice = await showDialog<ResizeChoice>(
          context: context,
          barrierDismissible: false,
          builder: (context) => ResizeDialog(
            asset: asset,
            thumbnailPath: thumbnail,
            position: i + 1,
            total: queue.length,
            suggestedLongEdge: threshold.suggestedLongEdge,
          ),
        );
        if (choice == null || choice.action == ResizeAction.stop) break;
        if (choice.action == ResizeAction.skip) {
          skipped++;
          continue;
        }
        try {
          await _applyResize(library, asset, choice.width!, choice.height!);
          resized++;
        } on LibraryException catch (error) {
          failures.add('${asset.originalFilename}: $error');
        }
      }
    } finally {
      _thumbnails.clear();
      if (mounted && !_closingWindow) await _reload();
    }
    if (!mounted) return;
    setState(
      () => _status =
          'Resized $resized, skipped $skipped'
          '${failures.isEmpty ? '' : ', ${failures.length} failed'}',
    );
    if (failures.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some images could not be resized'),
          content: SelectableText(failures.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  });

  /// Text-encoder vectors of tag names, keyed by image model key and name.
  final Map<String, List<double>> _tagNameVectors = {};

  /// AI sort into existing tags, one image at a time. Without [parent],
  /// untagged images are sorted into top-level tags; with it, images tagged
  /// [parent] (and none of its children) into its children. [chooseMode]
  /// first asks which of the two to run. With [selection], exactly those
  /// images are sorted, whatever tags they already have.
  /// AI sort is built but hidden: Find matching images covers the same
  /// need more simply. Set to true to restore every entry point.
  static const _aiSortEnabled = false;

  void _aiSort({
    LibraryTag? parent,
    bool chooseMode = false,
    List<LibraryAsset>? selection,
  }) => _run(() async {
    final library = _library;
    final similarity = _similarity;
    if (library == null) return;
    if (similarity == null) {
      throw LibraryException('Similarity search is not running.');
    }
    final tags = await library.tags();
    final active = (await library.assets())
        .where((asset) => !asset.missing && !_hiddenIds.contains(asset.id))
        .toList();
    if (!mounted || !identical(library, _library)) return;
    var target = parent;
    final picked = selection == null
        ? null
        : active.where((a) => selection.any((s) => s.id == a.id)).toList();
    if (picked != null) {
      if (picked.isEmpty) return;
      // Start on the most specific tag with children that every selected
      // image carries, if any.
      final shared = tags.where(
        (tag) =>
            tags.any((child) => child.parentId == tag.id) &&
            picked.every((a) => a.tagIds.contains(tag.id)),
      );
      int depth(LibraryTag tag) {
        var d = 0;
        for (var id = tag.parentId; id != null; d++) {
          id = tags.where((t) => t.id == id).firstOrNull?.parentId;
        }
        return d;
      }

      final plan = await showDialog<AiSortPlan>(
        context: context,
        builder: (_) => AiSortSetupDialog(
          tags: tags,
          untagged: picked.length,
          narrowable: {
            for (final tag in tags)
              if (tags.any((child) => child.parentId == tag.id))
                tag.id: picked.length,
          },
          initialParent: shared.isEmpty
              ? null
              : shared.reduce((a, b) => depth(a) >= depth(b) ? a : b).id,
          selectionCount: picked.length,
        ),
      );
      if (plan == null || !mounted) return;
      target = plan.parent;
    } else if (chooseMode) {
      final plan = await showDialog<AiSortPlan>(
        context: context,
        builder: (_) => AiSortSetupDialog(
          tags: tags,
          untagged: active.where((a) => a.tagIds.isEmpty).length,
          narrowable: {
            for (final tag in tags)
              if (tags.any((child) => child.parentId == tag.id))
                tag.id: narrowQueue(tag, tags, active).length,
          },
          initialParent: target?.id,
        ),
      );
      if (plan == null || !mounted) return;
      target = plan.parent;
    }
    final candidates = childTags(target?.id, tags);
    final queue =
        picked ??
        (target == null
            ? active.where((a) => a.tagIds.isEmpty).toList()
            : narrowQueue(target, tags, active));
    if (candidates.isEmpty || queue.isEmpty) {
      setState(
        () => _status = candidates.isEmpty
            ? 'AI sort needs ${target == null ? 'top-level tags' : 'child tags under “${target.name}”'}'
            : 'Nothing to sort: ${target == null ? 'no untagged images' : 'every image in “${target.name}” already has a child tag'}',
      );
      return;
    }
    await similarity.start();
    if (similarity.error != null || similarity.model == null) {
      throw LibraryException(
        'The similarity index needs attention: ${similarity.error}',
      );
    }
    final key = similarity.model!.key;
    setState(() => _status = 'Preparing AI sort…');
    // Tag names are a secondary signal: without the text encoder, sort by
    // the images already in each tag alone.
    final notices = <String>[];
    final names = <String, List<double>>{};
    try {
      for (final tag in candidates) {
        final cacheKey = '$key|${tag.name}';
        var vector = _tagNameVectors[cacheKey];
        if (vector == null) {
          final embedded = await _suggestionBackend.embedText(tag.name);
          if (embedded.embeddingKey != key) {
            throw StateError('the text and image models do not match');
          }
          vector = _tagNameVectors[cacheKey] = embedded.vector;
        }
        names[tag.id] = vector;
      }
    } catch (error) {
      names.clear();
      notices.add(
        'Tag names are not used ($error); suggestions come from the images '
        'already in each tag.',
      );
    }
    if (!mounted || !identical(library, _library)) return;
    final references = candidates.where((t) => t.isReference).length;
    if (references > 0) {
      notices.add(
        '$references reference ${references == 1 ? 'tag is' : 'tags are'} '
        'among the choices: images sorted there only show when you filter '
        'by that tag.',
      );
    }
    final byId = {for (final tag in candidates) tag.id: tag};
    final session = '${library.id}/${DateTime.now().microsecondsSinceEpoch}';
    AiSortResult? result;
    try {
      result = await showDialog<AiSortResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AiSortDialog(
          title: target == null
              ? 'Sort untagged images'
              : 'Narrow “${target.name}”',
          queue: queue,
          candidates: candidates,
          notice: notices.isEmpty ? null : notices.join('\n'),
          thumbnail: library.thumbnail,
          score: (asset) async {
            if (_closingWindow || !identical(library, _library)) {
              throw StateError('Library closed.');
            }
            // Indexes the image first when it has no vector yet.
            await similarity.ensure(asset);
            final rows =
                (await library.similarity({
                          'op': 'sortScores',
                          'key': key,
                          'session': session,
                          'candidates': [
                            for (final tag in candidates)
                              {'id': tag.id, 'nameVector': names[tag.id]},
                          ],
                          'assetIds': [asset.id],
                        })
                        as Map)[asset.id]
                    as List?;
            if (rows == null) {
              throw StateError('This image has no similarity vector yet.');
            }
            return [
              for (final row in rows.cast<Map>())
                AiSortSuggestion.fromMap(row, byId[row['tagId']]!),
            ];
          },
          apply: (asset, tag) =>
              library.editTags([asset.id], add: [tag.id], remove: const []),
          undo: (asset, tag) =>
              library.editTags([asset.id], add: const [], remove: [tag.id]),
        ),
      );
    } finally {
      if (identical(library, _library)) {
        try {
          await library.similarity({'op': 'sortEnd'});
        } catch (_) {}
      }
      if (mounted && !_closingWindow && identical(library, _library)) {
        await _reload();
      }
    }
    if (mounted && result != null) {
      final done = result;
      setState(
        () => _status =
            'AI sort: tagged ${done.accepted}, skipped ${done.skipped}'
            '${done.remaining > 0 ? ', ${done.remaining} not reviewed' : ''}',
      );
    }
  });

  /// Replaces the library copy of [asset] with a [width]×[height] version and
  /// sends the previous file to the Recycle Bin.
  Future<void> _applyResize(
    LibraryStore library,
    LibraryAsset asset,
    int width,
    int height,
  ) async {
    // Windows keeps file mappings until decoded images are released.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await library.resizeAsset(asset.id, width: width, height: height);
    _thumbnails.remove(library.absolutePath(asset.relativePath));
    await _emptyLibraryTrash(library);
  }

  void _openPreviewExternally() {
    if (_selectedPaths.isNotEmpty) _openImageExternally(_selectedPaths.first);
  }

  void _openImageExternally(String path) {
    final asset = _assetsByPath[path];
    if (asset != null) _openAssetExternally(asset);
  }

  // Opens via the runner's own channel rather than url_launcher, which calls
  // ShellExecute on the UI thread: Windows can take seconds to load its shell
  // components the first time, freezing the whole window meanwhile.
  static const _shellChannel = MethodChannel('umbra_tags/shell');

  void _openAssetExternally(LibraryAsset asset) => _run(() async {
    if (_library == null) return;
    final file = File(_library!.absolutePath(asset.relativePath));
    if (!await file.exists()) {
      throw LibraryException('This image file is missing from the library.');
    }
    if (await _shellChannel.invokeMethod<bool>('openFile', file.path) != true) {
      throw LibraryException(
        'Could not open this image. Choose a default app for its file type in your system settings.',
      );
    }
  });

  static const _clipboardChannel = MethodChannel('umbra_tags/clipboard');

  void _copyImageToClipboard(String path) => _run(() async {
    final asset = _assetsByPath[path];
    if (asset == null || _library == null) return;
    final file = File(_library!.absolutePath(asset.relativePath));
    if (!await file.exists()) {
      throw LibraryException('This image file is missing from the library.');
    }
    // The native side decodes with GDI+, which has no WebP codec.
    if (p.extension(file.path).toLowerCase() != '.webp') {
      await _clipboardChannel.invokeMethod<void>('copyImage', file.path);
      return;
    }
    final source = file.path;
    final png = await Isolate.run(() {
      final decoded = img.decodeImage(File(source).readAsBytesSync());
      return decoded == null ? null : img.encodePng(decoded);
    });
    if (png == null) throw LibraryException('Could not decode this image.');
    final temp = File(
      p.join(Directory.systemTemp.path, 'umbra-tags-clipboard.png'),
    );
    await temp.writeAsBytes(png, flush: true);
    await _clipboardChannel.invokeMethod<void>('copyImage', temp.path);
  });

  void _archiveSelection() => _run(() async {
    await _library!.archive(
      _selectedPaths.map((path) => _assetsByPath[path]!.id).toList(),
      !_showArchived,
    );
    await _reload();
  });

  void _refreshLibrary() => _run(() async {
    await _library!.refresh();
    _thumbnails.clear();
    await _reload();
  });

  void _backupLibrary() => _run(() async {
    final backup = await _library!.backup();
    if (mounted) {
      setState(() => _status = 'Metadata backup saved: ${p.basename(backup)}');
    }
  });

  bool _maximized = false;

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowClose() async {
    if (_closingWindow) return;
    if (_minimizeToTray && !_quitRequested) {
      await _hideToTray();
      return;
    }
    _closeRequested = true;
    _cancelClassification = true;
    setState(() {
      _closingWindow = true;
      _status = 'Closing…';
    });
    final timer = Stopwatch()..start();
    final timings = <String>['Shutdown ${DateTime.now().toIso8601String()}'];
    Future<void> step(String name, Future<void> Function() action) async {
      final stage = Stopwatch()..start();
      try {
        await action();
      } catch (error) {
        timings.add('$name failed: $error');
        debugPrint('Shutdown $name failed: $error');
      } finally {
        timings.add('$name: ${stage.elapsedMilliseconds} ms');
        debugPrint('Shutdown $name: ${stage.elapsedMilliseconds} ms');
      }
    }

    _rememberScrollPosition();
    _resizeTimer?.cancel();
    _sessionTimer?.cancel();
    _library?.cancelBackgroundWork();
    // Dismiss review/configuration dialogs so _run can finish. In-flight
    // catalog transactions still complete before the library is closed.
    Navigator.of(context).popUntil((route) => route.isFirst);
    _writeSession();
    final operationIdle = _operationIdle?.future;
    await Future.wait([
      step('settings', () => _sessionWrite),
      step('receiver', () async {
        await _receiver?.close();
      }),
      step('standby model', () async {
        await _standbyEmbedder?.dispose();
      }),
      step('tag model', () async {
        await _tagSuggester?.dispose();
      }),
      step('classifier', () async {
        await _classifier?.dispose();
      }),
      step('similarity', _stopSimilarity),
      step('active operation', () async {
        await operationIdle;
      }),
      step('options save', () async {
        await _applyingOptions;
      }),
    ]);
    _standbyEmbedder = null;
    _tagSuggester = null;
    _classifier = null;
    await step('pending delete', _commitPendingDelete);
    await step('library', () async {
      await _library?.close();
    });
    await step('final settings', () => _sessionWrite);
    debugPrint('Shutdown total: ${timer.elapsedMilliseconds} ms');
    timings.add('Total: ${timer.elapsedMilliseconds} ms');
    // Keep the last shutdown breakdown available in installed Release builds.
    // Diagnostic I/O must never prevent the window from closing.
    try {
      await (() async {
        final settings = widget.sessionFile ?? await _sessionFile();
        await File(
          p.join(settings.parent.path, 'shutdown-timing.log'),
        ).writeAsString('${timings.join('\n')}\n');
      })().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    if (_inTray) {
      try {
        await tray.trayManager.destroy();
      } catch (_) {}
    }
    await windowManager.destroy();
  }

  /// Quits for real, even when closing normally hides to the tray.
  void _quit() {
    _quitRequested = true;
    windowManager.close();
  }

  Future<void> _hideToTray() async {
    try {
      if (!_inTray) {
        await tray.trayManager.setIcon('assets/tray_icon.ico');
        await tray.trayManager.setToolTip('Umbra Tags');
        await tray.trayManager.setContextMenu(
          tray.Menu(
            items: [
              tray.MenuItem(key: 'open', label: 'Open Umbra Tags'),
              tray.MenuItem.separator(),
              tray.MenuItem(key: 'quit', label: 'Quit'),
            ],
          ),
        );
        _inTray = true;
      }
    } catch (_) {
      // Without a tray icon there would be no way back to a hidden window.
      _quit();
      return;
    }
    // Save now: while hidden, the next exit may be a Windows sign-out.
    _rememberScrollPosition();
    _writeSession();
    await windowManager.hide();
  }

  Future<void> _showFromTray() async {
    await windowManager.show();
    await windowManager.focus();
    if (_inTray) {
      _inTray = false;
      await tray.trayManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() => _showFromTray();

  @override
  void onTrayIconRightMouseDown() => tray.trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    if (menuItem.key == 'open') _showFromTray();
    if (menuItem.key == 'quit') _quit();
  }

  void _onLayoutWidth(double width) {
    if (width == _committedWidth) return;
    _pendingWidth = width;
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _committedWidth = _pendingWidth);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_focusSearchOnCtrlK);
    _searchField.dispose();
    _searchFocus.dispose();
    _rememberScrollPosition();
    _resizeTimer?.cancel();
    _sessionTimer?.cancel();
    if (!_closingWindow) _writeSession();
    windowManager.removeListener(this);
    tray.trayManager.removeListener(this);
    unawaited(_standbyEmbedder?.dispose() ?? Future<void>.value());
    unawaited(_receiver?.close() ?? Future<void>.value());
    unawaited(_tagSuggester?.dispose() ?? Future<void>.value());
    unawaited(_classifier?.dispose() ?? Future<void>.value());
    final library = _library;
    unawaited(_stopSimilarity().then((_) => library?.close()));
    _scrollController.dispose();
    _galleryFocus.dispose();
    super.dispose();
  }

  int _columnCount(double availableWidth) =>
      (availableWidth / _tileSize).floor().clamp(1, 999);

  Rect? get _selectionRect {
    if (_dragStart == null || _dragCurrent == null) return null;
    return Rect.fromPoints(_dragStart!, _dragCurrent!);
  }

  String? _tileAt(Offset position) {
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null) return null;
    for (final path in _imagePaths) {
      final tileBox =
          _tileKeys[path]?.currentContext?.findRenderObject() as RenderBox?;
      if (tileBox == null) continue;
      final offset = tileBox.localToGlobal(Offset.zero, ancestor: gridBox);
      if ((offset & tileBox.size).contains(position)) return path;
    }
    return null;
  }

  // Drags the selection, or just the pressed tile when it is not selected.
  // The native drag loop runs until the drop; drops back onto this window are
  // ignored rather than re-imported.
  Future<void> _startFileDrag(String path) async {
    if (!_selectedPaths.contains(path)) {
      setState(
        () => _selectedPaths
          ..clear()
          ..add(path),
      );
    }
    final paths = [
      for (final candidate in _imagePaths)
        if (_selectedPaths.contains(candidate) &&
            _assetsByPath[candidate]?.missing == false)
          candidate,
    ];
    if (paths.isEmpty) return;
    // Rebuild so the gallery's import drop target switches off; otherwise its
    // "Drop images to import" overlay shows as the drag leaves the window.
    setState(() => _draggingOut = true);
    try {
      // The drag starts over this window, so apply that rebuild first.
      await WidgetsBinding.instance.endOfFrame;
      await _dragChannel.invokeMethod<bool>('startFileDrag', paths);
    } on MissingPluginException {
      // Only the Windows runner can start an outgoing file drag.
    } on PlatformException {
      // Nothing was dragged; the selection is unchanged.
    } finally {
      if (mounted) setState(() => _draggingOut = false);
    }
  }

  void _updateMarqueeSelection() {
    final rect = _selectionRect;
    if (rect == null) return;
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null) return;

    final selected = <String>{};
    for (final path in _imagePaths) {
      final tileBox =
          _tileKeys[path]?.currentContext?.findRenderObject() as RenderBox?;
      if (tileBox == null) continue;
      // Convert tile position to grid-local coordinates
      final tileOffset = tileBox.localToGlobal(Offset.zero, ancestor: gridBox);
      final tileRect = tileOffset & tileBox.size;
      if (rect.overlaps(tileRect)) selected.add(path);
    }
    setState(
      () => _selectedPaths
        ..clear()
        ..addAll(selected),
    );
  }

  /// Menus on the left, the search field centred in the space between, then
  /// layout, zoom, preview and Import on the right.
  Widget _topBar(Widget menus) => Row(
    children: [
      menus,
      // Empty space either side of the search moves the window, like a
      // native title bar; double-click maximizes.
      // The middle takes all free space, so the right-hand group always ends
      // at the window edge; the search sits centred within it.
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              const Expanded(child: _TitleDragArea()),
              SizedBox(
                width: math.min(460, math.max(0, box.maxWidth - 48)),
                child: _searchBox(),
              ),
              const Expanded(child: _TitleDragArea()),
            ],
          ),
        ),
      ),
      SegmentedButton<LayoutMode>(
        style: const ButtonStyle(
          visualDensity: VisualDensity(horizontal: -2, vertical: -2),
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        segments: const [
          ButtonSegment(
            value: LayoutMode.crop,
            icon: Icon(
              Icons.grid_view_rounded,
              size: 18,
              semanticLabel: 'Crop',
            ),
            tooltip: 'Crop — fill uniform tiles',
          ),
          ButtonSegment(
            value: LayoutMode.letterbox,
            icon: Icon(
              Icons.fit_screen_rounded,
              size: 18,
              semanticLabel: 'Fit',
            ),
            tooltip: 'Fit — show the whole image',
          ),
          ButtonSegment(
            value: LayoutMode.masonry,
            icon: Icon(
              Icons.view_quilt_rounded,
              size: 18,
              semanticLabel: 'Masonry',
            ),
            tooltip: 'Masonry — arrange by image proportions',
          ),
        ],
        showSelectedIcon: false,
        selected: {_layout},
        onSelectionChanged: (s) {
          setState(() => _layout = s.first);
          _persistSession();
        },
      ),
      const SizedBox(width: 18),
      // Zoom: small square, thin track with a square thumb, large square.
      const Icon(Icons.square, size: 9, semanticLabel: 'Smaller tiles'),
      SizedBox(
        width: 130,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 1.5,
            thumbShape: const SquareSliderThumb(size: 12),
            overlayShape: SliderComponentShape.noOverlay,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: _tileSize,
            min: 50,
            max: 400,
            onChanged: (v) {
              setState(() => _tileSize = v);
              _persistSession();
            },
          ),
        ),
      ),
      const Icon(Icons.square, size: 15, semanticLabel: 'Larger tiles'),
      const SizedBox(width: 14),
      IconButton(
        icon: Icon(
          _previewVisible ? Icons.view_sidebar : Icons.view_sidebar_outlined,
          size: 20,
        ),
        tooltip: _previewVisible ? 'Hide preview' : 'Show preview',
        onPressed: () {
          setState(() => _previewVisible = !_previewVisible);
          _persistSession();
        },
      ),
      if (widget.startReceiver) _receiverIndicator(),
      const SizedBox(width: 10),
      if (_library != null)
        FilledButton.icon(
          onPressed: _busy ? null : _importImages,
          style: const ButtonStyle(
            visualDensity: VisualDensity(vertical: -1),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Import'),
        ),
      const SizedBox(width: 12),
      for (final button in [
        WindowCaptionButton.minimize(
          brightness: Brightness.dark,
          onPressed: () => windowManager.minimize(),
        ),
        _maximized
            ? WindowCaptionButton.unmaximize(
                brightness: Brightness.dark,
                onPressed: () => windowManager.unmaximize(),
              )
            : WindowCaptionButton.maximize(
                brightness: Brightness.dark,
                onPressed: () => windowManager.maximize(),
              ),
        // Goes through onWindowClose, so minimize-to-tray still applies.
        WindowCaptionButton.close(
          brightness: Brightness.dark,
          onPressed: () => windowManager.close(),
        ),
      ])
        SizedBox(height: 48, child: button), // The bar's toolbarHeight.
    ],
  );

  /// The browser extension's receiver: white while listening; dimmed with an
  /// amber dot when it is off or could not start.
  Widget _receiverIndicator() {
    final listening = _receiver?.port != null;
    return Tooltip(
      message: _receiverStatus,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.browser_updated,
              size: 20,
              color: listening ? AppColors.foam : AppColors.mist,
            ),
            if (!listening)
              const Positioned(
                right: -3,
                top: -3,
                child: SizedBox.square(
                  dimension: 7,
                  child: ColoredBox(color: AppColors.star),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Ctrl+K from anywhere in the window focuses the search field.
  bool _focusSearchOnCtrlK(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyK ||
        !HardwareKeyboard.instance.isControlPressed ||
        _library == null ||
        !mounted) {
      return false;
    }
    _searchFocus.requestFocus();
    _searchField.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchField.text.length,
    );
    return true;
  }

  /// Library name, status and indexing, shown at the foot of the sidebar
  /// instead of a full-width bar.
  Widget _statusFooter() {
    const muted = TextStyle(color: AppColors.mist, fontSize: 12);
    final link = _statusLink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_busy) ...[
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _library?.name ?? 'Umbra Tags',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (_selectedPaths.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 8),
                  child: Text(
                    '${_selectedPaths.length} selected',
                    style: muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          // Another status replaces the text, which drops the link.
          if (link != null && link.text == _status)
            Tooltip(
              message: 'Show in gallery',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _busy ? null : () => _revealAsset(link.assetId),
                  child: Text(
                    _status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.haze,
                    ),
                  ),
                ),
              ),
            )
          else
            Text(
              _status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          if (_similarity != null) SimilarityStatus(controller: _similarity!),
          if (_classifying)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _cancelClassification
                    ? null
                    : () => setState(() => _cancelClassification = true),
                child: Text(
                  _cancelClassification ? 'Stopping…' : 'Cancel after image',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchBox() => TextField(
    key: const ValueKey('text-search'),
    controller: _searchField,
    focusNode: _searchFocus,
    // Start loading the text encoder on the first keystroke, so it is
    // usually ready by the time the query is submitted. A failure here
    // resurfaces on the search itself.
    onChanged: (text) {
      if (text.isNotEmpty && !_searchModelReady) {
        unawaited(_warmSearchModel().catchError((Object _) {}));
      }
    },
    enabled: _library != null,
    onSubmitted: _searchByText,
    textInputAction: TextInputAction.search,
    style: const TextStyle(fontSize: 13.5),
    decoration: InputDecoration(
      isDense: true,
      // Translucent on the red title bar.
      fillColor: const Color(0x611E0407),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Color(0x47FFF2F1)),
      ),
      hintText: 'Describe an image… e.g. blue city at night',
      prefixIcon: const Icon(Icons.search, size: 18),
      suffixIcon: _textQuery == null && _similarTo == null
          ? const _KeyCap('Ctrl K')
          : IconButton(
              tooltip: _similarTo != null
                  ? 'Back to all images'
                  : 'Clear search',
              icon: const Icon(Icons.close, size: 18),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      _endTextSearch();
                      await _reload();
                    }),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: _topBar(
          MenuBar(
            style: const MenuStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            children: [
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: _busy ? null : _createLibrary,
                    child: const Text('New library…'),
                  ),
                  MenuItemButton(
                    onPressed: _busy ? null : _openLibrary,
                    child: const Text('Open library…'),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _library == null ? null : _importImages,
                    child: const Text('Import images…'),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _library == null
                        ? null
                        : _importFromDownloads,
                    child: const Text('Import from Downloads…'),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _library == null
                        ? null
                        : _backupLibrary,
                    child: const Text('Back up metadata'),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _library == null ? null : _closeLibrary,
                    child: const Text('Close library'),
                  ),
                  const Divider(),
                  MenuItemButton(
                    onPressed: _busy ? null : _quit,
                    child: const Text('Quit'),
                  ),
                ],
                child: const Text('File'),
              ),
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: _imagePaths.isEmpty
                        ? null
                        : () {
                            _galleryFocus.requestFocus();
                            setState(() => _selectedPaths.addAll(_imagePaths));
                          },
                    child: const Text('Select all'),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _selectedPaths.isEmpty
                        ? null
                        : _editSelectionTags,
                    child: const Text('Edit tags…'),
                  ),
                  if (_mlClassifyEnabled)
                    MenuItemButton(
                      onPressed: _busy || _selectedPaths.isEmpty
                          ? null
                          : _classifySelection,
                      child: const Text('ML classify'),
                    ),
                  if (_aiSortEnabled)
                    MenuItemButton(
                      onPressed: _busy || _library == null
                          ? null
                          : () => _aiSort(chooseMode: true),
                      child: const Text('AI sort…'),
                    ),
                  MenuItemButton(
                    onPressed: _busy || _library == null
                        ? null
                        : _resizeLargeImages,
                    child: const Text('Resize large images…'),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _warmingModels || !_sessionRestored
                        ? null
                        : _configureOptions,
                    child: const Text('Options…'),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _selectedPaths.isEmpty
                        ? null
                        : _archiveSelection,
                    child: Text(
                      _showArchived ? 'Restore selected' : 'Archive selected',
                    ),
                  ),
                ],
                child: const Text('Edit'),
              ),
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: () {
                      setState(
                        () => _tileSize = (_tileSize + 25).clamp(50, 400),
                      );
                      _persistSession();
                    },
                    child: const Text('Zoom in'),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _library == null
                        ? null
                        : () => _run(() async {
                            _showArchived = !_showArchived;
                            _untagged = false;
                            _tagFilter = null;
                            await _reload();
                          }),
                    child: Text(
                      _showArchived ? 'Show library' : 'Show archive',
                    ),
                  ),
                  MenuItemButton(
                    onPressed: _busy || _library == null
                        ? null
                        : _refreshLibrary,
                    child: const Text('Refresh files'),
                  ),
                  MenuItemButton(
                    onPressed: () {
                      setState(
                        () => _tileSize = (_tileSize - 25).clamp(50, 400),
                      );
                      _persistSession();
                    },
                    child: const Text('Zoom out'),
                  ),
                  MenuItemButton(
                    leadingIcon: Icon(
                      _showTileTags
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() => _showTileTags = !_showTileTags);
                      _persistSession();
                    },
                    child: const Text('Show tags on images'),
                  ),
                ],
                child: const Text('View'),
              ),
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => showAboutDialog(
                      context: context,
                      applicationName: 'Umbra Tags',
                      applicationVersion: 'Library format 1',
                    ),
                    child: const Text('About'),
                  ),
                ],
                child: const Text('Help'),
              ),
            ],
          ),
        ),
        titleSpacing: 0,
      ),
      body: _library == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 48,
                    color: Colors.white38,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Your images. Your library.',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keep each library in a folder you choose.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _createLibrary,
                        child: const Text('New library'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : _openLibrary,
                        child: const Text('Open library'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _status,
                    style: const TextStyle(color: AppColors.mist, fontSize: 12),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                TagSidebar(
                  width: _sidebarWidth,
                  footer: _statusFooter(),
                  tags: _tags,
                  viewCounts: _viewCounts,
                  view: _showArchived
                      ? LibraryView.archived
                      : _untagged
                      ? LibraryView.untagged
                      : LibraryView.all,
                  selectedTag: _tagFilter,
                  busy: _busy,
                  onView: (view) => _setFilter(view),
                  onSelect: (id) => _setFilter(LibraryView.all, id),
                  onCreate: (parent) => _editTag(parent: parent),
                  onEdit: (tag) => _editTag(tag: tag),
                  onDelete: _deleteTag,
                  onFindMatches: _findTagMatches,
                  onSortChildren: _aiSortEnabled
                      ? (tag) => _aiSort(parent: tag)
                      : null,
                  onToggleExcluded: _toggleTagExcluded,
                  collapsedTags: _collapsedTags,
                  onToggleCollapsed: (id) {
                    setState(() {
                      if (!_collapsedTags.remove(id)) _collapsedTags.add(id);
                    });
                    _persistSession();
                  },
                ),
                // Drag handle
                GestureDetector(
                  onHorizontalDragUpdate: (d) => setState(() {
                    _sidebarWidth = (_sidebarWidth + d.delta.dx).clamp(
                      _sidebarMinWidth,
                      _sidebarMaxWidth,
                    );
                    _persistSession();
                  }),
                  child: MouseRegion(
                    key: const ValueKey('sidebar-resize-handle'),
                    cursor: SystemMouseCursors.resizeColumn,
                    child: Container(width: 6, color: AppColors.rule),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      ViewBreadcrumbs(
                        tags: _tags,
                        view: _showArchived
                            ? LibraryView.archived
                            : _untagged
                            ? LibraryView.untagged
                            : LibraryView.all,
                        tagId: _tagFilter,
                        onView: _busy ? null : (view) => _setFilter(view),
                        onTag: _busy
                            ? null
                            : (id) => _setFilter(LibraryView.all, id),
                        starredOnly: _starredOnly,
                        onToggleStarred: _busy ? null : _toggleStarredOnly,
                        order: _order,
                        onOrder: _busy ? null : _setOrder,
                        action: _aiSortAction,
                      ),
                      Expanded(
                        child: GalleryDropTarget(
                          enabled: !_busy && !_closingWindow && !_draggingOut,
                          onFiles: (files) {
                            if (!_draggingOut) {
                              _run(() => _importImageFiles(files));
                            }
                          },
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              _onLayoutWidth(constraints.maxWidth);
                              final width = _committedWidth > 0
                                  ? _committedWidth
                                  : constraints.maxWidth;
                              final cols = _columnCount(width);

                              if (_assets.isEmpty) {
                                return Center(
                                  child: Text(
                                    _showArchived
                                        ? 'No archived images'
                                        : _tagFilter != null || _untagged
                                        ? 'No images match this filter'
                                        : 'Import images to fill this library',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                                );
                              }
                              Widget grid;
                              if (_pendingScrollOffset != null) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _restoreScrollPosition(),
                                );
                              }
                              if (_layout == LayoutMode.masonry) {
                                grid = ExactMasonryView(
                                  key: _gridKey,
                                  controller: _scrollController,
                                  columns: cols,
                                  spacing: 8,
                                  aspectRatios: [
                                    for (final asset in _assets)
                                      asset.width / asset.height,
                                  ],
                                  itemBuilder: (context, index) => GalleryTile(
                                    key: _tileKeys[_imagePaths[index]],
                                    path: _imagePaths[index],
                                    thumbnail: _thumbnailFor(
                                      _imagePaths[index],
                                    ),
                                    aspectRatio:
                                        _assets[index].width /
                                        _assets[index].height,
                                    filename: _assets[index].originalFilename,
                                    tileSize: _tileSize,
                                    layout: _layout,
                                    selected: _selectedPaths.contains(
                                      _imagePaths[index],
                                    ),
                                    onDoubleTap: _busy
                                        ? null
                                        : () => _openImageExternally(
                                            _imagePaths[index],
                                          ),
                                    onContextSelect: () =>
                                        _selectContextImage(_imagePaths[index]),
                                    onCopyImage: _busy
                                        ? null
                                        : () => _copyImageToClipboard(
                                            _imagePaths[index],
                                          ),
                                    onEditTags: _busy
                                        ? null
                                        : _editSelectionTags,
                                    onArchive: _busy ? null : _archiveSelection,
                                    archived: _showArchived,
                                    onDelete: _busy ? null : _deleteSelection,
                                    onRefine: !_refineEnabled || _busy
                                        ? null
                                        : _refineSelection,
                                    canRefine: _canRefineSelection,
                                    onAiSort:
                                        !_aiSortEnabled ||
                                            _busy ||
                                            _showArchived
                                        ? null
                                        : () => _aiSort(selection: _selection),
                                    onSimilar: _busy
                                        ? null
                                        : () => _findSimilar(_assets[index]),
                                    onResize: _busy || _showArchived
                                        ? null
                                        : () => _resizeImage(_assets[index]),
                                    onTagDropped: _busy
                                        ? null
                                        : (tag) => _applyDroppedTag(
                                            _imagePaths[index],
                                            tag,
                                          ),
                                    tagDropCount:
                                        _selectedPaths.contains(
                                          _imagePaths[index],
                                        )
                                        ? _selectedPaths.length
                                        : 1,
                                    starred: _assets[index].starred,
                                    tagNames: _showTileTags
                                        ? _tileTagNames(_assets[index])
                                        : const [],
                                    starWillSet: _starWillSet(
                                      _imagePaths[index],
                                    ),
                                    onToggleStar: _busy
                                        ? null
                                        : () => _toggleStar(_imagePaths[index]),
                                  ),
                                );
                              } else {
                                grid = GridView.builder(
                                  key: _gridKey,
                                  controller: _scrollController,
                                  itemCount: _imagePaths.length,
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: _tileSize,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 8,
                                      ),
                                  itemBuilder: (context, index) => GalleryTile(
                                    key: _tileKeys[_imagePaths[index]],
                                    path: _imagePaths[index],
                                    thumbnail: _thumbnailFor(
                                      _imagePaths[index],
                                    ),
                                    aspectRatio:
                                        _assets[index].width /
                                        _assets[index].height,
                                    filename: _assets[index].originalFilename,
                                    tileSize: _tileSize,
                                    layout: _layout,
                                    selected: _selectedPaths.contains(
                                      _imagePaths[index],
                                    ),
                                    onDoubleTap: _busy
                                        ? null
                                        : () => _openImageExternally(
                                            _imagePaths[index],
                                          ),
                                    onContextSelect: () =>
                                        _selectContextImage(_imagePaths[index]),
                                    onCopyImage: _busy
                                        ? null
                                        : () => _copyImageToClipboard(
                                            _imagePaths[index],
                                          ),
                                    onEditTags: _busy
                                        ? null
                                        : _editSelectionTags,
                                    onArchive: _busy ? null : _archiveSelection,
                                    archived: _showArchived,
                                    onDelete: _busy ? null : _deleteSelection,
                                    onRefine: !_refineEnabled || _busy
                                        ? null
                                        : _refineSelection,
                                    canRefine: _canRefineSelection,
                                    onAiSort:
                                        !_aiSortEnabled ||
                                            _busy ||
                                            _showArchived
                                        ? null
                                        : () => _aiSort(selection: _selection),
                                    onSimilar: _busy
                                        ? null
                                        : () => _findSimilar(_assets[index]),
                                    onResize: _busy || _showArchived
                                        ? null
                                        : () => _resizeImage(_assets[index]),
                                    onTagDropped: _busy
                                        ? null
                                        : (tag) => _applyDroppedTag(
                                            _imagePaths[index],
                                            tag,
                                          ),
                                    tagDropCount:
                                        _selectedPaths.contains(
                                          _imagePaths[index],
                                        )
                                        ? _selectedPaths.length
                                        : 1,
                                    starred: _assets[index].starred,
                                    tagNames: _showTileTags
                                        ? _tileTagNames(_assets[index])
                                        : const [],
                                    starWillSet: _starWillSet(
                                      _imagePaths[index],
                                    ),
                                    onToggleStar: _busy
                                        ? null
                                        : () => _toggleStar(_imagePaths[index]),
                                  ),
                                );
                              }

                              return Focus(
                                focusNode: _galleryFocus,
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent &&
                                      event.logicalKey ==
                                          LogicalKeyboardKey.delete &&
                                      !_busy &&
                                      _selectedPaths.isNotEmpty) {
                                    _deleteSelection();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: ScrollConfiguration(
                                  behavior: _GalleryScrollBehavior(),
                                  child: Scrollbar(
                                    controller: _scrollController,
                                    thumbVisibility: true,
                                    interactive: true,
                                    scrollbarOrientation:
                                        ScrollbarOrientation.right,
                                    thickness: 8,
                                    radius: const Radius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 20),
                                      // Keep scrollbar drags outside selection hit testing.
                                      child: Listener(
                                        onPointerDown: (e) {
                                          final keys =
                                              HardwareKeyboard.instance;
                                          _toggleOnTap =
                                              keys.isControlPressed ||
                                              keys.isMetaPressed;
                                          _rangeOnTap = keys.isShiftPressed;
                                          _collapseOnRelease = null;
                                          if (_busy ||
                                              e.buttons != kPrimaryButton) {
                                            return;
                                          }
                                          // Select on press, like Explorer:
                                          // tiles also wait out the double-
                                          // click window before a tap fires,
                                          // and Delete in that gap acted on
                                          // the previous selection.
                                          final pressed = keys.isAltPressed
                                              ? null
                                              : _tileAt(e.localPosition);
                                          if (pressed != null) {
                                            if (!_toggleOnTap &&
                                                !_rangeOnTap &&
                                                _selectedPaths.length > 1 &&
                                                _selectedPaths.contains(
                                                  pressed,
                                                )) {
                                              _collapseOnRelease = pressed;
                                            } else {
                                              _selectImage(pressed);
                                            }
                                          }
                                          // Marquee and file drags: left mouse
                                          // button only.
                                          if (e.kind !=
                                              PointerDeviceKind.mouse) {
                                            _galleryFocus.requestFocus();
                                            return;
                                          }
                                          _galleryFocus.requestFocus();
                                          if (keys.isAltPressed) {
                                            setState(() {
                                              _dragStart = e.localPosition;
                                              _dragCurrent = e.localPosition;
                                            });
                                          } else {
                                            _fileDragOrigin = e.localPosition;
                                            _fileDragPath = _tileAt(
                                              e.localPosition,
                                            );
                                          }
                                        },
                                        onPointerMove: (e) {
                                          if (_dragStart != null) {
                                            setState(
                                              () => _dragCurrent =
                                                  e.localPosition,
                                            );
                                            _updateMarqueeSelection();
                                          } else if (_fileDragPath != null &&
                                              (e.localPosition -
                                                          _fileDragOrigin!)
                                                      .distance >
                                                  kTouchSlop / 3) {
                                            final path = _fileDragPath!;
                                            _fileDragPath = _fileDragOrigin =
                                                null;
                                            _collapseOnRelease = null;
                                            _startFileDrag(path);
                                          }
                                        },
                                        onPointerUp: (_) {
                                          final collapse = _collapseOnRelease;
                                          _collapseOnRelease = null;
                                          setState(() {
                                            _dragStart = null;
                                            _dragCurrent = null;
                                            _fileDragPath = _fileDragOrigin =
                                                null;
                                          });
                                          if (collapse != null) {
                                            _selectImage(collapse);
                                          }
                                        },
                                        onPointerCancel: (_) => setState(() {
                                          _collapseOnRelease = null;
                                          _dragStart = null;
                                          _dragCurrent = null;
                                          _fileDragPath = _fileDragOrigin =
                                              null;
                                        }),
                                        child: Stack(
                                          children: [
                                            grid,
                                            if (_queryVector != null &&
                                                _searchHasMore &&
                                                !_resultsStillRelevant)
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 16,
                                                child: Center(
                                                  child: FilledButton.icon(
                                                    key: const ValueKey(
                                                      'search-show-more',
                                                    ),
                                                    onPressed:
                                                        _loadingMoreResults
                                                        ? null
                                                        : _loadMoreResults,
                                                    icon: const Icon(
                                                      Icons.expand_more,
                                                    ),
                                                    label: const Text(
                                                      'Show $_searchPage more (less similar)',
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (_selectionRect != null)
                                              Positioned.fill(
                                                child: IgnorePointer(
                                                  child: CustomPaint(
                                                    painter: _MarqueePainter(
                                                      _selectionRect!,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_previewVisible) ...[
                  // Drag handle
                  GestureDetector(
                    onHorizontalDragUpdate: (d) => setState(() {
                      _previewWidth = (_previewWidth - d.delta.dx).clamp(
                        150,
                        800,
                      );
                      _persistSession();
                    }),
                    child: MouseRegion(
                      key: const ValueKey('preview-resize-handle'),
                      cursor: SystemMouseCursors.resizeColumn,
                      child: Container(width: 6, color: AppColors.rule),
                    ),
                  ),
                  // Preview pane
                  SizedBox(
                    width: _previewWidth.clamp(
                      150,
                      (MediaQuery.sizeOf(context).width - 500).clamp(150, 800),
                    ),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: AppColors.darker),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SizedBox.expand(
                              child: _selectedPaths.isNotEmpty
                                  ? Image.file(
                                      File(_selectedPaths.first),
                                      fit: BoxFit.contain,
                                      cacheWidth:
                                          (_previewWidth *
                                                  MediaQuery.devicePixelRatioOf(
                                                    context,
                                                  ))
                                              .ceil(),
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Text(
                                          'Original file is missing or unreadable',
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Text(
                                        'No image selected',
                                        style: TextStyle(color: Colors.white24),
                                      ),
                                    ),
                            ),
                          ),
                          if (_selectedPaths.isNotEmpty)
                            AmbientGlass(
                              colors: _ambientFor(_selectedPaths.first),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  PreviewDetails(
                                    asset: _assetsByPath[_selectedPaths.first]!,
                                    selectionCount: _selectedPaths.length,
                                  ),
                                  const Divider(
                                    height: 25,
                                    indent: 16,
                                    endIndent: 16,
                                    color: Colors.white12,
                                  ),
                                  SelectionTags(
                                    tags: _tags,
                                    assets: _selection,
                                  ),
                                  const Divider(
                                    height: 25,
                                    indent: 16,
                                    endIndent: 16,
                                    color: Colors.white12,
                                  ),
                                  OpenExternallyButton(
                                    onOpen:
                                        _busy ||
                                            _assetsByPath[_selectedPaths.first]!
                                                .missing
                                        ? null
                                        : _openPreviewExternally,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class GalleryTile extends StatelessWidget {
  const GalleryTile({
    super.key,
    required this.path,
    required this.thumbnail,
    required this.aspectRatio,
    required this.filename,
    required this.tileSize,
    required this.layout,
    required this.selected,
    this.onTap,
    this.onDoubleTap,
    this.onContextSelect,
    this.onCopyImage,
    this.onEditTags,
    this.onArchive,
    this.archived = false,
    this.onDelete,
    this.onAiSort,
    this.onRefine,
    this.canRefine,
    this.onSimilar,
    this.onResize,
    this.onTagDropped,
    this.tagDropCount = 1,
    this.starred = false,
    this.tagNames = const [],
    this.starWillSet = true,
    this.onToggleStar,
  });

  final String path;
  final Future<String?> thumbnail;
  final double aspectRatio;
  final String filename;
  final double tileSize;
  final LayoutMode layout;
  final bool selected, archived;
  final bool Function()? canRefine;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap,
      onContextSelect,
      onCopyImage,
      onEditTags,
      onArchive,
      onDelete,
      onRefine,
      onAiSort,
      onSimilar,
      onResize;

  /// Assigns a tag dragged from the sidebar; [tagDropCount] images receive it.
  final ValueChanged<LibraryTag>? onTagDropped;
  final int tagDropCount;

  /// Whether this image is starred (shows a badge), whether the menu's star
  /// action would star or unstar its targets, and that action.
  final bool starred, starWillSet;

  /// Shown along the bottom edge, over the image.
  final List<String> tagNames;
  final VoidCallback? onToggleStar;

  @override
  Widget build(BuildContext context) {
    final image = FutureBuilder<String?>(
      future: thumbnail,
      builder: (context, snapshot) {
        final placeholder = ColoredBox(
          color: Colors.white10,
          child: Center(
            child: Icon(
              snapshot.connectionState == ConnectionState.waiting
                  ? Icons.image_outlined
                  : Icons.broken_image_outlined,
              color: Colors.white24,
            ),
          ),
        );
        if (snapshot.data == null) return placeholder;
        return LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.devicePixelRatioOf(context);
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final decodeByHeight =
                layout == LayoutMode.crop &&
                height.isFinite &&
                aspectRatio > width / height;
            return Image.file(
              File(snapshot.data!),
              fit: layout == LayoutMode.crop ? BoxFit.cover : BoxFit.contain,
              cacheWidth: decodeByHeight
                  ? null
                  : (width * scale).ceil().clamp(1, 1280),
              cacheHeight: decodeByHeight
                  ? (height * scale).ceil().clamp(1, 1280)
                  : null,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => placeholder,
            );
          },
        );
      },
    );
    return DragTarget<LibraryTag>(
      onWillAcceptWithDetails: (_) => onTagDropped != null,
      onAcceptWithDetails: (details) => onTagDropped?.call(details.data),
      builder: (context, candidates, _) => GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
        child: Stack(
          fit: layout == LayoutMode.masonry ? StackFit.loose : StackFit.expand,
          children: [
            layout == LayoutMode.masonry
                ? AspectRatio(aspectRatio: aspectRatio, child: image)
                : ColoredBox(color: AppColors.lighter, child: image),
            if (tagNames.isNotEmpty)
              Positioned(
                left: 7,
                right: 7,
                bottom: 5,
                child: IgnorePointer(
                  child: Text(
                    tagNames.join('  ·  '),
                    key: ValueKey('tile-tags-$path'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.foam,
                      // Readable over any image: a tight shadow for the edge
                      // and a wide, soft one for light backgrounds.
                      shadows: [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 2,
                          color: Color(0xE6000000),
                        ),
                        Shadow(blurRadius: 8, color: Color(0x99000000)),
                      ],
                    ),
                  ),
                ),
              ),
            if (starred)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.star,
                  size: 18,
                  color: AppColors.star,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            if (selected || candidates.isNotEmpty)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: candidates.isNotEmpty ? Colors.black45 : null,
                    border: Border.all(
                      color: AppColors.accent,
                      width: candidates.isNotEmpty ? 3 : 2,
                    ),
                  ),
                ),
              ),
            if (candidates.isNotEmpty)
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      tagDropCount > 1
                          ? 'Add to $tagDropCount images'
                          : 'Add tag',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    onContextSelect?.call();
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: [
        PopupMenuItem(
          value: 'copyImage',
          enabled: onCopyImage != null,
          child: const Text('Copy image to clipboard'),
        ),
        PopupMenuItem(
          value: 'tags',
          enabled: onEditTags != null,
          child: const _MenuLabel(Icons.label_outline, 'Edit tags…'),
        ),
        PopupMenuItem(
          value: 'star',
          enabled: onToggleStar != null,
          child: starWillSet
              ? const _MenuLabel(Icons.star_outline, 'Star')
              : const _MenuLabel(Icons.star, 'Unstar'),
        ),
        const PopupMenuItem(
          value: 'info',
          child: _MenuLabel(Icons.info_outline, 'Image info'),
        ),
        PopupMenuItem(
          value: 'similar',
          enabled: onSimilar != null,
          child: const Text('Find similar'),
        ),
        PopupMenuItem(
          value: 'resize',
          enabled: onResize != null,
          child: const _MenuLabel(Icons.photo_size_select_large, 'Resize…'),
        ),
        if (onRefine != null && (canRefine?.call() ?? false))
          const PopupMenuItem(value: 'refine', child: Text('AI refine tags…')),
        if (onAiSort != null)
          const PopupMenuItem(
            value: 'aiSort',
            child: _MenuLabel(Icons.auto_awesome_outlined, 'AI sort…'),
          ),
        PopupMenuItem(
          value: 'archive',
          enabled: onArchive != null,
          child: archived
              ? const _MenuLabel(
                  Icons.unarchive_outlined,
                  'Restore from archive',
                )
              : const _MenuLabel(Icons.archive_outlined, 'Archive'),
        ),
        PopupMenuItem(
          value: 'delete',
          enabled: onDelete != null,
          child: const _MenuLabel(Icons.delete_outline, 'Delete'),
        ),
      ],
    );
    if (choice == 'copyImage' && context.mounted) onCopyImage?.call();
    if (choice == 'tags' && context.mounted) onEditTags?.call();
    if (choice == 'star' && context.mounted) onToggleStar?.call();
    if (choice == 'archive' && context.mounted) onArchive?.call();
    if (choice == 'delete' && context.mounted) onDelete?.call();
    if (choice == 'refine' && context.mounted) onRefine?.call();
    if (choice == 'aiSort' && context.mounted) onAiSort?.call();
    if (choice == 'similar' && context.mounted) onSimilar?.call();
    if (choice == 'resize' && context.mounted) onResize?.call();
    if (choice == 'info' && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(filename),
          content: SelectableText(path),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
}

/// Title-bar space that drags the window and maximizes on double-click.
class _TitleDragArea extends StatelessWidget {
  const _TitleDragArea();

  @override
  Widget build(BuildContext context) =>
      // The app bar gives its title an unbounded height; match toolbarHeight.
      const DragToMoveArea(child: SizedBox(height: 48));
}

/// A keyboard shortcut hint, drawn like a key cap.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Align(
      widthFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x59FFF2F1)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11,
            color: Color(0xD9FFF2F1),
          ),
        ),
      ),
    ),
  );
}

/// A context menu entry with a leading icon.
class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
  );
}

class _MarqueePainter extends CustomPainter {
  _MarqueePainter(this.rect);
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MarqueePainter old) => old.rect != rect;
}

class _GalleryScrollBehavior extends ScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child; // suppress built-in scrollbar — we render our own
}
