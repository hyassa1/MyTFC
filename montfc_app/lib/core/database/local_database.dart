import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base locale SQLite (sqflite utilise le SQLite d'Android : quasiment aucun
/// poids ajouté à l'APK).
///
/// Tables :
/// * `kv`                   : petites valeurs (date de dernière synchro, droits chiffrés…)
/// * `content_items`        : cache du contenu public (guide, catalogue, métadonnées des modèles)
/// * `content_bodies`       : corps des modèles payants, CHIFFRÉS (AES-GCM)
/// * `student_works`        : travaux de l'étudiant (synchronisés)
/// * `bibliography_entries` : sources bibliographiques (synchronisées)
/// * `checklist_items`      : liste de vérification avant dépôt (locale uniquement)
///
/// Les colonnes `dirty` marquent les lignes modifiées hors ligne, à envoyer
/// au serveur à la prochaine connexion.
class LocalDatabase {
  LocalDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 1;
  static const String fileName = 'montfc.db';

  /// Ouvre (ou crée) la base. [factory] et [path] servent aux tests
  /// (sqflite_common_ffi, base en mémoire).
  static Future<LocalDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
    return LocalDatabase._(db);
  }

  Future<void> close() => db.close();

  /// Migrations successives : ajouter un bloc `if (from < N)` par version.
  static Future<void> _migrate(Database db, int from, int to) async {
    final batch = db.batch();
    if (from < 1) {
      batch.execute('''
        CREATE TABLE kv (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE content_items (
          kind       TEXT NOT NULL,
          id         TEXT NOT NULL,
          data       TEXT NOT NULL,
          position   INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT,
          deleted    INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (kind, id)
        )''');
      batch.execute('''
        CREATE TABLE content_bodies (
          kind        TEXT NOT NULL,
          template_id TEXT NOT NULL,
          cipher      TEXT NOT NULL,
          updated_at  TEXT,
          PRIMARY KEY (kind, template_id)
        )''');
      batch.execute('''
        CREATE TABLE student_works (
          id         TEXT PRIMARY KEY,
          data       TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          dirty      INTEGER NOT NULL DEFAULT 0
        )''');
      batch.execute('''
        CREATE TABLE bibliography_entries (
          id         TEXT PRIMARY KEY,
          work_id    TEXT,
          kind       TEXT NOT NULL,
          data       TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          dirty      INTEGER NOT NULL DEFAULT 0
        )''');
      batch.execute('CREATE INDEX bibliography_entries_work_idx ON bibliography_entries (work_id)');
      batch.execute('''
        CREATE TABLE checklist_items (
          item_id    TEXT PRIMARY KEY,
          checked    INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        )''');
    }
    await batch.commit(noResult: true);
  }
}
