import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

/// Petites valeurs clé/texte persistées dans la base locale.
class KvStore {
  KvStore(this._local);

  final LocalDatabase _local;

  static const lastSyncKey = 'sync.last_server_time';
  static const entitlementsKey = 'store.entitlements_cipher';
  static const seedLoadedKey = 'content.seed_loaded';

  Future<String?> get(String key, {DatabaseExecutor? txn}) async {
    final rows = await (txn ?? _local.db).query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> set(String key, String value, {DatabaseExecutor? txn}) =>
      (txn ?? _local.db).insert('kv', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> remove(String key, {DatabaseExecutor? txn}) =>
      (txn ?? _local.db).delete('kv', where: 'key = ?', whereArgs: [key]);
}
