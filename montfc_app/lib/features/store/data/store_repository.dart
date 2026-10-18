import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/content/content_kinds.dart';
import '../../../core/content/content_store.dart';
import '../../../core/database/kv_store.dart';
import '../domain/offer.dart';

/// Catalogue, prix et historique des achats.
///
/// Le catalogue vient du cache local (disponible hors ligne) ; le calcul du
/// prix avec code promo et l'historique demandent une connexion (l'historique
/// est gardé en cache pour l'affichage hors ligne).
class StoreRepository {
  StoreRepository({required this._content, required this._kv, this._client});

  static const historyCacheKey = 'store.history';

  final ContentStore _content;
  final KvStore _kv;
  final SupabaseClient? _client;

  Future<List<Offer>> offers() async => Offer.fromRows(
        await _content.list(ContentKind.product),
        await _content.list(ContentKind.productPrice),
      );

  /// Prix calculé par le serveur. Hors ligne : prix catalogue, sans promo.
  Future<Quote> quote(Offer offer, String currency, {String? promoCode}) async {
    final client = _client;
    final fallback = Quote(
      currency: currency,
      grossMinor: offer.prices[currency] ?? 0,
      discountMinor: 0,
      netMinor: offer.prices[currency] ?? 0,
    );
    if (client == null) return fallback;
    try {
      final res = await client.rpc<dynamic>('quote_price', params: {
        'p_product_id': offer.id,
        'p_currency': currency,
        'p_promo_code': (promoCode?.trim().isEmpty ?? true) ? null : promoCode!.trim(),
      });
      return Quote.fromJson(Map<String, dynamic>.from(res as Map));
    } on SocketException {
      return fallback;
    } on PostgrestException {
      return fallback;
    }
  }

  /// Historique des achats de l'utilisateur (RLS : uniquement les siens).
  Future<List<PurchaseRecord>> history() async {
    final client = _client;
    if (client != null) {
      try {
        final rows = await client
            .from('payments')
            .select('id, product_id, status, currency, amount_net_minor, created_at, channel')
            .neq('channel', 'admin')
            .order('created_at', ascending: false)
            .limit(50);
        final list = rows.map(PurchaseRecord.fromJson).toList();
        await _kv.set(historyCacheKey, jsonEncode(list.map((r) => r.toJson()).toList()));
        return list;
      } on SocketException {
        // Hors ligne : cache ci-dessous.
      } on PostgrestException {
        // Idem.
      }
    }
    final cached = await _kv.get(historyCacheKey);
    if (cached == null) return const [];
    return (jsonDecode(cached) as List)
        .map((e) => PurchaseRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
