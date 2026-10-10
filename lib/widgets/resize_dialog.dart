import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/library_store.dart';

enum ResizeAction { resize, skip, stop }

/// What the resize wizard decided. [width] and [height] are set for
/// [ResizeAction.resize].
class ResizeChoice {
  const ResizeChoice.resize(int this.width, int this.height)
    : action = ResizeAction.resize;
  const ResizeChoice.skip()
    : action = ResizeAction.skip,
      width = null,
      height = null;
  const ResizeChoice.stop()
    : action = ResizeAction.stop,
      width = null,
      height = null;

  final ResizeAction action;
  final int? width, height;
}

/// Scales [width]×[height] by [factor], keeping at least one pixel per side.
(int, int) scaledSize(int width, int height, double factor) => (
  math.max(1, (width * factor).round()),
  math.max(1, (height * factor).round()),
);

/// Scales so the longer side becomes [longEdge] pixels.
(int, int) fitLongEdge(int width, int height, int longEdge) =>
    scaledSize(width, height, longEdge / math.max(width, height));

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

const _breakpoints = <(String, double)>[
  ('75%', 0.75),
  ('50%', 0.5),
  ('33%', 1 / 3),
  ('25%', 0.25),
  ('10%', 0.1),
];

/// Shows an image's current size and offers smaller sizes at percentage
/// breakpoints of the original, or a custom long edge.
///
/// In a batch ([position] and [total] set) the dialog also offers Skip and
/// Stop, and [suggestedLongEdge] preselects the largest breakpoint that fits.
class ResizeDialog extends StatefulWidget {
  const ResizeDialog({
    super.key,
    required this.asset,
    this.thumbnailPath,
    this.position,
    this.total,
    this.suggestedLongEdge,
  });

  final LibraryAsset asset;
  final String? thumbnailPath;
  final int? position, total;
  final int? suggestedLongEdge;

  bool get batch => total != null;

  @override
  State<ResizeDialog> createState() => _ResizeDialogState();
}

class _ResizeDialogState extends State<ResizeDialog> {
  static const _custom = -1;
  late int _choice; // Index into [_breakpoints], or [_custom].
  late final TextEditingController _customEdge;

  int get _width => widget.asset.width;
  int get _height => widget.asset.height;
  int get _longEdge => math.max(_width, _height);

  @override
  void initState() {
    super.initState();
    final suggested = widget.suggestedLongEdge;
    _choice = 1; // 50%
    if (suggested != null) {
      final fitting = _breakpoints.indexWhere(
        (b) => _longEdge * b.$2 <= suggested,
      );
      _choice = fitting == -1 ? _custom : fitting;
    }
    _customEdge = TextEditingController(
      text: '${math.min(suggested ?? (_longEdge ~/ 2), _longEdge - 1)}',
    );
  }

  @override
  void dispose() {
    _customEdge.dispose();
    super.dispose();
  }

  /// The selected target size, or null when the custom value is invalid.
  (int, int)? get _target {
    if (_choice != _custom) {
      return scaledSize(_width, _height, _breakpoints[_choice].$2);
    }
    final edge = int.tryParse(_customEdge.text.trim());
    if (edge == null || edge < 1 || edge >= _longEdge) return null;
    return fitLongEdge(_width, _height, edge);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7);
    final target = _target;
    final resize = target == null
        ? null
        : () =>
              Navigator.pop(context, ResizeChoice.resize(target.$1, target.$2));
    return AlertDialog(
      title: Text(
        widget.batch
            ? 'Resize large images · ${widget.position} of ${widget.total}'
            : 'Resize image',
      ),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.thumbnailPath != null)
              Container(
                height: 160,
                color: Colors.black26,
                child: Image.file(
                  File(widget.thumbnailPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              widget.asset.originalFilename,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Current size: $_width × $_height px'
              '${widget.asset.byteSize > 0 ? ' · ${formatBytes(widget.asset.byteSize)}' : ''}',
            ),
            const SizedBox(height: 12),
            Text('Resize to', style: theme.textTheme.labelLarge),
            RadioGroup<int>(
              groupValue: _choice,
              onChanged: (value) => setState(() => _choice = value ?? _choice),
              child: Column(
                children: [
                  for (var i = 0; i < _breakpoints.length; i++)
                    _option(i, _breakpoints[i].$1, () {
                      final (w, h) = scaledSize(
                        _width,
                        _height,
                        _breakpoints[i].$2,
                      );
                      return '$w × $h px';
                    }(), muted),
                  _customOption(muted),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The library copy is replaced. The current file goes to the Recycle Bin; '
              'tags and stars stay.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.batch) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, const ResizeChoice.stop()),
            child: const Text('Stop'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, const ResizeChoice.skip()),
            child: const Text('Skip'),
          ),
        ] else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        FilledButton(
          autofocus: true,
          onPressed: resize,
          child: Text(
            target == null ? 'Resize' : 'Resize to ${target.$1} × ${target.$2}',
          ),
        ),
      ],
    );
  }

  Widget _option(int value, String label, String size, Color? muted) =>
      RadioListTile<int>(
        value: value,
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Row(
          children: [
            SizedBox(width: 48, child: Text(label)),
            Text('→  $size', style: TextStyle(color: muted)),
          ],
        ),
      );

  Widget _customOption(Color? muted) {
    final target = _choice == _custom ? _target : null;
    return RadioListTile<int>(
      value: _custom,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          const Text('Long edge'),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _customEdge,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'px',
              ),
              onTap: () => setState(() => _choice = _custom),
              onChanged: (_) => setState(() => _choice = _custom),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              _choice != _custom
                  ? ''
                  : target == null
                  ? 'Must be under $_longEdge'
                  : '→  ${target.$1} × ${target.$2} px',
              style: TextStyle(
                color: target == null ? Colors.redAccent : muted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

enum LargeImageMeasure { longEdge, fileSize }

/// The threshold chosen in [LargeImagesDialog].
class LargeImageThreshold {
  const LargeImageThreshold(this.measure, this.value);
  final LargeImageMeasure measure;

  /// Pixels for [LargeImageMeasure.longEdge], megabytes for [LargeImageMeasure.fileSize].
  final double value;

  bool matches(LibraryAsset asset) => switch (measure) {
    LargeImageMeasure.longEdge => math.max(asset.width, asset.height) > value,
    LargeImageMeasure.fileSize => asset.byteSize > value * 1024 * 1024,
  };

  /// Long edge to suggest in the wizard, when the threshold is in pixels.
  int? get suggestedLongEdge =>
      measure == LargeImageMeasure.longEdge ? value.floor() : null;
}

/// Asks which images count as large and shows how many match. Pops with the
/// threshold, or null when cancelled.
class LargeImagesDialog extends StatefulWidget {
  const LargeImagesDialog({super.key, required this.assets});

  final List<LibraryAsset> assets;

  @override
  State<LargeImagesDialog> createState() => _LargeImagesDialogState();
}

class _LargeImagesDialogState extends State<LargeImagesDialog> {
  var _measure = LargeImageMeasure.longEdge;
  final _pixels = TextEditingController(text: '4000');
  final _megabytes = TextEditingController(text: '10');

  @override
  void dispose() {
    _pixels.dispose();
    _megabytes.dispose();
    super.dispose();
  }

  LargeImageThreshold? get _threshold {
    final field = _measure == LargeImageMeasure.longEdge ? _pixels : _megabytes;
    final value = double.tryParse(field.text.trim());
    return value == null || value <= 0
        ? null
        : LargeImageThreshold(_measure, value);
  }

  @override
  Widget build(BuildContext context) {
    final threshold = _threshold;
    final count = threshold == null
        ? 0
        : widget.assets.where(threshold.matches).length;
    return AlertDialog(
      title: const Text('Resize large images'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Go through every image above a size, largest first. For each one you '
              'see its dimensions and choose a new size or skip it.',
            ),
            const SizedBox(height: 12),
            RadioGroup<LargeImageMeasure>(
              groupValue: _measure,
              onChanged: (value) =>
                  setState(() => _measure = value ?? _measure),
              child: Column(
                children: [
                  _row(
                    LargeImageMeasure.longEdge,
                    'Long edge over',
                    _pixels,
                    'px',
                  ),
                  _row(
                    LargeImageMeasure.fileSize,
                    'File size over',
                    _megabytes,
                    'MB',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              threshold == null
                  ? 'Enter a number above zero.'
                  : '$count ${count == 1 ? 'image matches' : 'images match'} '
                        '(archived images are not included).',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: threshold == null || count == 0
              ? null
              : () => Navigator.pop(context, threshold),
          child: Text(count == 0 ? 'Start' : 'Start ($count)'),
        ),
      ],
    );
  }

  Widget _row(
    LargeImageMeasure measure,
    String label,
    TextEditingController controller,
    String unit,
  ) => RadioListTile<LargeImageMeasure>(
    value: measure,
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        SizedBox(
          width: 90,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(isDense: true, suffixText: unit),
            onTap: () => setState(() => _measure = measure),
            onChanged: (_) => setState(() => _measure = measure),
          ),
        ),
      ],
    ),
  );
}
