import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/features/profile/domain/profile.dart';
import 'package:montfc/features/works/data/works_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late LocalDatabase local;

  setUp(() async => local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => local.close());

  test('page de garde enregistrée hors ligne : marquée à envoyer, colonnes du travail remplies', () async {
    final repo = WorksRepository(local, clock: () => DateTime.utc(2026, 10, 18, 9));
    expect(await repo.current(), isNull);

    final work = await repo.currentOrNew();
    await repo.save(work.withCover('tpl-1', {
      'title': ' Mon sujet ',
      'director': 'Prof. Lukusa',
      'supervisor': '',
      'grade': 'memoire_licence',
    }));

    final saved = (await repo.current())!;
    expect(saved.id, work.id);
    expect(saved.title, 'Mon sujet');
    expect(saved.workType, WorkType.memoireLicence);
    expect(saved.supervisor, isNull);
    expect(saved.coverTemplateId, 'tpl-1');
    final row = (await local.db.query('student_works')).single;
    expect(row['dirty'], 1);
    expect(row['updated_at'], '2026-10-18T09:00:00.000Z');
  });

  test('changer de modèle garde les autres valeurs ; colonnes serveur inconnues conservées', () async {
    await local.db.insert('student_works', {
      'id': 'w1',
      'data': jsonEncode({'id': 'w1', 'user_id': 'u1', 'cover_data': {'title': 'A', 'institution_name': 'ISC'}}),
      'updated_at': '2026-10-01T00:00:00Z',
      'dirty': 0,
    });
    final repo = WorksRepository(local);
    final w = (await repo.current())!;
    await repo.save(w.withCover('tpl-2', {'title': 'B'}));

    final data = jsonDecode((await local.db.query('student_works')).single['data'] as String) as Map;
    expect(data['user_id'], 'u1');
    expect(data['cover_data'], {'title': 'B', 'institution_name': 'ISC'});
  });
}
