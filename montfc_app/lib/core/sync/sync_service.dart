import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/store/domain/entitlement.dart';
import '../content/content_kinds.dart';
import '../database/kv_store.dart';
import '../database/local_database.dart';
import '../security/content_cipher.dart';
import 'sync_remote.dart';

/// Résultat d'une synchronisation, pour l'affichage et les journaux.
class SyncResult {
  const SyncResult({required this.pushed, required this.pulledAt, this.error});

  const SyncResult.skipped() : pushed = 0, pulledAt = null, error = null;

  final int pushed;
  final DateTime? pulledAt;
  final Object? error;

  bool get ok => error == null;
}

/// Synchronisation entre la base locale et Supabase.
///
/// Déroulé de [sync] :
/// 1. envoi des modifications faites hors ligne (`push_changes`, la dernière
///    modification gagne côté serveur) ;
/// 2. réception de tout ce qui a changé depuis la dernière synchro
///    (`sync_changes`), en UN seul appel réseau ;
/// 3. application locale dans une transaction ; les corps payants sont
///    chiffrés avant écriture.
///
/// Les appels concurrents sont fusionnés : un seul échange à la fois.
class SyncService {
  SyncService({
    required this._local,
    required this._kv,
    required this._cipher,
    this._remote,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalDatabase _local;
  final KvStore _kv;
  final ContentCipher _cipher;
  final SyncRemote? _remote;
  final DateTime Function() _clock;

  Future<SyncResult>? _inFlight;

  /// Synchronise maintenant. Ne lève pas d'exception : l'erreur éventuelle
  /// est renvoyée dans [SyncResult.error] (réseau instable = cas normal).
  Future<SyncResult> sync() {
    if (_remote == null) return Future.value(const SyncResult.skipped());
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  Future<SyncResult> _run() async {
    try {
      final pushed = await _push();
      final sinceText = await _kv.get(KvStore.lastSyncKey);
      final since = sinceText == null ? null : DateTime.parse(sinceText);
      final payload = await _remote!.syncChanges(since);
      await applyChanges(payload);
      final serverTime = DateTime.parse(payload['server_time'] as String);
      await _kv.set(KvStore.lastSyncKey, serverTime.toIso8601String());
      return SyncResult(pushed: pushed, pulledAt: serverTime);
    } catch (e) {
      return SyncResult(pushed: 0, pulledAt: null, error: e);
    }
  }

  /// Oublie la date de dernière synchro : la prochaine récupère tout.
  /// Utilisé à la connexion d'un nouveau compte.
  Future<void> resetCursor() => _kv.remove(KvStore.lastSyncKey);

  /// Charge le contenu gratuit embarqué dans l'APK (premier lancement hors
  /// ligne). Le fichier a le même format qu'une réponse de `sync_changes`.
  Future<void> loadSeedIfNeeded(Future<String> Function() readSeed) async {
    if (await _kv.get(KvStore.seedLoadedKey) != null) return;
    if (await _kv.get(KvStore.lastSyncKey) != null) return;
    final payload = jsonDecode(await readSeed()) as Map<String, dynamic>;
    await applyChanges(payload, includeUserData: false);
    await _kv.set(KvStore.seedLoadedKey, '1');
  }

  // ---------------------------------------------------------------------------
  // Envoi
  // ---------------------------------------------------------------------------

  Future<int> _push() async {
    final works = await _local.db.query('student_works', where: 'dirty = 1');
    final entries = await _local.db.query('bibliography_entries', where: 'dirty = 1');
    if (works.isEmpty && entries.isEmpty) return 0;

    Map<String, dynamic> toPayload(Map<String, Object?> row) => {
          ...jsonDecode(row['data'] as String) as Map<String, dynamic>,
          'id': row['id'],
          'updated_at': row['updated_at'],
          'deleted_at': row['deleted_at'],
        };

    await _remote!.pushChanges(
      works.map(toPayload).toList(),
      entries.map((r) => {...toPayload(r), 'work_id': r['work_id'], 'kind': r['kind']}).toList(),
    );

    // On ne nettoie que les lignes inchangées depuis l'envoi : une
    // modification faite pendant l'échange reste à envoyer.
    await _local.db.transaction((txn) async {
      for (final w in works) {
        await txn.update('student_works', {'dirty': 0},
            where: 'id = ? AND updated_at = ?', whereArgs: [w['id'], w['updated_at']]);
      }
      for (final e in entries) {
        await txn.update('bibliography_entries', {'dirty': 0},
            where: 'id = ? AND updated_at = ?', whereArgs: [e['id'], e['updated_at']]);
      }
    });
    return works.length + entries.length;
  }

  // ---------------------------------------------------------------------------
  // Réception
  // ---------------------------------------------------------------------------

  /// Applique une réponse de `sync_changes` (ou le contenu embarqué).
  Future<void> applyChanges(Map<String, dynamic> payload, {bool includeUserData = true}) async {
    // Le chiffrement est asynchrone : on le fait avant d'ouvrir la transaction.
    final bodies = <({BodyKind kind, String id, String cipher, String? updatedAt})>[];
    for (final kind in BodyKind.values) {
      for (final row in _rows(payload[kind.syncKey])) {
        bodies.add((
          kind: kind,
          id: row['template_id'] as String,
          cipher: await _cipher.encryptJson(row),
          updatedAt: row['updated_at'] as String?,
        ));
      }
    }

    ({EntitlementSet set, String cipher})? rights;
    if (includeUserData && payload.containsKey('entitlements')) {
      final list = _rows(payload['entitlements']);
      rights = (
        set: EntitlementSet(list.map(Entitlement.fromJson).toList()),
        cipher: await _cipher.encryptJson(list),
      );
    }

    await _local.db.transaction((txn) async {
      for (final kind in ContentKind.values) {
        if (kind == ContentKind.setting) {
          final settings = payload['settings'];
          if (settings is Map) {
            for (final entry in settings.entries) {
              await _upsertItem(txn, kind, entry.key as String, {'key': entry.key, 'value': entry.value});
            }
          }
          continue;
        }
        for (final row in _rows(payload[kind.syncKey])) {
          final id = kind == ContentKind.productPrice
              ? '${row['product_id']}:${row['currency']}'
              : row['id'] as String;
          await _upsertItem(txn, kind, id, row);
        }
      }

      for (final b in bodies) {
        await txn.insert(
          'content_bodies',
          {'kind': b.kind.name, 'template_id': b.id, 'cipher': b.cipher, 'updated_at': b.updatedAt},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (rights case (:final set, :final cipher)) {
        await _kv.set(KvStore.entitlementsKey, cipher, txn: txn);
        await _purgeInaccessibleBodies(txn, set);
      }

      if (includeUserData) {
        if (payload['profile'] is Map) {
          await _kv.set('user.profile', jsonEncode(payload['profile']), txn: txn);
        }
        for (final row in _rows(payload['student_works'])) {
          await _mergeUserRow(txn, 'student_works', row);
        }
        for (final row in _rows(payload['bibliography_entries'])) {
          await _mergeUserRow(txn, 'bibliography_entries', row);
        }
      }
    });
  }

  Future<void> _upsertItem(Transaction txn, ContentKind kind, String id, Map<String, dynamic> row) =>
      txn.insert(
        'content_items',
        {
          'kind': kind.name,
          'id': id,
          'data': jsonEncode(row),
          'position': (row['position'] as num?)?.toInt() ?? 0,
          'updated_at': row['updated_at'] as String?,
          'deleted': row['deleted_at'] == null ? 0 : 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// Un droit expiré ou révoqué : on efface du téléphone les corps devenus
  /// inaccessibles (ils seront re-téléchargés après un nouvel achat).
  Future<void> _purgeInaccessibleBodies(Transaction txn, EntitlementSet rights) async {
    final now = _clock();
    final stored = await txn.query('content_bodies', columns: ['kind', 'template_id']);
    for (final row in stored) {
      final kind = BodyKind.values.byName(row['kind'] as String);
      final id = row['template_id'] as String;
      if (!rights.hasAccess(kind.feature, resourceId: id, now: now)) {
        await txn.delete('content_bodies',
            where: 'kind = ? AND template_id = ?', whereArgs: [kind.name, id]);
      }
    }
  }

  /// Fusion « la dernière modification gagne » pour les données de l'étudiant.
  /// Une ligne locale modifiée hors ligne (dirty) et plus récente que celle du
  /// serveur est conservée ; elle sera envoyée à la prochaine synchro.
  Future<void> _mergeUserRow(Transaction txn, String table, Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdated = DateTime.parse(row['updated_at'] as String);
    final existing = await txn.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isNotEmpty && existing.first['dirty'] == 1) {
      final localUpdated = DateTime.parse(existing.first['updated_at'] as String);
      if (localUpdated.isAfter(remoteUpdated)) return;
    }

    final data = Map<String, dynamic>.from(row)
      ..remove('id')
      ..remove('user_id')
      ..remove('updated_at')
      ..remove('server_updated_at')
      ..remove('deleted_at');
    final values = <String, Object?>{
      'id': id,
      'data': jsonEncode(data),
      'updated_at': remoteUpdated.toIso8601String(),
      'deleted_at': row['deleted_at'],
      'dirty': 0,
    };
    if (table == 'bibliography_entries') {
      data
        ..remove('work_id')
        ..remove('kind');
      values['data'] = jsonEncode(data);
      values['work_id'] = row['work_id'];
      values['kind'] = row['kind'];
    }
    await txn.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : const [];
}
