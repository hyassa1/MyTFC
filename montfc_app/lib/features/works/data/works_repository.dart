import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/local_database.dart';
import '../domain/student_work.dart';

/// Travaux de l'étudiant sur le téléphone. Chaque modification est marquée
/// « à envoyer » (dirty) et part au serveur à la prochaine synchronisation.
class WorksRepository {
  WorksRepository(this._local, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final LocalDatabase _local;
  final DateTime Function() _clock;

  /// Le travail en cours (le plus récemment modifié), ou null.
  Future<StudentWork?> current() async {
    final rows = await _local.db.query('student_works',
        where: 'deleted_at IS NULL', orderBy: 'updated_at DESC', limit: 1);
    if (rows.isEmpty) return null;
    return StudentWork.fromJson({
      ...jsonDecode(rows.first['data'] as String) as Map<String, dynamic>,
      'id': rows.first['id'],
    });
  }

  /// Le travail en cours, ou un nouveau travail vide (pas encore enregistré).
  Future<StudentWork> currentOrNew() async => await current() ?? StudentWork(id: const Uuid().v4());

  Future<void> save(StudentWork work) async {
    // Les colonnes serveur inconnues de l'app (user_id…) sont gardées.
    final existing = await _local.db.query('student_works', where: 'id = ?', whereArgs: [work.id], limit: 1);
    final previous =
        existing.isEmpty ? <String, dynamic>{} : jsonDecode(existing.first['data'] as String) as Map<String, dynamic>;
    await _local.db.insert(
      'student_works',
      {
        'id': work.id,
        'data': jsonEncode({...previous, ...work.toJson()}),
        'updated_at': _clock().toUtc().toIso8601String(),
        'deleted_at': null,
        'dirty': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
