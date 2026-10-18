import 'package:sqflite/sqflite.dart';

import '../../../core/database/local_database.dart';

/// Cases cochées de la liste de vérification, enregistrées uniquement sur le
/// téléphone (table `checklist_items`).
class ChecklistRepository {
  ChecklistRepository(this._local);

  final LocalDatabase _local;

  Future<Set<String>> checkedIds() async {
    final rows = await _local.db.query('checklist_items', columns: ['item_id'], where: 'checked = 1');
    return rows.map((r) => r['item_id'] as String).toSet();
  }

  Future<void> setChecked(String itemId, bool checked) => _local.db.insert(
        'checklist_items',
        {'item_id': itemId, 'checked': checked ? 1 : 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> reset() => _local.db.delete('checklist_items');
}
