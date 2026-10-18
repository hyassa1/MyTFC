import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/security/secure_screen.dart';
import 'package:montfc/features/store/domain/entitlement.dart';
import 'package:montfc/features/store/domain/offer.dart';
import 'package:montfc/features/store/presentation/paid_feature_gate.dart';
import 'package:montfc/features/store/presentation/store_providers.dart';

import '../payment/payment_test_support.dart';

void main() {
  Future<void> pump(WidgetTester tester, EntitlementSet rights) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        entitlementsProvider.overrideWith((ref) async => rights),
        offersProvider.overrideWith((ref) async => const <Offer>[packOffer]),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: PaidFeatureGate(feature: AppFeature.coverPage, child: Text('Aperçu de la page de garde')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sans droit : invitation à débloquer, contenu caché', (tester) async {
    await pump(tester, EntitlementSet.empty);
    expect(find.text('Contenu à débloquer'), findsOneWidget);
    expect(find.textContaining('Pack Finaliste'), findsOneWidget);
    expect(find.text('Aperçu de la page de garde'), findsNothing);
  });

  testWidgets('avec le pack : contenu affiché, captures d\'écran bloquées', (tester) async {
    await pump(tester, EntitlementSet([
      Entitlement(
        id: 'e1',
        feature: AppFeature.all,
        startsAt: DateTime.now().subtract(const Duration(days: 1)),
        expiresAt: DateTime.now().add(const Duration(days: 300)),
      ),
    ]));
    expect(find.text('Aperçu de la page de garde'), findsOneWidget);
    expect(find.byType(SecureScreen), findsOneWidget);
    expect(SecureScreen.activeCount, 1);
  });
}
