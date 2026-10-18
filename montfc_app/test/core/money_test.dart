import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:montfc/core/utils/money.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  test('francs congolais sans décimales', () {
    expect(Money.format(580000, 'CDF').replaceAll(' ', ' ').replaceAll(' ', ' '), '5 800 FC');
  });

  test('dollars avec deux décimales et virgule', () {
    expect(Money.format(200, 'USD'), '2,00 \$');
    expect(Money.format(1050, 'USD'), '10,50 \$');
  });
}
