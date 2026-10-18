import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/payment.dart';

/// Paiement mobile money via les fonctions serveur (variante directe et web).
///
/// L'application ne parle JAMAIS à l'agrégateur : elle demande au serveur de
/// lancer la transaction (payment-init) puis suit son état (payment-status).
abstract interface class MobileMoneyGateway {
  Future<PaymentAttempt> start(MobileMoneyRequest request);
  Future<PaymentAttempt> status(String paymentId);
}

class SupabaseMobileMoneyGateway implements MobileMoneyGateway {
  SupabaseMobileMoneyGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<PaymentAttempt> start(MobileMoneyRequest request) =>
      _call('payment-init', request.toJson());

  @override
  Future<PaymentAttempt> status(String paymentId) => _call('payment-status', {'payment_id': paymentId});

  Future<PaymentAttempt> _call(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(fn, body: body).timeout(const Duration(seconds: 30));
      final data = Map<String, dynamic>.from(res.data as Map);
      return PaymentAttempt.fromJson(Map<String, dynamic>.from(data['payment'] as Map));
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] as String? : null;
      throw PaymentFailure(PaymentFailure.messageFor(code));
    } on SocketException {
      throw PaymentFailure.network;
    } on TimeoutException {
      throw PaymentFailure.network;
    }
  }
}
