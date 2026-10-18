import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/flavor.dart';
import 'core/database/kv_store.dart';
import 'core/database/local_database.dart';
import 'core/security/content_cipher.dart';
import 'core/security/key_store.dart';
import 'core/providers.dart';
import 'core/sync/sync_service.dart';

/// Démarrage commun aux deux variantes (store / direct).
///
/// 1. ouvre la base locale ;
/// 2. charge le contenu gratuit embarqué au tout premier lancement, pour que
///    le guide soit lisible même sans connexion ;
/// 3. initialise Supabase si l'application a été compilée avec un serveur.
Future<void> bootstrap(AppFlavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  // Licence de la police embarquée (affichée dans « Licences »).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Liberation Serif'],
      await rootBundle.loadString('assets/fonts/LICENSE-LiberationSerif-OFL.txt'),
    );
  });

  final env = Env.fromEnvironment(flavor);
  final local = await LocalDatabase.open();

  // Contenu embarqué (même format qu'une réponse de sync_changes).
  final seedLoader = SyncService(
    local: local,
    kv: KvStore(local),
    cipher: ContentCipher(SecureSecretStore()),
  );
  await seedLoader.loadSeedIfNeeded(() => rootBundle.loadString('assets/seed/content.json'));

  if (env.hasBackend) {
    await Supabase.initialize(url: env.supabaseUrl, publishableKey: env.supabasePublishableKey);
  }

  runApp(ProviderScope(
    overrides: [
      envProvider.overrideWithValue(env),
      localDatabaseProvider.overrideWithValue(local),
    ],
    child: const MonTfcApp(),
  ));
}
