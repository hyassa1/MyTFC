/// Erreur d'authentification présentée à l'étudiant, en français.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  static const network = AuthFailure(
      'Connexion internet indisponible. Vérifie ta connexion puis réessaie.');
  static const invalidCode = AuthFailure('Code incorrect ou expiré. Vérifie le SMS ou demande un nouveau code.');
  static const tooManyRequests = AuthFailure(
      'Trop de demandes de code. Patiente quelques minutes avant de réessayer.');
  static const invalidPhone = AuthFailure('Numéro invalide. Exemple : 0812345678.');
  static const noBackend = AuthFailure('La connexion n\'est pas disponible dans cette version de l\'application.');
  static const unknown = AuthFailure('Une erreur est survenue. Réessaie dans un instant.');

  @override
  String toString() => message;
}
