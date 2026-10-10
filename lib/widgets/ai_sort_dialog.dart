import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/library_store.dart';
import '../storage/tag_repository.dart';
import 'tag_widgets.dart' show referenceTagColor;

/// One ranked candidate tag for an image (see `ml/tag_sort.dart`).
class AiSortSuggestion {
  const AiSortSuggestion({
    required this.tag,
    required this.confidence,
    this.name = 0,
    this.votes = 0,
    this.neighbours = 0,
    this.members = 0,
  });

  AiSortSuggestion.fromMap(Map row, this.tag)
    : confidence = (row['confidence'] as num).toDouble(),
      name = (row['name'] as num?)?.toDouble() ?? 0,
      votes = row['votes'] as int? ?? 0,
      neighbours = row['neighbours'] as int? ?? 0,
      members = row['members'] as int? ?? 0;

  final LibraryTag tag;

  /// Combined confidence in [0, 1]; all candidates sum to 1.
  final double confidence;

  /// The tag name's share of the text-image match, in [0, 1].
  final double name;

  /// How many of the [neighbours] most similar sorted images are in [tag].
  final int votes, neighbours;

  /// Images already in [tag] (or beneath it).
  final int members;

  /// Why the tag was suggested, e.g. "7 of 10 most similar sorted images ·
  /// name match".
  String get reason {
    final parts = <String>[
      if (votes > 0)
        '$votes of $neighbours most similar sorted images'
      else if (members > 0)
        'looks like its $members ${members == 1 ? 'image' : 'images'}',
      if (members == 0)
        'no images yet: name match only'
      else if (name >= 0.5)
        'name match',
    ];
    return parts.isEmpty ? 'weak match' : parts.join(' · ');
  }
}

/// How an AI sort session ended.
class AiSortResult {
  const AiSortResult({
    required this.accepted,
    required this.skipped,
    required this.total,
  });
  final int accepted, skipped, total;
  int get remaining => total - accepted - skipped;
}

/// Tags directly beneath [parentId] (top-level tags for null), by name.
List<LibraryTag> childTags(String? parentId, List<LibraryTag> tags) =>
    tags.where((tag) => tag.parentId == parentId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Images that can be narrowed from [parent] into its children: tagged with
/// [parent] itself and with none of the tags beneath it.
List<LibraryAsset> narrowQueue(
  LibraryTag parent,
  List<LibraryTag> tags,
  List<LibraryAsset> assets,
) {
  final beneath = <String>{};
  void collect(String id) {
    for (final tag in tags) {
      if (tag.parentId == id && beneath.add(tag.id)) collect(tag.id);
    }
  }

  collect(parent.id);
  return [
    for (final asset in assets)
      if (asset.tagIds.contains(parent.id) &&
          !asset.tagIds.any(beneath.contains))
        asset,
  ];
}

/// What to sort: untagged images into top-level tags ([parent] null), or
/// [parent]'s images into its children.
class AiSortPlan {
  const AiSortPlan([this.parent]);
  final LibraryTag? parent;
}

/// Chooses the AI sort mode. Pops with an [AiSortPlan], or null.
class AiSortSetupDialog extends StatefulWidget {
  const AiSortSetupDialog({
    super.key,
    required this.tags,
    required this.untagged,
    required this.narrowable,
    this.initialParent,
  });

  final List<LibraryTag> tags;

  /// Untagged images available to sort.
  final int untagged;

  /// For each tag with children, how many of its images carry none of them.
  final Map<String, int> narrowable;
  final String? initialParent;

  @override
  State<AiSortSetupDialog> createState() => _AiSortSetupDialogState();
}

class _AiSortSetupDialogState extends State<AiSortSetupDialog> {
  late bool _narrow;
  String? _parent;

  List<LibraryTag> get _parents =>
      widget.tags.where((t) => widget.narrowable.containsKey(t.id)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  void initState() {
    super.initState();
    final parents = _parents;
    _parent = widget.initialParent ?? parents.firstOrNull?.id;
    _narrow = widget.initialParent != null;
  }

  @override
  Widget build(BuildContext context) {
    final topLevel = childTags(null, widget.tags).length;
    final parents = _parents;
    final count = _narrow
        ? widget.narrowable[_parent] ?? 0
        : (topLevel == 0 ? 0 : widget.untagged);
    final muted = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('AI sort'),
      content: SizedBox(
        width: 460,
        child: RadioGroup<bool>(
          groupValue: _narrow,
          onChanged: (value) => setState(() => _narrow = value ?? _narrow),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Suggests tags you already have, one image at a time. '
                'Suggestions learn from the images already in each tag and '
                'from the tag names.',
              ),
              const SizedBox(height: 12),
              RadioListTile<bool>(
                value: false,
                contentPadding: EdgeInsets.zero,
                title: const Text('Sort untagged images into top-level tags'),
                subtitle: Text(
                  '${widget.untagged} untagged · $topLevel top-level tags',
                  style: muted,
                ),
              ),
              RadioListTile<bool>(
                value: true,
                contentPadding: EdgeInsets.zero,
                enabled: parents.isNotEmpty,
                title: const Text('Narrow a tag into its child tags'),
                subtitle: parents.isEmpty
                    ? Text('No tag has child tags yet', style: muted)
                    : Text(
                        'Images tagged with the parent but none of its children',
                        style: muted,
                      ),
              ),
              if (parents.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: DropdownButton<String>(
                    key: const ValueKey('ai-sort-parent'),
                    value: _parent,
                    isExpanded: true,
                    onChanged: (id) => setState(() {
                      _parent = id;
                      _narrow = true;
                    }),
                    items: [
                      for (final tag in parents)
                        DropdownMenuItem(
                          value: tag.id,
                          child: Text(
                            '${tag.name} (${widget.narrowable[tag.id]} to narrow)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: count == 0
              ? null
              : () => Navigator.pop(
                  context,
                  AiSortPlan(
                    _narrow
                        ? widget.tags.firstWhere((t) => t.id == _parent)
                        : null,
                  ),
                ),
          child: Text(count == 0 ? 'Start' : 'Start ($count)'),
        ),
      ],
    );
  }
}

/// Reviews AI tag suggestions one image at a time: 1/2/3 accept a
/// suggestion, O picks any candidate, S skips, Backspace undoes the last
/// step, Esc stops. Accepted tags are applied immediately through [apply];
/// a summary is shown at the end. Pops with an [AiSortResult].
class AiSortDialog extends StatefulWidget {
  const AiSortDialog({
    super.key,
    required this.title,
    required this.queue,
    required this.candidates,
    required this.score,
    required this.apply,
    required this.undo,
    this.thumbnail,
    this.notice,
  });

  final String title;
  final List<LibraryAsset> queue;
  final List<LibraryTag> candidates;

  /// Ranked suggestions for an image, best first.
  final Future<List<AiSortSuggestion>> Function(LibraryAsset) score;
  final Future<void> Function(LibraryAsset, LibraryTag) apply, undo;
  final Future<String?> Function(LibraryAsset)? thumbnail;

  /// Shown under the title, e.g. when tag names cannot be used.
  final String? notice;

  @override
  State<AiSortDialog> createState() => _AiSortDialogState();
}

class _AiSortDialogState extends State<AiSortDialog> {
  int _index = 0;
  bool _finished = false, _working = false;
  String? _applyError;
  Future<List<AiSortSuggestion>>? _suggestions;
  List<AiSortSuggestion>? _loaded;
  Future<String?>? _thumbnail;

  /// Each step taken, so Backspace can undo it: the tag applied, or null for
  /// a skip.
  final _history = <({int index, LibraryTag? tag})>[];

  int get _accepted => _history.where((step) => step.tag != null).length;
  int get _skipped => _history.length - _accepted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (_index >= widget.queue.length) {
      _finished = true;
      return;
    }
    final asset = widget.queue[_index];
    _loaded = null;
    _applyError = null;
    final future = widget.score(asset);
    _suggestions = future;
    future.then((value) {
      if (mounted && identical(future, _suggestions)) {
        setState(() => _loaded = value);
      }
    }, onError: (Object _) {});
    _thumbnail = widget.thumbnail?.call(asset);
  }

  void _advance() {
    setState(() {
      _index++;
      _load();
    });
  }

  Future<void> _accept(LibraryTag tag) async {
    if (_working || _finished) return;
    final asset = widget.queue[_index];
    setState(() => _working = true);
    try {
      await widget.apply(asset, tag);
      _history.add((index: _index, tag: tag));
      if (mounted) _advance();
    } catch (error) {
      if (mounted) setState(() => _applyError = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _acceptRank(int rank) {
    final loaded = _loaded;
    if (loaded != null && rank < loaded.length) _accept(loaded[rank].tag);
  }

  void _skip() {
    if (_working || _finished) return;
    _history.add((index: _index, tag: null));
    _advance();
  }

  Future<void> _undo() async {
    if (_working || _history.isEmpty) return;
    final step = _history.last;
    setState(() => _working = true);
    try {
      if (step.tag != null) {
        await widget.undo(widget.queue[step.index], step.tag!);
      }
      _history.removeLast();
      if (mounted) {
        setState(() {
          _finished = false;
          _index = step.index;
          _load();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _applyError = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _stop() {
    if (_working) return;
    setState(() => _finished = true);
  }

  void _close() => Navigator.pop(
    context,
    AiSortResult(
      accepted: _accepted,
      skipped: _skipped,
      total: widget.queue.length,
    ),
  );

  Future<void> _other() async {
    if (_working || _finished) return;
    final scores = {
      for (final s in _loaded ?? const <AiSortSuggestion>[]) s.tag.id: s,
    };
    final ordered = [...widget.candidates]
      ..sort((a, b) {
        final by = (scores[b.id]?.confidence ?? 0).compareTo(
          scores[a.id]?.confidence ?? 0,
        );
        return by != 0
            ? by
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final tag = await showDialog<LibraryTag>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a tag'),
        children: [
          for (final tag in ordered)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, tag),
              child: Row(
                children: [
                  Expanded(child: _TagLabel(tag: tag)),
                  if (scores[tag.id] case final s?)
                    Text(
                      '${(s.confidence * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (tag != null && mounted) await _accept(tag);
  }

  @override
  Widget build(BuildContext context) {
    final digit = <ShortcutActivator, VoidCallback>{
      for (final (rank, keys) in [
        (0, [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1]),
        (1, [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2]),
        (2, [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3]),
      ])
        for (final key in keys) SingleActivator(key): () => _acceptRank(rank),
    };
    return CallbackShortcuts(
      bindings: _finished
          ? {
              const SingleActivator(LogicalKeyboardKey.escape): _close,
              const SingleActivator(LogicalKeyboardKey.enter): _close,
              const SingleActivator(LogicalKeyboardKey.backspace): _undo,
            }
          : {
              ...digit,
              const SingleActivator(LogicalKeyboardKey.keyS): _skip,
              const SingleActivator(LogicalKeyboardKey.keyO): _other,
              const SingleActivator(LogicalKeyboardKey.backspace): _undo,
              const SingleActivator(LogicalKeyboardKey.escape): _stop,
            },
      child: Focus(
        autofocus: true,
        child: _finished ? _summary(context) : _review(context),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final remaining = widget.queue.length - _history.length;
    return AlertDialog(
      title: Text('${widget.title} · done'),
      content: SizedBox(
        width: 420,
        child: Text(
          'Tagged $_accepted, skipped $_skipped'
          '${remaining > 0 ? ', $remaining not reviewed' : ''}.',
        ),
      ),
      actions: [
        if (_history.isNotEmpty)
          TextButton(
            onPressed: _working ? null : _undo,
            child: const Text('Undo last'),
          ),
        FilledButton(
          autofocus: true,
          onPressed: _close,
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _review(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final asset = widget.queue[_index];
    return AlertDialog(
      title: Text(
        '${widget.title} · ${_index + 1} of ${widget.queue.length}',
        overflow: TextOverflow.ellipsis,
      ),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.notice != null) ...[
              Text(widget.notice!, style: muted),
              const SizedBox(height: 8),
            ],
            Container(
              height: (MediaQuery.sizeOf(context).height * 0.35).clamp(
                140.0,
                360.0,
              ),
              color: Colors.black26,
              child: FutureBuilder<String?>(
                future: _thumbnail,
                builder: (context, snapshot) => snapshot.data == null
                    ? const SizedBox.shrink()
                    : Image.file(
                        File(snapshot.data!),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              asset.originalFilename,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<AiSortSuggestion>>(
              future: _suggestions,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'No suggestions for this image: ${snapshot.error}\n'
                    'Press S to skip it.',
                    style: const TextStyle(color: Colors.redAccent),
                  );
                }
                final suggestions = snapshot.data;
                if (suggestions == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < suggestions.length && i < 3; i++)
                      _SuggestionRow(
                        rank: i + 1,
                        suggestion: suggestions[i],
                        onTap: _working
                            ? null
                            : () => _accept(suggestions[i].tag),
                      ),
                  ],
                );
              },
            ),
            if (_applyError != null) ...[
              const SizedBox(height: 8),
              Text(
                _applyError!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '1 / 2 / 3 accept · O other tag · S skip · '
              'Backspace undo · Esc stop',
              style: muted,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working || _history.isEmpty ? null : _undo,
          child: const Text('Undo'),
        ),
        TextButton(
          onPressed: _working ? null : _stop,
          child: const Text('Stop'),
        ),
        TextButton(
          onPressed: _working ? null : _other,
          child: const Text('Other…'),
        ),
        FilledButton.tonal(
          onPressed: _working ? null : _skip,
          child: const Text('Skip'),
        ),
      ],
    );
  }
}

class _TagLabel extends StatelessWidget {
  const _TagLabel({required this.tag});
  final LibraryTag tag;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (tag.isReference) ...[
        const Icon(
          Icons.collections_bookmark_outlined,
          size: 16,
          color: referenceTagColor,
        ),
        const SizedBox(width: 4),
      ],
      Flexible(child: Text(tag.name, overflow: TextOverflow.ellipsis)),
      if (tag.isReference)
        Text(
          '  reference tag',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: referenceTagColor),
        ),
    ],
  );
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.rank,
    required this.suggestion,
    required this.onTap,
  });
  final int rank;
  final AiSortSuggestion suggestion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return InkWell(
      key: ValueKey('ai-sort-suggestion-$rank'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white38),
              ),
              child: Text('$rank'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _TagLabel(tag: suggestion.tag)),
                      Text('${(suggestion.confidence * 100).round()}%'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: suggestion.confidence.clamp(0.0, 1.0),
                    minHeight: 4,
                  ),
                  const SizedBox(height: 2),
                  Text(suggestion.reason, style: muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
