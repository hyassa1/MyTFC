import 'package:intl/intl.dart';

/// Formatage des montants stockés en unités mineures (×100), comme en base.
///
/// CDF : « 5 800 FC » (sans décimales, usage courant à Kinshasa).
/// USD : « 2,00 $ ».
abstract final class Money {
  static final NumberFormat _cdf = NumberFormat.decimalPattern('fr');
  static final NumberFormat _usd = NumberFormat('#,##0.00', 'fr');

  static String format(int amountMinor, String currency) {
    final value = amountMinor / 100;
    return switch (currency) {
      'CDF' => '${_cdf.format(value.round())} FC',
      'USD' => '${_usd.format(value)} \$',
      _ => '${_usd.format(value)} $currency',
    };
  }
}
