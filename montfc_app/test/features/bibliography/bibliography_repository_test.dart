import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/features/bibliography/data/bibliography_repository.dart';
import 'package:montfc/features/bibliography/domain/source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late LocalDatabase local;

  setUp(() async => local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => local.close());

  test('enregistrée hors ligne au format attendu par le serveur, suppression envoyée aussi', () async {
    final repo = BibliographyRepository(local, clock: () => DateTime.utc(2026, 10, 18));
    const s = Source(id: 's1', kind: SourceKind.article, title: 'Microfinance', journal: 'Revue', year: '2021',
        authors: [Person(last: 'Mbuyi', first: 'Jean')], workId: 'w1');
    await repo.save(s);

    final row = (await local.db.query('bibliography_entries')).single;
    expect(row['dirty'], 1);
    expect(row['kind'], 'article');
    expect(row['work_id'], 'w1');
    // La synchro envoie {...data, id, kind, work_id} : la source est sous la clé « data ».
    expect((jsonDecode(row['data'] as String) as Map)['data']['journal'], 'Revue');

    final back = (await repo.all()).single;
    expect(back.authors.single.last, 'Mbuyi');
    expect(back.workId, 'w1');

    await repo.delete('s1');
    expect(await repo.all(), isEmpty);
    final deleted = (await local.db.query('bibliography_entries')).single;
    expect(deleted['deleted_at'], isNotNull);
    expect(deleted['dirty'], 1);
  });
}
