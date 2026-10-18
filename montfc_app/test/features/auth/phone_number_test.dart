import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/features/auth/domain/phone_number.dart';

void main() {
  group('PhoneNumber.tryParse', () {
    test('accepte les formats courants et les normalise en +243', () {
      for (final input in [
        '0812345678',
        '812345678',
        '+243812345678',
        '243812345678',
        '00243812345678',
        '081 234 56 78',
        '+243 (81) 234-56.78',
      ]) {
        expect(PhoneNumber.tryParse(input)?.e164, '+243812345678', reason: input);
      }
    });

    test('refuse les numéros invalides', () {
      for (final input in ['', '12345', '0112345678', '+33612345678', '08123456789', '08a2345678', '243712345678']) {
        expect(PhoneNumber.tryParse(input), isNull, reason: input);
      }
    });

    test('déduit l\'opérateur du préfixe', () {
      expect(PhoneNumber.tryParse('0812345678')!.operator, MobileOperator.vodacom);
      expect(PhoneNumber.tryParse('0842345678')!.operator, MobileOperator.orange);
      expect(PhoneNumber.tryParse('0892345678')!.operator, MobileOperator.orange);
      expect(PhoneNumber.tryParse('0992345678')!.operator, MobileOperator.airtel);
      expect(PhoneNumber.tryParse('0902345678')!.operator, MobileOperator.africell);
      expect(PhoneNumber.tryParse('0862345678')!.operator, isNull);
    });

    test('affichage lisible', () {
      expect(PhoneNumber.tryParse('0812345678')!.display, '+243 81 234 5678');
    });
  });
}
