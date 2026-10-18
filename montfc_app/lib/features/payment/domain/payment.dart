import '../../auth/domain/phone_number.dart';
import '../../store/domain/offer.dart';

/// État d'un paiement (miroir de l'enum SQL `public.payment_status`).
enum PaymentStatus {
  pending,
  processing,
  succeeded,
  failed,
  expired,
  cancelled;

  static PaymentStatus fromCode(String code) =>
      values.where((v) => v.name == code).firstOrNull ?? PaymentStatus.pending;

  /// Plus rien ne bougera (hors rattrapage d'un succès tardif côté serveur).
  bool get isFinal => this == succeeded || this == failed || this == cancelled;

  bool get isWaiting => this == pending || this == processing;
}

/// Paiement tel que renvoyé par les fonctions serveur.
class PaymentAttempt {
  const PaymentAttempt({
    required this.id,
    required this.status,
    required this.currency,
    required this.amountNetMinor,
    this.failureReason,
    this.expiresAt,
  });

  final String id;
  final PaymentStatus status;
  final String currency;
  final int amountNetMinor;
  final String? failureReason;
  final DateTime? expiresAt;

  factory PaymentAttempt.fromJson(Map<String, dynamic> j) => PaymentAttempt(
        id: j['id'] as String,
        status: PaymentStatus.fromCode(j['status'] as String),
        currency: j['currency'] as String,
        amountNetMinor: (j['amount_net_minor'] as num).toInt(),
        failureReason: j['failure_reason'] as String?,
        expiresAt: j['expires_at'] == null ? null : DateTime.parse(j['expires_at'] as String),
      );

  /// Message d'échec compréhensible par l'étudiant.
  String get failureMessage => PaymentFailure.messageFor(failureReason);
}

/// Demande d'achat mobile money.
class MobileMoneyRequest {
  const MobileMoneyRequest({
    required this.offer,
    required this.currency,
    required this.phone,
    required this.idempotencyKey,
    this.operator,
    this.resourceId,
    this.promoCode,
    this.fromWeb = false,
  });

  final Offer offer;
  final String currency;
  final PhoneNumber phone;
  final MobileOperator? operator;
  final String? resourceId;
  final String? promoCode;

  /// Même clé pour un nouvel essai du même achat : jamais de double débit.
  final String idempotencyKey;
  final bool fromWeb;

  Map<String, dynamic> toJson() => {
        'product_id': offer.id,
        'resource_id': resourceId,
        'currency': currency,
        'msisdn': phone.e164,
        'operator': operator == null ? null : _operatorCode(operator!),
        'promo_code': promoCode,
        'idempotency_key': idempotencyKey,
        'channel': fromWeb ? 'mobile_money_web' : 'mobile_money_app',
      };

  static String _operatorCode(MobileOperator o) => switch (o) {
        MobileOperator.vodacom => 'vodacom',
        MobileOperator.orange => 'orange',
        MobileOperator.airtel => 'airtel',
        MobileOperator.africell => 'afrimoney',
      };
}

/// Erreur de paiement présentée à l'étudiant.
class PaymentFailure implements Exception {
  const PaymentFailure(this.message);

  final String message;

  static const network = PaymentFailure(
      'Connexion internet indisponible. Ton paiement n\'a pas été lancé ; réessaie quand tu seras connecté.');

  /// Traduit un code d'erreur serveur ou agrégateur.
  static String messageFor(String? code) => switch (code) {
        null => 'Le paiement n\'a pas abouti.',
        'insufficient_funds' => 'Solde insuffisant sur ton compte mobile money.',
        'timeout' => 'Tu n\'as pas confirmé le paiement à temps. Aucun montant n\'a été débité.',
        'invalid_msisdn' => 'Numéro mobile money invalide.',
        'resource_required' => 'Choisis d\'abord le modèle à acheter.',
        'promo_invalid' || 'promo_expired' || 'promo_not_started' || 'promo_exhausted' || 'promo_not_applicable' =>
          Quote.promoMessage(code),
        'product_not_found' || 'price_not_found' => 'Cette offre n\'est plus disponible.',
        'not_authenticated' => 'Ta session a expiré. Reconnecte-toi.',
        _ when code.contains('unreachable') =>
          'Le service de paiement ne répond pas. Aucun montant n\'a été débité ; réessaie dans un instant.',
        _ => 'Le paiement n\'a pas abouti. Aucun montant n\'a été débité si tu n\'as pas saisi ton code PIN.',
      };

  @override
  String toString() => message;
}
