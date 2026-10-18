import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/content/content_kinds.dart';
import 'package:montfc/core/content/content_store.dart';
import 'package:montfc/core/database/kv_store.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/core/security/content_cipher.dart';
import 'package:montfc/core/security/key_store.dart';
import 'package:montfc/core/sync/sync_remote.dart';
import 'package:montfc/core/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Serveur simulé : renvoie les réponses préparées et garde trace des envois.
class FakeRemote implements SyncRemote {
  final List<Map<String, dynamic>> responses = [];
  final List<DateTime?> sinceCalls = [];
  final List<List<Map<String, dynamic>>> pushedWorks = [];
  bool failNext = false;

  @override
  Future<Map<String, dynamic>> syncChanges(DateTime? since) async {
    sinceCalls.add(since);
    if (failNext) {
      failNext = false;
      throw const SocketException('réseau indisponible');
    }
    return responses.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>> pushChanges(
    List<Map<String, dynamic>> works,
    List<Map<String, dynamic>> entries,
  ) async {
    pushedWorks.add(works);
    return {'works_applied': works.length, 'entries_applied': entries.length};
  }
}

Map<String, dynamic> emptyPayload(String serverTime) => {
      'server_time': serverTime,
      'entitlements': <Object>[],
      'student_works': <Object>[],
      'bibliography_entries': <Object>[],
    };

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late KvStore kv;
  late ContentCipher cipher;
  late FakeRemote remote;
  late SyncService sync;
  late ContentStore content;
  final now = DateTime.utc(2026, 10, 18, 12);

  setUp(() async {
    local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    kv = KvStore(local);
    cipher = ContentCipher(MemorySecretStore());
    remote = FakeRemote();
    sync = SyncService(local: local, kv: kv, cipher: cipher, remote: remote, clock: () => now);
    content = ContentStore(local: local, kv: kv, cipher: cipher, clock: () => now);
  });

  tearDown(() => local.close());

  test('le contenu embarqué rend le guide lisible hors ligne dès le premier lancement', () async {
    final seed = File('assets/seed/content.json').readAsStringSync();
    await sync.loadSeedIfNeeded(() async => seed);

    final chapters = await content.list(ContentKind.guideChapter);
    expect(chapters, hasLength(3));
    expect(chapters.first['slug'], 'choix-du-sujet');
    expect(await content.list(ContentKind.coverTemplate), hasLength(3));
    expect(await content.setting('min_app_version'), '1.0.0');

    // Le contenu embarqué ne contient aucun corps payant.
    expect(jsonDecode(seed)['cover_template_bodies'], isEmpty);
  });

  test('le contenu embarqué n\'est chargé qu\'une fois', () async {
    var reads = 0;
    Future<String> read() async {
      reads++;
      return File('assets/seed/content.json').readAsStringSync();
    }

    await sync.loadSeedIfNeeded(read);
    await sync.loadSeedIfNeeded(read);
    expect(reads, 1);
  });

  test('un corps payant est stocké chiffré et lisible seulement avec un droit actif', () async {
    remote.responses.add({
      ...emptyPayload('2026-10-18T11:00:00+00:00'),
      'cover_templates': [
        {'id': 'cov-1', 'code': 'COVER_X', 'name': 'X', 'is_published': true, 'updated_at': '2026-10-18T10:00:00+00:00'},
      ],
      'cover_template_bodies': [
        {'template_id': 'cov-1', 'layout': {'blocks': ['MISE-EN-PAGE-SECRETE']}, 'updated_at': '2026-10-18T10:00:00+00:00'},
      ],
      'entitlements': [
        {'id': 'e1', 'feature': 'all', 'resource_id': null, 'starts_at': '2026-10-01T00:00:00+00:00',
         'expires_at': '2027-10-01T00:00:00+00:00', 'revoked_at': null},
      ],
    });

    final result = await sync.sync();
    expect(result.ok, isTrue, reason: '${result.error}');

    final raw = await local.db.query('content_bodies');
    expect(raw, hasLength(1));
    expect((raw.first['cipher'] as String).contains('SECRETE'), isFalse, reason: 'stockage chiffré');

    final body = await content.body(BodyKind.cover, 'cov-1');
    expect(((body!['layout'] as Map)['blocks'] as List).first, 'MISE-EN-PAGE-SECRETE');
    expect(await kv.get(KvStore.lastSyncKey), isNotNull);
  });

  test('un droit qui disparaît efface le corps payant du téléphone', () async {
    remote.responses
      ..add({
        ...emptyPayload('2026-10-18T11:00:00+00:00'),
        'cover_template_bodies': [
          {'template_id': 'cov-1', 'layout': {'a': 1}, 'updated_at': '2026-10-18T10:00:00+00:00'},
        ],
        'entitlements': [
          {'id': 'e1', 'feature': 'cover_page', 'resource_id': null, 'starts_at': '2026-10-01T00:00:00+00:00',
           'expires_at': null, 'revoked_at': null},
        ],
      })
      ..add({
        ...emptyPayload('2026-10-18T11:30:00+00:00'),
        'entitlements': [
          {'id': 'e1', 'feature': 'cover_page', 'resource_id': null, 'starts_at': '2026-10-01T00:00:00+00:00',
           'expires_at': null, 'revoked_at': '2026-10-18T11:20:00+00:00'},
        ],
      });

    await sync.sync();
    expect(await content.body(BodyKind.cover, 'cov-1'), isNotNull);

    await sync.sync();
    expect(await content.body(BodyKind.cover, 'cov-1'), isNull);
    expect(await local.db.query('content_bodies'), isEmpty);
  });

  test('la deuxième synchro ne demande que les changements depuis la première', () async {
    remote.responses
      ..add(emptyPayload('2026-10-18T11:00:00+00:00'))
      ..add(emptyPayload('2026-10-18T11:05:00+00:00'));
    await sync.sync();
    await sync.sync();
    expect(remote.sinceCalls, [null, DateTime.parse('2026-10-18T11:00:00+00:00')]);
  });

  test('sans réseau : erreur renvoyée, curseur et données locales intacts', () async {
    remote.failNext = true;
    final result = await sync.sync();
    expect(result.ok, isFalse);
    expect(await kv.get(KvStore.lastSyncKey), isNull);
  });

  test('les modifications hors ligne sont envoyées puis marquées propres', () async {
    await local.db.insert('student_works', {
      'id': 'w1',
      'data': jsonEncode({'title': 'Mon sujet', 'work_type': 'tfc'}),
      'updated_at': '2026-10-18T09:00:00.000Z',
      'dirty': 1,
    });
    remote.responses.add(emptyPayload('2026-10-18T11:00:00+00:00'));

    final result = await sync.sync();
    expect(result.pushed, 1);
    expect(remote.pushedWorks.single.single['title'], 'Mon sujet');
    expect((await local.db.query('student_works')).single['dirty'], 0);
  });

  test('la dernière modification gagne à la réception', () async {
    // Ligne locale modifiée hors ligne APRÈS la version du serveur : conservée.
    await local.db.insert('student_works', {
      'id': 'w1',
      'data': jsonEncode({'title': 'Version locale récente'}),
      'updated_at': '2026-10-18T10:30:00.000Z',
      'dirty': 1,
    });
    // Ligne locale propre : remplacée par le serveur.
    await local.db.insert('student_works', {
      'id': 'w2',
      'data': jsonEncode({'title': 'Ancienne'}),
      'updated_at': '2026-10-18T08:00:00.000Z',
      'dirty': 0,
    });

    await sync.applyChanges({
      ...emptyPayload('2026-10-18T11:00:00+00:00'),
      'student_works': [
        {'id': 'w1', 'title': 'Version serveur plus ancienne', 'updated_at': '2026-10-18T10:00:00+00:00', 'deleted_at': null},
        {'id': 'w2', 'title': 'Version serveur', 'updated_at': '2026-10-18T09:00:00+00:00', 'deleted_at': null},
      ],
    });

    final rows = {for (final r in await local.db.query('student_works')) r['id']: r};
    expect(jsonDecode(rows['w1']!['data'] as String)['title'], 'Version locale récente');
    expect(rows['w1']!['dirty'], 1);
    expect(jsonDecode(rows['w2']!['data'] as String)['title'], 'Version serveur');
  });

  test('un élément supprimé côté admin disparaît des listes', () async {
    await sync.applyChanges({
      'guide_chapters': [
        {'id': 'c1', 'slug': 'a', 'position': 1, 'is_published': true, 'deleted_at': null},
        {'id': 'c2', 'slug': 'b', 'position': 2, 'is_published': true, 'deleted_at': '2026-10-18T10:00:00+00:00'},
      ],
    }, includeUserData: false);
    expect((await content.list(ContentKind.guideChapter)).map((c) => c['id']), ['c1']);
  });
}
