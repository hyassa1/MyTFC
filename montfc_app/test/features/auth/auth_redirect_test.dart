import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/router/auth_redirect.dart';
import 'package:montfc/core/router/routes.dart';
import 'package:montfc/features/auth/data/auth_repository.dart';
import 'package:montfc/features/auth/presentation/auth_controller.dart';
import 'package:montfc/features/profile/domain/profile.dart';

void main() {
  const guest = AuthState(status: AuthStatus.guest);
  const user = AuthUser(id: 'u1', phone: '243812345678');
  const incomplete = AuthState(status: AuthStatus.signedIn, user: user, profile: Profile(id: 'u1'));
  const complete = AuthState(
    status: AuthStatus.signedIn,
    user: user,
    profile: Profile(
      id: 'u1',
      fullName: 'Étudiant',
      institutionId: 'i',
      faculty: 'Droit',
      level: AcademicLevel.l3,
      workType: WorkType.tfc,
      academicYear: '2026-2027',
    ),
  );

  String? go(AuthState s, String location) => authRedirect(s, Uri.parse(location));

  test('sans compte : les fonctions gratuites restent ouvertes', () {
    for (final path in [Routes.home, Routes.guide, Routes.sampleSize, Routes.checklist]) {
      expect(go(guest, path), isNull, reason: path);
    }
  });

  test('sans compte : une page payante mène à la connexion puis revient', () {
    final target = go(guest, Routes.cover)!;
    expect(Uri.parse(target).path, Routes.login);
    expect(Uri.parse(target).queryParameters[Routes.fromParam], Routes.cover);
  });

  test('profil incomplet : création du profil d\'abord, quelle que soit la page', () {
    expect(Uri.parse(go(incomplete, Routes.guide)!).path, Routes.profileSetup);
    expect(Uri.parse(go(incomplete, Routes.cover)!).queryParameters[Routes.fromParam], Routes.cover);
    expect(go(incomplete, Routes.profileSetup), isNull);
  });

  test('connecté : la connexion renvoie à la page demandée, jamais à une adresse externe', () {
    expect(go(complete, '${Routes.login}?${Routes.fromParam}=${Uri.encodeComponent(Routes.store)}'), Routes.store);
    expect(go(complete, '${Routes.login}?${Routes.fromParam}=${Uri.encodeComponent('//evil.example')}'), Routes.home);
    expect(go(complete, Routes.cover), isNull);
  });

  test('démarrage : aucune redirection tant que la session n\'est pas lue', () {
    expect(go(const AuthState(status: AuthStatus.unknown), Routes.cover), isNull);
  });
}
