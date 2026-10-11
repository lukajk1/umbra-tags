import 'dart:io';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../storage/library_store.dart';
import '../theme.dart';

enum TagMatchSource { semantic, classifier }

typedef ScoreTagImage =
    Future<double> Function(
      LibraryAsset asset,
      TagMatchSource source,
      String label,
    );

/// A whole semantic scan scored at once from stored vectors: similarity to
/// the images already in the tag plus the tag name (see `ml/tag_match.dart`).
class TagMatchBatch {
  const TagMatchBatch({
    required this.scores,
    required this.members,
    this.errors = const {},
    this.nameWeight,
    this.nameError,
    this.threshold,
  });

  /// Score per asset id.
  final Map<String, double> scores;
  final Map<String, String> errors;

  /// Images in the tag that served as examples; 0 means the name alone.
  final int members;

  /// The name's weight beside the examples (0: the name is ignored).
  final double? nameWeight;

  /// Why the tag name could not be used, if it could not.
  final String? nameError;

  /// Suggested minimum score: how well a typical image in the tag matches.
  final double? threshold;
}

/// Scores every image in one go. [progress] reports images being indexed
/// first; [stopped] asks to finish early. Returns null when the similarity
/// index is unavailable, and the dialog falls back to per-image scoring.
typedef ScanTagMatches =
    Future<TagMatchBatch?> Function(
      void Function(int done, int total) progress,
      bool Function() stopped,
    );

class TagMatchDialog extends StatefulWidget {
  const TagMatchDialog({
    super.key,
    required this.tagName,
    required this.assets,
    required this.classifierLabels,
    required this.score,
    required this.thumbnail,
    required this.onApply,
    this.scanSemantic,
    this.classifierError,
    this.classifierThreshold = 0.8,
    this.imagePath,
  });
  final String tagName;
  final List<LibraryAsset> assets;
  final List<String> classifierLabels;
  final String? classifierError;
  final double classifierThreshold;

  /// Scores one image; used for the classifier, and for the semantic source
  /// without [scanSemantic] or when it returns null (tag name only).
  final ScoreTagImage score;

  /// Scores the semantic source in one pass from stored vectors.
  final ScanTagMatches? scanSemantic;
  final Future<String?> Function(LibraryAsset) thumbnail;
  final Future<void> Function(List<LibraryAsset>) onApply;

  /// Absolute path of the original image, for the enlarged preview. Without
  /// it the preview shows the thumbnail.
  final String Function(LibraryAsset)? imagePath;

  @override
  State<TagMatchDialog> createState() => _TagMatchDialogState();
}

class _TagMatchDialogState extends State<TagMatchDialog> {
  TagMatchSource _source = TagMatchSource.semantic;
  String? _classLabel;
  double _semanticThreshold = 0.15;
  late double _classifierThreshold;
  final _scores = <String, double>{};
  final _selected = <String>{};
  final _errors = <String, String>{};
  final _thumbnails = <String, Future<String?>>{};
  bool _scanning = false, _saving = false, _stop = false;
  bool _showBelow = false;
  double _tileSize = 240;
  int _processed = 0;
  String? _error;

  /// What the last semantic scan matched by; null before a scan.
  String? _basis;

  /// Images being indexed before a batch scan can score them.
  int _indexing = 0, _indexed = 0;

  /// Whether the user moved the semantic threshold; until then each scan
  /// suggests one.
  bool _thresholdTouched = false;
  String? _lastTapId;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  double get _threshold => _source == TagMatchSource.classifier
      ? _classifierThreshold
      : _semanticThreshold;

  bool get _locked => _scanning || _saving;

  /// Typed threshold, kept in sync with the slider while not being edited.
  final _thresholdField = TextEditingController();
  final _thresholdFocus = FocusNode();

  @override
  void dispose() {
    _thresholdField.dispose();
    _thresholdFocus.dispose();
    super.dispose();
  }

  /// The slider spans the scores the scan found (match scores cluster in a
  /// narrow band), or the full range before a scan.
  (double, double) get _sliderRange {
    if (_source == TagMatchSource.classifier) return (0, 1);
    if (_scores.length < 2) return (-1, 1);
    var lo = _scores.values.reduce((a, b) => a < b ? a : b);
    var hi = _scores.values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 0.01) {
      lo -= 0.005;
      hi += 0.005;
    }
    return (lo, hi);
  }

  void _setThreshold(double value) => setState(() {
    if (_source == TagMatchSource.classifier) {
      _classifierThreshold = value.clamp(0, 1);
    } else {
      // Blended scores are in cosine units plus a name bonus, so they can
      // leave [-1, 1] a little.
      _semanticThreshold = value.clamp(-10, 10);
      _thresholdTouched = true;
    }
    _selectMatches();
  });

  /// Classifier thresholds are typed as percentages; match scores as-is.
  String _thresholdText(double value) => _source == TagMatchSource.classifier
      ? (value * 100).toStringAsFixed(1)
      : value.toStringAsFixed(4);

  void _submitThreshold(String text) {
    final typed = double.tryParse(text.trim());
    if (typed == null) {
      _thresholdField.text = _thresholdText(_threshold);
      return;
    }
    _setThreshold(_source == TagMatchSource.classifier ? typed / 100 : typed);
    _thresholdField.text = _thresholdText(_threshold);
  }

  @override
  void initState() {
    super.initState();
    _classifierThreshold = widget.classifierThreshold.clamp(0, 1);
    for (final label in widget.classifierLabels) {
      if (label.trim().toLowerCase() == widget.tagName.trim().toLowerCase()) {
        _classLabel = label;
        _source = TagMatchSource.classifier;
        break;
      }
    }
    _classLabel ??= widget.classifierLabels.firstOrNull;
    _thresholdField.text = _thresholdText(_threshold);
  }

  void _reset() {
    _scores.clear();
    _selected.clear();
    _errors.clear();
    _processed = 0;
    _indexing = _indexed = 0;
    _error = null;
    _basis = null;
  }

  static String _describe(TagMatchBatch batch) {
    final count = batch.members;
    if (count == 0) {
      return 'Matching by the tag name only: this tag has no indexed images yet.';
    }
    final images = '$count ${count == 1 ? 'image' : 'images'} in this tag';
    if (batch.nameError != null) {
      return 'Matching by $images (tag name not used: ${batch.nameError})';
    }
    if ((batch.nameWeight ?? 0) > 0) {
      return 'Matching by $images + the tag name';
    }
    return 'Matching by $images (the tag name does not describe them, so it is not used)';
  }

  /// Scores the semantic source in one pass; false to fall back to per-image
  /// scoring.
  Future<bool> _scanBatch(ScanTagMatches scan) async {
    final batch = await scan((done, total) {
      if (mounted) {
        setState(() {
          _indexed = done;
          _indexing = total;
        });
      }
    }, () => _stop || !mounted);
    if (batch == null || !mounted) return false;
    final ids = {for (final asset in widget.assets) asset.id};
    setState(() {
      _scores
        ..clear()
        ..addAll({
          for (final MapEntry(:key, :value) in batch.scores.entries)
            if (ids.contains(key) && value.isFinite) key: value,
        });
      _errors.addAll({
        for (final MapEntry(:key, :value) in batch.errors.entries)
          if (ids.contains(key) && !_scores.containsKey(key)) key: value,
      });
      _processed = widget.assets.length;
      _indexing = _indexed = 0;
      _basis = _describe(batch);
      if (batch.threshold case final threshold? when !_thresholdTouched) {
        _semanticThreshold = threshold;
      }
      _selectMatches();
    });
    _thresholdField.text = _thresholdText(_threshold);
    return true;
  }

  void _selectMatches() {
    _selected
      ..clear()
      ..addAll(
        _scores.entries.where((e) => e.value >= _threshold).map((e) => e.key),
      );
  }

  Future<void> _scan() async {
    setState(() {
      _reset();
      _scanning = true;
      _stop = false;
    });
    final label = _source == TagMatchSource.classifier
        ? _classLabel!
        : widget.tagName;
    try {
      final batch = widget.scanSemantic;
      if (_source == TagMatchSource.semantic && batch != null) {
        try {
          if (await _scanBatch(batch) || !mounted) return;
        } catch (error) {
          if (mounted) setState(() => _error = error.toString());
          return;
        }
        // Without the similarity index: the tag name alone, image by image.
        setState(
          () => _basis =
              'Matching by the tag name only: the similarity index is unavailable.',
        );
      }
      for (final asset in widget.assets) {
        if (!mounted || _stop) break;
        try {
          final value = await widget.score(asset, _source, label);
          if (!value.isFinite ||
              value < -1 ||
              value > 1 ||
              (_source == TagMatchSource.classifier && value < 0)) {
            throw StateError('The model returned an invalid score.');
          }
          if (!mounted) return;
          setState(() {
            _scores[asset.id] = value;
            if (value >= _threshold) _selected.add(asset.id);
          });
        } catch (error) {
          if (!mounted) return;
          setState(() => _errors[asset.id] = error.toString());
          // Avoid repeatedly calling a broken backend across a large library.
          if (_scores.isEmpty && _errors.length >= 3) {
            _stop = true;
            _error =
                'Scan stopped after three failures. Check the image errors and ML settings.';
          }
        }
        if (!mounted) return;
        setState(() => _processed++);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _apply() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onApply(
        widget.assets.where((a) => _selected.contains(a.id)).toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _saving = false;
        });
      }
    }
  }

  String _scoreLabel(double score) => _source == TagMatchSource.classifier
      ? '${(score * 100).toStringAsFixed(1)}%'
      : 'Match score ${score.toStringAsFixed(3)}';

  String _shortScore(double score) => _source == TagMatchSource.classifier
      ? '${(score * 100).toStringAsFixed(1)}%'
      : score.toStringAsFixed(3);

  Future<String?> _thumb(LibraryAsset asset) =>
      _thumbnails.putIfAbsent(asset.id, () => widget.thumbnail(asset));

  /// Scored images shown in the gallery, best first: those at or above the
  /// threshold, anything selected, and with [_showBelow] everything scored.
  List<LibraryAsset> _visible() => widget.assets.where((a) {
    final score = _scores[a.id];
    if (score == null) return false;
    return _showBelow || score >= _threshold || _selected.contains(a.id);
  }).toList()..sort((a, b) => _scores[b.id]!.compareTo(_scores[a.id]!));

  void _toggle(LibraryAsset asset) {
    if (_locked || !_scores.containsKey(asset.id)) return;
    setState(() {
      if (!_selected.remove(asset.id)) _selected.add(asset.id);
    });
  }

  /// A click toggles at once; a second click on the same tile within the
  /// double-click window toggles back and opens the preview, so a double
  /// click leaves the selection as it was.
  void _tapTile(List<LibraryAsset> items, int index) {
    final asset = items[index];
    final now = DateTime.now();
    final isDouble =
        _lastTapId == asset.id &&
        now.difference(_lastTapAt) < kDoubleTapTimeout;
    _toggle(asset);
    if (isDouble) {
      _lastTapId = null;
      _preview(items, index);
    } else {
      _lastTapId = asset.id;
      _lastTapAt = now;
    }
  }

  void _preview(List<LibraryAsset> items, int index) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xE6070A33),
      builder: (_) => _MatchPreview(
        items: items,
        initial: index,
        thumbnail: _thumb,
        imagePath: widget.imagePath,
        caption: (a) {
          final score = _scores[a.id];
          return score == null ? '' : _scoreLabel(score);
        },
        isSelected: (a) => _selected.contains(a.id),
        onToggle: _locked ? null : _toggle,
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final locked = _locked;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 380,
          child: DropdownButtonFormField<TagMatchSource>(
            initialValue: _source,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Match using'),
            items: [
              const DropdownMenuItem(
                value: TagMatchSource.semantic,
                child: Text(
                  'Tag suggestion model — text / image similarity',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.classifierLabels.isNotEmpty)
                const DropdownMenuItem(
                  value: TagMatchSource.classifier,
                  child: Text('Trained classifier'),
                ),
            ],
            onChanged: locked
                ? null
                : (value) {
                    setState(() {
                      _source = value!;
                      _reset();
                    });
                    _thresholdField.text = _thresholdText(_threshold);
                  },
          ),
        ),
        if (_source == TagMatchSource.classifier)
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: _classLabel,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Classifier label to match',
              ),
              items: widget.classifierLabels
                  .map(
                    (label) => DropdownMenuItem(
                      value: label,
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: locked
                  ? null
                  : (value) => setState(() {
                      _classLabel = value;
                      _reset();
                    }),
            ),
          ),
        SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text('Minimum ${_scoreLabel(_threshold)}'),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const ValueKey('match-threshold-slider'),
                      value: _threshold.clamp(_sliderRange.$1, _sliderRange.$2),
                      min: _sliderRange.$1,
                      max: _sliderRange.$2,
                      label: _scoreLabel(_threshold),
                      onChanged: locked
                          ? null
                          : (value) {
                              _setThreshold(value);
                              _thresholdField.text = _thresholdText(_threshold);
                            },
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: TextField(
                      key: const ValueKey('match-threshold-field'),
                      controller: _thresholdField,
                      focusNode: _thresholdFocus,
                      enabled: !locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        suffixText: _source == TagMatchSource.classifier
                            ? '%'
                            : null,
                      ),
                      onSubmitted: _submitThreshold,
                      onTapOutside: (_) {
                        if (_thresholdFocus.hasFocus) {
                          _submitThreshold(_thresholdField.text);
                          _thresholdFocus.unfocus();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: locked || widget.assets.isEmpty ? null : _scan,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(_processed == 0 ? 'Scan library' : 'Scan again'),
        ),
        if (_scanning)
          TextButton(
            onPressed: _stop ? null : () => setState(() => _stop = true),
            child: Text(_stop ? 'Stopping…' : 'Stop'),
          ),
        Text(
          _indexing > 0
              ? 'Indexing new images: $_indexed / $_indexing'
              : '$_processed / ${widget.assets.length} scanned · ${_errors.length} failed',
          style: const TextStyle(color: AppColors.mist),
        ),
      ],
    );
  }

  /// What the semantic source matches by, so the score is explainable.
  String? get _basisText {
    if (_source != TagMatchSource.semantic) return null;
    if (_basis != null) return _basis;
    return widget.scanSemantic == null
        ? 'Matching by the tag name.'
        : 'Matches images similar to the ones already in this tag, plus the tag name.';
  }

  Widget _resultsHeader(List<LibraryAsset> visible) {
    final locked = _locked;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_selected.length} selected of ${visible.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: locked || visible.isEmpty
                    ? null
                    : () => setState(
                        () => _selected.addAll(visible.map((a) => a.id)),
                      ),
                child: const Text('Select all'),
              ),
              TextButton(
                onPressed: locked || _selected.isEmpty
                    ? null
                    : () => setState(_selected.clear),
                child: const Text('Select none'),
              ),
              FilterChip(
                label: const Text('Show below threshold'),
                selected: _showBelow,
                showCheckmark: false,
                selectedColor: AppColors.raised,
                side: BorderSide(
                  color: _showBelow ? AppColors.foam : AppColors.rule,
                ),
                onSelected: (value) => setState(() => _showBelow = value),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.photo_size_select_small,
          size: 18,
          color: AppColors.mist,
        ),
        SizedBox(
          width: 160,
          child: Slider(
            value: _tileSize,
            min: 140,
            max: 480,
            onChanged: (value) => setState(() => _tileSize = value),
          ),
        ),
        const Icon(
          Icons.photo_size_select_large,
          size: 18,
          color: AppColors.mist,
        ),
      ],
    );
  }

  Widget _gallery(List<LibraryAsset> visible) {
    final failed = widget.assets
        .where((a) => _errors.containsKey(a.id))
        .toList();
    final items = [...visible, ...failed];
    if (items.isEmpty) {
      return Center(
        child: Text(
          _scores.isEmpty
              ? 'Scan to preview matches, then add the selected images.'
              : _scanning
              ? 'Looking for matches…'
              : 'No images at or above the threshold. Lower it or show images below the threshold.',
          style: const TextStyle(color: AppColors.mist),
        ),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return GridView.builder(
      padding: const EdgeInsets.only(right: 12, bottom: 12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _tileSize,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final asset = items[index];
        final score = _scores[asset.id];
        return _MatchTile(
          key: ValueKey('tag-match-tile-${asset.id}'),
          asset: asset,
          thumbnail: _thumb(asset),
          cacheWidth: (_tileSize * dpr).round(),
          selected: _selected.contains(asset.id),
          dimmed: score != null && score < _threshold,
          caption: score == null ? null : _shortScore(score),
          error: _errors[asset.id],
          onTap: score == null || _locked
              ? null
              : () => _tapTile(visible, index),
          onChanged: score == null || _locked ? null : () => _toggle(asset),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    final size = MediaQuery.sizeOf(context);
    final visible = _visible();
    return PopScope(
      canPop: !locked,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: size.width * 0.9,
          height: size.height * 0.9,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Find images for “${widget.tagName}”',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: locked ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '${widget.assets.length} available images without this tag. Archived images are excluded. Click an image to select it; double-click to view it larger.',
                  style: const TextStyle(color: AppColors.mist),
                ),
                const SizedBox(height: 12),
                _controls(context),
                if (_basisText case final basis?)
                  Text(
                    basis,
                    key: const ValueKey('tag-match-basis'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.mist),
                  ),
                if (widget.classifierError != null)
                  Text(
                    'Classifier unavailable: ${widget.classifierError}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                if (_scanning)
                  LinearProgressIndicator(
                    value: _indexing > 0
                        ? _indexed / _indexing
                        : widget.scanSemantic != null &&
                              _source == TagMatchSource.semantic &&
                              _processed == 0
                        ? null
                        : widget.assets.isEmpty
                        ? 0
                        : _processed / widget.assets.length,
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const Divider(height: 16),
                _resultsHeader(visible),
                const SizedBox(height: 8),
                Expanded(
                  child: ColoredBox(
                    color: AppColors.well,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
                      child: _gallery(visible),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: locked ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: locked || _selected.isEmpty ? null : _apply,
                      child: Text(
                        _saving
                            ? 'Adding…'
                            : 'Add ${_selected.length} images to tag',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    super.key,
    required this.asset,
    required this.thumbnail,
    required this.cacheWidth,
    required this.selected,
    required this.dimmed,
    required this.caption,
    required this.error,
    required this.onTap,
    required this.onChanged,
  });
  final LibraryAsset asset;
  final Future<String?> thumbnail;
  final int cacheWidth;
  final bool selected, dimmed;
  final String? caption, error;
  final VoidCallback? onTap, onChanged;

  @override
  Widget build(BuildContext context) {
    final image = FutureBuilder<String?>(
      future: thumbnail,
      builder: (_, snapshot) => snapshot.data == null
          ? Center(
              child: Icon(
                error == null
                    ? Icons.image_outlined
                    : Icons.broken_image_outlined,
                color: AppColors.haze,
                size: 32,
              ),
            )
          : Image.file(
              File(snapshot.data!),
              fit: BoxFit.contain,
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.haze,
                  size: 32,
                ),
              ),
            ),
    );
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.foam : AppColors.rule,
              width: selected ? 3 : 1,
            ),
          ),
          color: const Color(0xFF04061F),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: Opacity(opacity: dimmed ? 0.4 : 1, child: image),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: selected ? AppColors.raised : AppColors.panel,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          error ?? asset.originalFilename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: error == null
                                ? AppColors.foam
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      if (caption != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          caption!,
                          style: TextStyle(
                            fontSize: 12,
                            color: dimmed ? AppColors.haze : AppColors.mist,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (error == null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    color: const Color(0xB3070A33),
                    child: Checkbox(
                      key: ValueKey('tag-match-check-${asset.id}'),
                      value: selected,
                      shape: const RoundedRectangleBorder(),
                      onChanged: onChanged == null ? null : (_) => onChanged!(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The enlarged view: the original image fit to the screen. ← / → step
/// through the results, Space toggles the current image, Esc closes.
class _MatchPreview extends StatefulWidget {
  const _MatchPreview({
    required this.items,
    required this.initial,
    required this.thumbnail,
    required this.imagePath,
    required this.caption,
    required this.isSelected,
    required this.onToggle,
  });
  final List<LibraryAsset> items;
  final int initial;
  final Future<String?> Function(LibraryAsset) thumbnail;
  final String Function(LibraryAsset)? imagePath;
  final String Function(LibraryAsset) caption;
  final bool Function(LibraryAsset) isSelected;
  final void Function(LibraryAsset)? onToggle;

  @override
  State<_MatchPreview> createState() => _MatchPreviewState();
}

class _MatchPreviewState extends State<_MatchPreview> {
  late int _index = widget.initial;

  LibraryAsset get _asset => widget.items[_index];

  void _step(int delta) {
    final next = (_index + delta).clamp(0, widget.items.length - 1);
    if (next != _index) setState(() => _index = next);
  }

  void _toggle() {
    final toggle = widget.onToggle;
    if (toggle == null) return;
    toggle(_asset);
    setState(() {});
  }

  Widget _thumbnail() => FutureBuilder<String?>(
    future: widget.thumbnail(_asset),
    builder: (_, snapshot) => snapshot.data == null
        ? const Center(
            child: Icon(Icons.image_outlined, color: AppColors.haze, size: 48),
          )
        : Image.file(
            File(snapshot.data!),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.haze,
                size: 48,
              ),
            ),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (size.width * dpr).round();
    final path = widget.imagePath?.call(_asset);
    final asset = _asset;
    final selected = widget.isSelected(asset);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.space): _toggle,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          key: const ValueKey('tag-match-preview'),
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: AppColors.well,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Column(
              children: [
                Container(
                  color: AppColors.panel,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: selected,
                        shape: const RoundedRectangleBorder(),
                        onChanged: widget.onToggle == null
                            ? null
                            : (_) => _toggle(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${asset.originalFilename} · ${widget.caption(asset)} · ${_index + 1} of ${widget.items.length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous (←)',
                        onPressed: _index == 0 ? null : () => _step(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next (→)',
                        onPressed: _index == widget.items.length - 1
                            ? null
                            : () => _step(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                      IconButton(
                        tooltip: 'Close (Esc)',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: path == null
                        ? _thumbnail()
                        : Image.file(
                            File(path),
                            key: ValueKey(path),
                            fit: BoxFit.contain,
                            cacheWidth: cacheWidth,
                            // Formats the engine cannot decode fall back to
                            // the thumbnail.
                            errorBuilder: (_, _, _) => _thumbnail(),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
