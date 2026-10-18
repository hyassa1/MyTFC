import '../../features/auth/presentation/auth_controller.dart';
import 'routes.dart';

/// Règles de redirection selon l'état de connexion (fonction pure, testée).
///
/// * Sans compte : les pages payantes, le profil et les offres renvoient vers
///   la connexion, qui rouvrira la page demandée ensuite.
/// * Connecté avec un profil incomplet : création du profil d'abord.
/// * Connecté : la page de connexion renvoie à l'accueil.
String? authRedirect(AuthState auth, Uri location) {
  if (auth.status == AuthStatus.unknown) return null;
  final path = location.path;
  final from = location.queryParameters[Routes.fromParam];
  final isAuthPage = path == Routes.login || path == Routes.otp;

  if (!auth.isSignedIn) {
    if (Routes.needsAccount(path) || path == Routes.profileSetup) {
      return Uri(path: Routes.login, queryParameters: {Routes.fromParam: location.toString()}).toString();
    }
    return null;
  }

  if (auth.needsProfile && path != Routes.profileSetup && !isAuthPage) {
    return Uri(path: Routes.profileSetup, queryParameters: {Routes.fromParam: location.toString()}).toString();
  }
  if (isAuthPage) return _safe(from) ?? Routes.home;
  return null;
}

/// N'accepte qu'un chemin interne (jamais une adresse externe).
String? _safe(String? from) =>
    (from != null && from.startsWith('/') && !from.startsWith('//')) ? from : null;
