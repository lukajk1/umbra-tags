import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

class LibraryTag {
  LibraryTag.fromMap(Map row)
    : id = row['id'] as String,
      name = row['name'] as String,
      parentId = row['parent_id'] as String?,
      assetCount = row['asset_count'] as int? ?? 0,
      excludedFromAll = row['excluded_from_all'] == 1;
  final String id, name;
  final String? parentId;

  /// Whether this is a reference tag (stored as `excluded_from_all`): images
  /// carrying it or a descendant are hidden from every view except views
  /// filtered by this tag or one of its descendants.
  final bool excludedFromAll;

  /// A reference tag; see [excludedFromAll].
  bool get isReference => excludedFromAll;

  /// Non-archived images shown in this tag's view: those with the tag or any
  /// of its descendants, minus images hidden by reference tags other than
  /// this tag and its ancestors.
  final int assetCount;
}

/// Used only on the library worker. Schema v1 already includes these tables.
class TagRepository {
  TagRepository(this.db);
  final Database db;
  static const descendants = '''WITH RECURSIVE descendants(id) AS (
    SELECT id FROM tags WHERE id = ?
    UNION SELECT t.id FROM tags t JOIN descendants d ON t.parent_id = d.id
  )''';

  /// Every tag with its view's image count (see [LibraryTag.assetCount]).
  /// Counts are computed here rather than in SQL because with reference tags
  /// each view's rule depends on the view tag's own ancestors.
  List<Map<String, Object?>> tags() {
    final rows = db
        .select('''SELECT id,name,parent_id,excluded_from_all FROM tags
          ORDER BY name COLLATE NOCASE,id''')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final parent = {
      for (final row in rows) row['id'] as String: row['parent_id'] as String?,
    };
    final references = {
      for (final row in rows)
        if (row['excluded_from_all'] == 1) row['id'] as String,
    };
    // Each tag with its ancestors.
    final lineage = <String, Set<String>>{};
    for (final id in parent.keys) {
      final chain = <String>{};
      for (
        String? at = id;
        at != null && parent.containsKey(at);
        at = parent[at]
      ) {
        if (!chain.add(at)) break;
      }
      lineage[id] = chain;
    }
    final assetTags = <String, List<String>>{};
    for (final row in db.select('''SELECT at.asset_id,at.tag_id
        FROM asset_tags at JOIN assets a ON a.id = at.asset_id
        WHERE a.archived = 0''')) {
      (assetTags[row['asset_id'] as String] ??= []).add(
        row['tag_id'] as String,
      );
    }
    final counts = <String, int>{};
    for (final tagIds in assetTags.values) {
      // Views that would list the image: its tags and their ancestors. It
      // stays in a view only if every reference tag above (or among) its tags
      // is the view tag or one of the view tag's ancestors.
      final views = <String>{};
      final referenced = <String>{};
      for (final tag in tagIds) {
        for (final at in lineage[tag] ?? const <String>{}) {
          views.add(at);
          if (references.contains(at)) referenced.add(at);
        }
      }
      for (final view in views) {
        if (referenced.every(lineage[view]!.contains)) {
          counts[view] = (counts[view] ?? 0) + 1;
        }
      }
    }
    for (final row in rows) {
      row['asset_count'] = counts[row['id']] ?? 0;
    }
    return rows;
  }

  String save({String? id, required String name, String? parentId}) {
    name = name.trim();
    if (name.isEmpty || name.length > 120) {
      throw StateError('Tag names must contain 1–120 characters.');
    }
    if (id != null) _requireTag(id);
    if (parentId != null) _requireTag(parentId);
    if (db.select(
      'SELECT id FROM tags WHERE name = ? COLLATE NOCASE AND id != ?',
      [name, id ?? ''],
    ).isNotEmpty) {
      throw StateError('A tag with that name already exists.');
    }
    if (id != null &&
        parentId != null &&
        db.select('$descendants SELECT id FROM descendants WHERE id = ?', [
          id,
          parentId,
        ]).isNotEmpty) {
      throw StateError(
        'A tag cannot be placed inside itself or its descendants.',
      );
    }
    final result = id ?? const Uuid().v4();
    if (id == null) {
      db.execute('INSERT INTO tags(id,name,parent_id) VALUES (?,?,?)', [
        result,
        name,
        parentId,
      ]);
    } else {
      db.execute('UPDATE tags SET name = ?,parent_id = ? WHERE id = ?', [
        name,
        parentId,
        id,
      ]);
    }
    return result;
  }

  void delete(String id) {
    _requireTag(id);
    final parent = db.select('SELECT parent_id FROM tags WHERE id = ?', [
      id,
    ]).first['parent_id'];
    _transaction(() {
      db.execute('UPDATE tags SET parent_id = ? WHERE parent_id = ?', [
        parent,
        id,
      ]);
      db.execute('DELETE FROM tags WHERE id = ?', [id]);
    });
  }

  void editAssignments(
    List<String> assetIds,
    List<String> add,
    List<String> remove,
  ) {
    if (add.toSet().intersection(remove.toSet()).isNotEmpty) {
      throw StateError('A tag cannot be both added and removed.');
    }
    for (final id in {...add, ...remove}) {
      _requireTag(id);
    }
    _transaction(() {
      for (final asset in assetIds.toSet()) {
        if (db.select('SELECT id FROM assets WHERE id = ?', [asset]).isEmpty) {
          throw StateError('An image no longer exists in this library.');
        }
        for (final tag in add.toSet()) {
          db.execute(
            'INSERT OR IGNORE INTO asset_tags(asset_id,tag_id) VALUES (?,?)',
            [asset, tag],
          );
        }
        for (final tag in remove.toSet()) {
          db.execute(
            'DELETE FROM asset_tags WHERE asset_id = ? AND tag_id = ?',
            [asset, tag],
          );
        }
      }
    });
  }

  void setExcludedFromAll(String id, bool excluded) {
    _requireTag(id);
    db.execute('UPDATE tags SET excluded_from_all = ? WHERE id = ?', [
      excluded ? 1 : 0,
      id,
    ]);
  }

  /// Image counts for the built-in views, matching what each view lists:
  /// All images leaves out images hidden by reference tags.
  Map<String, int> viewCounts() {
    int count(Map args) => assets(args).length;
    return {
      'all': count({'excludeHidden': true}),
      'untagged': count({'untagged': true}),
      'archived': count({'archived': true}),
    };
  }

  /// Images for a view. Outside the archive, reference tags (stored as
  /// `excluded_from_all`) hide images carrying them or a descendant unless
  /// the view is filtered by that reference tag or one of its descendants.
  /// Tag views always apply this; the unfiltered view only with
  /// `excludeHidden` (All images).
  List<Map<String, Object?>> assets(Map args) {
    final tagId = args['tagId'] as String?;
    final archived = args['archived'] == true;
    final hideReferenced =
        !archived && (tagId != null || args['excludeHidden'] == true);
    final ctes = <String>[];
    final parameters = <Object?>[];
    if (tagId != null) {
      ctes.add('''descendants(id) AS (
        SELECT id FROM tags WHERE id = ?
        UNION SELECT t.id FROM tags t JOIN descendants d ON t.parent_id = d.id
      )''');
      parameters.add(tagId);
    }
    if (hideReferenced) {
      // The view tag and its ancestors (none without a tag): reference tags
      // among them hide nothing here. Every other reference tag hides its
      // whole subtree, including reference tags nested inside the view tag.
      ctes.add('''ancestors(id) AS (
        SELECT id FROM tags WHERE id = ?
        UNION SELECT t.parent_id FROM tags t JOIN ancestors an ON t.id = an.id
          WHERE t.parent_id IS NOT NULL
      )''');
      parameters.add(tagId);
      ctes.add('''hidden(id) AS (
        SELECT id FROM tags WHERE excluded_from_all = 1
          AND id NOT IN (SELECT id FROM ancestors)
        UNION SELECT t.id FROM tags t JOIN hidden h ON t.parent_id = h.id
      )''');
    }
    parameters.add(archived ? 1 : 0);
    final query =
        '''${ctes.isEmpty ? '' : 'WITH RECURSIVE ${ctes.join(',\n')}'}
      SELECT a.* FROM assets a WHERE a.archived = ?
      ${args['starredOnly'] == true ? 'AND a.starred = 1' : ''}
      ${args['untagged'] == true ? 'AND NOT EXISTS (SELECT 1 FROM asset_tags at WHERE at.asset_id = a.id)' : ''}
      ${tagId == null ? '' : 'AND EXISTS (SELECT 1 FROM asset_tags at JOIN descendants d ON d.id = at.tag_id WHERE at.asset_id = a.id)'}
      ${hideReferenced ? 'AND NOT EXISTS (SELECT 1 FROM asset_tags at JOIN hidden h ON h.id = at.tag_id WHERE at.asset_id = a.id)' : ''}
      ORDER BY a.imported_at DESC,a.id''';
    final result = db
        .select(query, parameters)
        .map((r) => <String, Object?>{...r, 'tag_ids': <String>[]})
        .toList();
    final byId = {for (final row in result) row['id']: row};
    for (final assignment in db.select(
      'SELECT asset_id,tag_id FROM asset_tags',
    )) {
      final row = byId[assignment['asset_id']];
      if (row != null) {
        (row['tag_ids'] as List<String>).add(assignment['tag_id'] as String);
      }
    }
    return result;
  }

  void _requireTag(String id) {
    if (db.select('SELECT id FROM tags WHERE id = ?', [id]).isEmpty) {
      throw StateError('This tag no longer exists.');
    }
  }

  void _transaction(void Function() operation) {
    db.execute('BEGIN IMMEDIATE');
    try {
      operation();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
