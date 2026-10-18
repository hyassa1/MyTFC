import 'entitlement.dart';

/// Offre en vente (table `products` + `product_prices`), prix modifiables
/// depuis l'admin sans mise à jour de l'application.
class Offer {
  const Offer({
    required this.id,
    required this.code,
    required this.name,
    required this.feature,
    required this.isPack,
    required this.requiresResource,
    required this.prices,
    this.description,
    this.durationDays,
    this.playProductId,
    this.position = 0,
  });

  final String id;
  final String code;
  final String name;
  final String? description;
  final AppFeature feature;
  final bool isPack;

  /// Vrai si l'achat porte sur un modèle précis (choisi dans la liste des modèles).
  final bool requiresResource;

  /// null = accès permanent.
  final int? durationDays;
  final String? playProductId;
  final int position;

  /// Prix en unités mineures (×100) par devise : {'CDF': 580000, 'USD': 200}.
  final Map<String, int> prices;

  static const packCode = 'PACK_FINALISTE';

  /// Assemble les offres actives à partir des lignes en cache.
  static List<Offer> fromRows(List<Map<String, dynamic>> products, List<Map<String, dynamic>> priceRows) {
    final prices = <String, Map<String, int>>{};
    for (final p in priceRows) {
      (prices[p['product_id'] as String] ??= {})[p['currency'] as String] = (p['amount_minor'] as num).toInt();
    }
    final offers = [
      for (final p in products)
        if (p['is_active'] != false && prices.containsKey(p['id']))
          Offer(
            id: p['id'] as String,
            code: p['code'] as String,
            name: p['name'] as String,
            description: p['description'] as String?,
            feature: AppFeature.fromCode(p['feature'] as String?) ?? AppFeature.all,
            isPack: p['kind'] == 'pack',
            requiresResource: p['requires_resource'] == true,
            durationDays: (p['duration_days'] as num?)?.toInt(),
            playProductId: p['play_product_id'] as String?,
            position: (p['position'] as num?)?.toInt() ?? 0,
            prices: prices[p['id']]!,
          ),
    ]..sort((a, b) => a.position.compareTo(b.position));
    return offers;
  }

  /// Offre à proposer pour débloquer une fonction (achat à l'unité).
  static Offer? forFeature(List<Offer> offers, AppFeature feature) =>
      offers.where((o) => !o.isPack && o.feature == feature).firstOrNull;

  static Offer? pack(List<Offer> offers) => offers.where((o) => o.isPack).firstOrNull;
}

/// Prix calculé par le serveur (`quote_price`), code promo compris.
class Quote {
  const Quote({
    required this.currency,
    required this.grossMinor,
    required this.discountMinor,
    required this.netMinor,
    this.promoError,
  });

  final String currency;
  final int grossMinor;
  final int discountMinor;
  final int netMinor;

  /// Code d'erreur du code promo (promo_invalid, promo_expired…), ou null.
  final String? promoError;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        currency: j['currency'] as String,
        grossMinor: (j['amount_gross_minor'] as num).toInt(),
        discountMinor: (j['discount_minor'] as num).toInt(),
        netMinor: (j['amount_net_minor'] as num).toInt(),
        promoError: j['promo_error'] as String?,
      );

  /// Message en français pour une erreur de code promo.
  static String promoMessage(String code) => switch (code) {
        'promo_expired' => 'Ce code promo a expiré.',
        'promo_not_started' => 'Ce code promo n\'est pas encore valable.',
        'promo_exhausted' => 'Ce code promo a atteint son nombre maximal d\'utilisations.',
        'promo_not_applicable' => 'Ce code promo ne s\'applique pas à cette offre.',
        _ => 'Code promo invalide.',
      };
}

/// Ligne de l'historique des achats (table `payments`).
class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.productId,
    required this.status,
    required this.currency,
    required this.amountNetMinor,
    required this.createdAt,
    this.channel,
  });

  final String id;
  final String productId;
  final String status;
  final String currency;
  final int amountNetMinor;
  final DateTime createdAt;
  final String? channel;

  factory PurchaseRecord.fromJson(Map<String, dynamic> j) => PurchaseRecord(
        id: j['id'] as String,
        productId: j['product_id'] as String,
        status: j['status'] as String,
        currency: j['currency'] as String,
        amountNetMinor: (j['amount_net_minor'] as num).toInt(),
        createdAt: DateTime.parse(j['created_at'] as String),
        channel: j['channel'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'status': status,
        'currency': currency,
        'amount_net_minor': amountNetMinor,
        'created_at': createdAt.toIso8601String(),
        'channel': channel,
      };

  String get statusLabel => switch (status) {
        'succeeded' => 'Payé',
        'pending' || 'processing' => 'En attente',
        'failed' => 'Échoué',
        'expired' => 'Délai dépassé',
        'cancelled' => 'Annulé',
        _ => status,
      };
}
