import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/core/sync/sync_controller.dart';
import 'package:montfc/features/bibliography/data/bibliography_repository.dart';
import 'package:montfc/features/bibliography/presentation/bibliography_providers.dart';
import 'package:montfc/features/bibliography/presentation/bibliography_screen.dart';
import 'package:montfc/features/bibliography/presentation/source_form_screen.dart';
import 'package:montfc/features/store/domain/entitlement.dart';
import 'package:montfc/features/store/domain/offer.dart';
import 'package:montfc/features/store/presentation/store_providers.dart';
import 'package:montfc/features/works/data/works_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../payment/payment_test_support.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  late LocalDatabase local;

  setUpAll(() => initializeDateFormatting('fr'));
  setUp(() async => local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<void> pump(WidgetTester tester, {required bool pack}) async {
    tester.view.physicalSize = const Size(1080, 4400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const BibliographyScreen()),
      GoRoute(path: '/bibliographie/ajouter', builder: (_, _) => const SourceFormScreen()),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bibliographyRepositoryProvider.overrideWithValue(BibliographyRepository(local)),
        syncControllerProvider.overrideWith(FakeSyncController.new),
        currentWorkProvider.overrideWith((ref) async => null),
        offersProvider.overrideWith((ref) async => const <Offer>[packOffer]),
        entitlementsProvider.overrideWith((ref) async => pack
            ? EntitlementSet([Entitlement(id: 'e', feature: AppFeature.all, startsAt: DateTime(2026),
                expiresAt: DateTime.now().add(const Duration(days: 30)))])
            : EntitlementSet.empty),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle(tester);
  }

  testWidgets('réservée au Pack Finaliste', (tester) async {
    await pump(tester, pack: false);
    expect(find.text('Contenu à débloquer'), findsOneWidget);
    expect(find.text('Ajouter une source'), findsNothing);
  });

  testWidgets('ajout d\'un ouvrage : aperçu APA en direct, puis rangé dans la liste', (tester) async {
    await pump(tester, pack: true);
    await tester.tap(find.text('Ajouter une source'));
    await settle(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Mbuyi');
    await tester.enterText(find.widgetWithText(TextField, 'Prénom(s)'), 'Jean-Pierre');
    await tester.enterText(find.widgetWithText(TextField, 'Titre'), 'La gestion financière');
    await tester.enterText(find.widgetWithText(TextField, 'Année (vide si sans date)'), '2015');
    await tester.pump();
    expect(find.textContaining('Mbuyi, J.-P. (2015). La gestion financière.', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    expect(find.text('Indique l\'éditeur.'), findsOneWidget, reason: 'éditeur obligatoire pour un ouvrage');

    await tester.enterText(find.widgetWithText(TextField, 'Éditeur'), 'PUK');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    expect(find.text('Bibliographie'), findsOneWidget);
    expect(find.textContaining('Mbuyi, J.-P. (2015). La gestion financière. PUK.', findRichText: true),
        findsOneWidget);
    expect(await tester.runAsync(() => BibliographyRepository(local).all()), hasLength(1));
  });
}
