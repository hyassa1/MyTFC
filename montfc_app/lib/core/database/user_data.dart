import 'kv_store.dart';
import 'local_database.dart';

/// Gestion des données locales liées au compte connecté.
///
/// * À la déconnexion (volontaire ou imposée par un autre appareil), on
///   efface TOUJOURS les droits et le contenu payant : ils ne doivent pas
///   rester lisibles sans session.
/// * Les travaux de l'étudiant ne sont effacés que si un AUTRE compte se
///   connecte sur ce téléphone, ou à une déconnexion volontaire : une
///   déconnexion imposée garde les modifications non envoyées, qui partiront
///   à la reconnexion du même compte.
class UserData {
  UserData(this._local, this._kv);

  static const ownerKey = 'user.id';
  static const profileKey = 'user.profile';

  final LocalDatabase _local;
  final KvStore _kv;

  /// Nombre de modifications pas encore envoyées au serveur.
  Future<int> pendingChanges() async {
    final rows = await _local.db.rawQuery('''
      SELECT (SELECT COUNT(*) FROM student_works WHERE dirty = 1)
           + (SELECT COUNT(*) FROM bibliography_entries WHERE dirty = 1) AS n''');
    return (rows.first['n'] as int?) ?? 0;
  }

  /// À appeler après une connexion réussie, avant la première synchro.
  Future<void> attachTo(String userId) async {
    final previous = await _kv.get(ownerKey);
    if (previous != null && previous != userId) {
      await clearAll();
    }
    await _kv.set(ownerKey, userId);
  }

  /// Retire l'accès au contenu payant (droits + corps chiffrés + profil).
  /// La date de synchro est oubliée : la prochaine connexion récupère tout.
  Future<void> clearAccess() => _local.db.transaction((txn) async {
        await txn.delete('content_bodies');
        await _kv.remove(KvStore.entitlementsKey, txn: txn);
        await _kv.remove(profileKey, txn: txn);
        await _kv.remove(KvStore.lastSyncKey, txn: txn);
      });

  /// Efface aussi les travaux et la bibliographie du compte précédent.
  Future<void> clearAll() async {
    await clearAccess();
    await _local.db.transaction((txn) async {
      await txn.delete('bibliography_entries');
      await txn.delete('student_works');
      await _kv.remove(ownerKey, txn: txn);
    });
  }
}
