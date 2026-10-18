import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/core/sync/sync_controller.dart';
import 'package:montfc/features/auth/data/auth_repository.dart';
import 'package:montfc/features/auth/presentation/auth_controller.dart';
import 'package:montfc/features/cover/presentation/cover_screens.dart';
import 'package:montfc/features/profile/domain/profile.dart';
import 'package:montfc/features/profile/presentation/profile_form_screen.dart';
import 'package:montfc/features/store/domain/entitlement.dart';
import 'package:montfc/features/store/domain/offer.dart';
import 'package:montfc/features/store/presentation/store_providers.dart';
import 'package:montfc/features/works/data/works_providers.dart';
import 'package:montfc/features/works/data/works_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../payment/payment_test_support.dart';
import 'cover_test_data.dart';

class _StudentAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.signedIn,
        user: AuthUser(id: testUserId),
        profile: Profile(
          id: testUserId,
          fullName: 'Mbuyi Kalala Jean',
          faculty: 'Sciences économiques',
          institutionId: '00000000-0000-4000-8000-000000000101',
          workType: WorkType.memoireLicence,
          academicYear: '2025-2026',
        ),
      );
}

/// La base sqflite_ffi répond hors de la boucle de test : on lui laisse le temps.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  late LocalDatabase local;

  setUp(() async {
    local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });
  tearDown(() => local.close());

  Future<void> pump(WidgetTester tester, {required bool paid}) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_StudentAuth.new),
        syncControllerProvider.overrideWith(FakeSyncController.new),
        worksRepositoryProvider.overrideWithValue(WorksRepository(local)),
        institutionsProvider.overrideWith((ref) async => const []),
        coverTemplatesProvider.overrideWith((ref) async => coverTemplates()),
        coverLayoutProvider.overrideWith((ref, id) async => layout(id)),
        offersProvider.overrideWith((ref) async => const <Offer>[packOffer]),
        entitlementsProvider.overrideWith((ref) async => paid
            ? EntitlementSet([
                Entitlement(id: 'e', feature: AppFeature.coverPage, startsAt: DateTime(2026)),
              ])
            : EntitlementSet.empty),
      ],
      child: const MaterialApp(home: CoverEditorScreen(templateId: unikinId)),
    ));
    await settle(tester);
  }

  testWidgets('sans achat : invitation à débloquer', (tester) async {
    await pump(tester, paid: false);
    expect(find.text('Contenu à débloquer'), findsOneWidget);
    expect(find.text('Informations'), findsNothing);
  });

  testWidgets('pré-rempli depuis le profil, aperçu en majuscules, enregistrement refusé si incomplet',
      (tester) async {
    await pump(tester, paid: true);
    expect(find.widgetWithText(TextField, 'Mbuyi Kalala Jean'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Sujet du travail *'), 'La trésorerie des PME');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    expect(find.text('Champ obligatoire.'), findsWidgets, reason: 'directeur et discipline manquent');

    await tester.tap(find.text('Aperçu'));
    await settle(tester);
    expect(find.text('LA TRÉSORERIE DES PME'), findsOneWidget);
    expect(find.text('MBUYI KALALA JEAN'), findsOneWidget);
    expect(find.textContaining('[Directeur'), findsOneWidget, reason: 'repère pour un champ vide');

    // Passer à l'aperçu a enregistré la saisie sur le téléphone.
    final work = await tester.runAsync(() => WorksRepository(local).current());
    expect(work?.title, 'La trésorerie des PME');
    expect(work?.coverTemplateId, unikinId);
  });
}
