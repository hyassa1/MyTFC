/// Opérateurs mobiles de la RDC (pour l'affichage et le mobile money).
enum MobileOperator {
  vodacom('M-Pesa (Vodacom)'),
  orange('Orange Money'),
  airtel('Airtel Money'),
  africell('Afrimoney (Africell)');

  const MobileOperator(this.label);

  final String label;
}

/// Numéro de téléphone mobile congolais, normalisé au format international
/// E.164 (+243 suivi de 9 chiffres).
///
/// Formats acceptés à la saisie : 0812345678, 812345678, +243812345678,
/// 243812345678, 00243812345678, avec espaces, tirets, points ou parenthèses.
class PhoneNumber {
  const PhoneNumber._(this.nationalNumber);

  /// Les 9 chiffres après l'indicatif, par exemple « 812345678 ».
  final String nationalNumber;

  static const countryCode = '243';

  /// Préfixes à deux chiffres connus. La liste fait foi pour l'opérateur
  /// proposé par défaut ; l'utilisateur peut toujours le changer.
  static const Map<String, MobileOperator> _prefixes = {
    '81': MobileOperator.vodacom,
    '82': MobileOperator.vodacom,
    '83': MobileOperator.vodacom,
    '80': MobileOperator.orange,
    '84': MobileOperator.orange,
    '85': MobileOperator.orange,
    '89': MobileOperator.orange,
    '97': MobileOperator.airtel,
    '98': MobileOperator.airtel,
    '99': MobileOperator.airtel,
    '90': MobileOperator.africell,
    '91': MobileOperator.africell,
  };

  /// Renvoie null si la saisie n'est pas un numéro mobile congolais valide.
  static PhoneNumber? tryParse(String input) {
    var digits = input.replaceAll(RegExp(r'[\s\-.()]'), '');
    if (digits.startsWith('+')) {
      digits = digits.substring(1);
    } else if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (!RegExp(r'^\d+$').hasMatch(digits)) return null;

    if (digits.length == 12 && digits.startsWith(countryCode)) {
      digits = digits.substring(3);
    } else if (digits.length == 10 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length != 9) return null;
    if (!(digits.startsWith('8') || digits.startsWith('9'))) return null;
    return PhoneNumber._(digits);
  }

  /// Format envoyé à Supabase Auth : « +243812345678 ».
  String get e164 => '+$countryCode$nationalNumber';

  /// Format lisible : « +243 81 234 5678 ».
  String get display =>
      '+$countryCode ${nationalNumber.substring(0, 2)} ${nationalNumber.substring(2, 5)} ${nationalNumber.substring(5)}';

  /// Opérateur déduit du préfixe, ou null s'il est inconnu.
  MobileOperator? get operator => _prefixes[nationalNumber.substring(0, 2)];

  @override
  bool operator ==(Object other) => other is PhoneNumber && other.nationalNumber == nationalNumber;

  @override
  int get hashCode => nationalNumber.hashCode;

  @override
  String toString() => e164;
}
