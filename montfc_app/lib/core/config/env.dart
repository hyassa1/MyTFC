import 'flavor.dart';

/// Configuration de l'application, fournie à la compilation par
/// `--dart-define-from-file=env/<fichier>.json` (voir env/example.json).
///
/// Seules des valeurs PUBLIQUES vont ici : l'URL du projet Supabase et sa clé
/// publique (« publishable key », ou l'ancienne clé « anon »), protégée par la
/// RLS. Les clés de l'agrégateur de paiement restent exclusivement dans les
/// secrets des Edge Functions.
class Env {
  const Env({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  final AppFlavor flavor;
  final String supabaseUrl;
  final String supabasePublishableKey;

  /// Lit les valeurs définies à la compilation.
  factory Env.fromEnvironment(AppFlavor flavor) => Env(
        flavor: flavor,
        supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
        supabasePublishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      );

  /// Faux si l'application a été compilée sans configuration serveur :
  /// elle fonctionne alors uniquement hors ligne, avec le contenu embarqué.
  bool get hasBackend => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
