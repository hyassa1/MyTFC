/// Chemins de navigation de l'application.
abstract final class Routes {
  static const home = '/';
  static const login = '/connexion';
  static const otp = '/connexion/code';
  static const profileSetup = '/profil/creation';
  static const profile = '/profil';
  static const profileEdit = '/profil/modifier';
  static const guide = '/guide';
  static String guideChapter(String slug) => '/guide/$slug';
  static const sampleSize = '/echantillon';
  static const checklist = '/verification';
  static const cover = '/page-de-garde';
  static String coverEditor(String templateId) => '/page-de-garde/$templateId';
  static const bibliography = '/bibliographie';
  static const sourceNew = '/bibliographie/ajouter';
  static String sourceEdit(String id) => '/bibliographie/source/$id';
  static const templates = '/modeles';
  static String template(String id) => '/modeles/$id';
  static const questionnaires = '/questionnaires';
  static String questionnaire(String id) => '/questionnaires/$id';
  static const export = '/export';
  static const store = '/boutique';
  static const purchase = '/boutique/achat';

  /// Pages qui demandent un compte (fonctions payantes, profil, offres).
  /// Les fonctions gratuites restent accessibles sans compte.
  static const requiresAccount = {
    cover,
    bibliography,
    templates,
    questionnaires,
    export,
    store,
    purchase,
    profile,
    profileEdit,
  };

  /// Vrai pour une page de [requiresAccount] ou une de ses sous-pages.
  static bool needsAccount(String path) =>
      requiresAccount.any((p) => path == p || path.startsWith('$p/'));

  /// Paramètre de requête qui porte la page à rouvrir après la connexion.
  static const fromParam = 'depuis';
}
