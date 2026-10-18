import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/local_database.dart';
import '../domain/source.dart';

/// Sources bibliographiques sur le téléphone, envoyées au serveur à la
/// prochaine synchronisation (dirty = 1). Suppression = marquage
/// (deleted_at), pour que l'effacement parte aussi au serveur.
class BibliographyRepository {
  BibliographyRepository(this._local, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final LocalDatabase _local;
  final DateTime Function() _clock;

  String _now() => _clock().toUtc().toIso8601String();

  Future<List<Source>> all() async {
    final rows = await _local.db.query('bibliography_entries', where: 'deleted_at IS NULL');
    return [
      for (final r in rows)
        Source.fromJson(
          r['id'] as String,
          SourceKind.fromCode(r['kind'] as String?),
          // Colonne locale = ligne serveur sans ses colonnes techniques : {"data": {...}}.
          Map<String, dynamic>.from((jsonDecode(r['data'] as String) as Map)['data'] as Map? ?? const {}),
          workId: r['work_id'] as String?,
        ),
    ];
  }

  Future<void> save(Source source) => _local.db.insert(
        'bibliography_entries',
        {
          'id': source.id,
          'work_id': source.workId,
          'kind': source.kind.code,
          'data': jsonEncode({'data': source.toJson()}),
          'updated_at': _now(),
          'deleted_at': null,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> delete(String id) => _local.db.update(
        'bibliography_entries',
        {'deleted_at': _now(), 'updated_at': _now(), 'dirty': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
}
