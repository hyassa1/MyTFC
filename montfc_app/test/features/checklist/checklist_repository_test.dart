import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/features/checklist/data/checklist_repository.dart';
import 'package:montfc/features/checklist/domain/checklist_items.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('les cases cochées sont enregistrées sur le téléphone et survivent à la réouverture', () async {
    final dir = await Directory.systemTemp.createTemp('montfc_checklist');
    final path = '${dir.path}/test.db';

    var local = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
    var repo = ChecklistRepository(local);
    await repo.setChecked('fond-sujet-valide', true);
    await repo.setChecked('mef-police', true);
    await repo.setChecked('mef-police', false);
    await local.close();

    local = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
    repo = ChecklistRepository(local);
    expect(await repo.checkedIds(), {'fond-sujet-valide'});

    await repo.reset();
    expect(await repo.checkedIds(), isEmpty);
    await local.close();
    await dir.delete(recursive: true);
  });

  test('les identifiants de la liste sont uniques', () {
    final ids = depositChecklist.expand((s) => s.items).map((i) => i.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });
}
