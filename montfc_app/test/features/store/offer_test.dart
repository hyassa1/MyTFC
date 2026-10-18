import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/features/auth/domain/phone_number.dart';
import 'package:montfc/features/payment/domain/payment.dart';
import 'package:montfc/features/store/domain/entitlement.dart';
import 'package:montfc/features/store/domain/offer.dart';
import 'package:montfc/features/store/presentation/store_providers.dart';

void main() {
  final products = [
    {'id': 'p1', 'code': 'COVER_PAGE', 'name': 'Page de garde', 'kind': 'unit', 'feature': 'cover_page',
      'position': 1, 'play_product_id': 'montfc_cover_page'},
    {'id': 'p4', 'code': 'PACK_FINALISTE', 'name': 'Pack', 'kind': 'pack', 'feature': 'all', 'position': 0,
      'duration_days': 365},
    {'id': 'p9', 'code': 'OLD', 'name': 'Ancienne', 'kind': 'unit', 'feature': 'export', 'is_active': false},
    {'id': 'p8', 'code': 'NOPRICE', 'name': 'Sans prix', 'kind': 'unit', 'feature': 'export'},
  ];
  final prices = [
    {'product_id': 'p1', 'currency': 'CDF', 'amount_minor': 580000},
    {'product_id': 'p1', 'currency': 'USD', 'amount_minor': 200},
    {'product_id': 'p4', 'currency': 'USD', 'amount_minor': 1000},
    {'product_id': 'p9', 'currency': 'USD', 'amount_minor': 100},
  ];

  test('offres : inactives et sans prix écartées, triées, prix par devise', () {
    final offers = Offer.fromRows(products, prices);
    expect(offers.map((o) => o.code), ['PACK_FINALISTE', 'COVER_PAGE']);
    expect(offers[1].prices, {'CDF': 580000, 'USD': 200});
    expect(Offer.pack(offers)!.durationDays, 365);
    expect(Offer.forFeature(offers, AppFeature.coverPage)!.playProductId, 'montfc_cover_page');
    expect(Offer.forFeature(offers, AppFeature.export), isNull);
  });

  test('devis serveur avec code promo et messages d\'erreur', () {
    final q = Quote.fromJson({
      'currency': 'CDF', 'amount_gross_minor': 2900000, 'discount_minor': 290000,
      'amount_net_minor': 2610000, 'promo_error': null,
    });
    expect(q.netMinor, q.grossMinor - q.discountMinor);
    expect(Quote.promoMessage('promo_expired'), contains('expiré'));
    expect(Quote.promoMessage('n_importe_quoi'), 'Code promo invalide.');
  });

  test('demande mobile money envoyée au serveur (Africell = afrimoney)', () {
    final offer = Offer.fromRows(products, prices).first;
    final json = MobileMoneyRequest(
      offer: offer,
      currency: 'USD',
      phone: PhoneNumber.tryParse('0901234567')!,
      operator: MobileOperator.africell,
      promoCode: 'DEMO10',
      idempotencyKey: 'k',
    ).toJson();
    expect(json['product_id'], 'p4');
    expect(json['msisdn'], '+243901234567');
    expect(json['operator'], 'afrimoney');
    expect(json['channel'], 'mobile_money_app');
  });

  group('moyens de paiement par variante', () {
    final setting = {
      'store': {'android': ['google_play'], 'ios': ['app_store']},
      'direct': {'android': ['mobile_money']},
    };

    test('Play Store : uniquement Google Play (règles de Google)', () {
      expect(paymentMethodsFor(setting, flavor: 'store', platform: 'android'), [PaymentMethod.googlePlay]);
    });

    test('APK direct : mobile money', () {
      expect(paymentMethodsFor(setting, flavor: 'direct', platform: 'android'), [PaymentMethod.mobileMoney]);
    });

    test('réglage absent : valeurs sûres par défaut', () {
      expect(paymentMethodsFor(null, flavor: 'store', platform: 'android'), [PaymentMethod.googlePlay]);
      expect(paymentMethodsFor(null, flavor: 'direct', platform: 'android'), [PaymentMethod.mobileMoney]);
    });

    test('ouverture future de la facturation alternative : sans republier l\'app', () {
      final opened = {
        'store': {'android': ['google_play', 'mobile_money']},
      };
      expect(paymentMethodsFor(opened, flavor: 'store', platform: 'android'),
          [PaymentMethod.googlePlay, PaymentMethod.mobileMoney]);
    });

    test('un moyen d\'une autre plateforme est ignoré', () {
      expect(paymentMethodsFor({'store': {'android': ['app_store']}}, flavor: 'store', platform: 'android'),
          isEmpty);
    });
  });

  test('libellés de l\'historique des achats', () {
    PurchaseRecord r(String s) => PurchaseRecord(
        id: 'x', productId: 'p1', status: s, currency: 'CDF', amountNetMinor: 1, createdAt: DateTime(2026));
    expect(r('succeeded').statusLabel, 'Payé');
    expect(r('processing').statusLabel, 'En attente');
    expect(r('expired').statusLabel, 'Délai dépassé');
  });
}
