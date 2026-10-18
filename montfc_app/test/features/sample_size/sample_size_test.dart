import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:montfc/features/sample_size/domain/sample_size.dart';

String norm(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('Slovin', () {
    test('exemple classique : N = 1 000, e = 5 % → 286', () {
      final r = SampleSize.slovin(population: 1000, marginOfError: 0.05);
      expect(r.exactValue, closeTo(285.714, 0.001));
      expect(r.sampleSize, 286);
    });

    test('étapes expliquées avec les valeurs intermédiaires', () {
      final r = SampleSize.slovin(population: 1000, marginOfError: 0.05);
      final formulas = r.steps.map((s) => norm(s.formula)).toList();
      expect(formulas, contains('e² = 0,05² = 0,0025'));
      expect(formulas, contains('1 000 × 0,0025 = 2,5'));
      expect(formulas, contains('1 + 2,5 = 3,5'));
      expect(formulas, contains('n = 1 000 ÷ 3,5 = 285,71'));
      expect(formulas.last, 'n = 286');
    });

    test('autres valeurs de référence', () {
      expect(SampleSize.slovin(population: 500, marginOfError: 0.05).sampleSize, 223); // 222,22
      expect(SampleSize.slovin(population: 10000, marginOfError: 0.05).sampleSize, 385); // 384,61
      expect(SampleSize.slovin(population: 200, marginOfError: 0.1).sampleSize, 67); // 66,67
      expect(SampleSize.slovin(population: 100, marginOfError: 0.05).sampleSize, 80); // 80 exact
    });

    test('un résultat entier n\'est pas arrondi au-dessus par erreur d\'arrondi', () {
      // 100 / (1 + 100 × 0,0025) = 80 exactement.
      expect(SampleSize.ceilSafe(80.0000000001), 80);
      expect(SampleSize.ceilSafe(80.01), 81);
    });

    test('population minuscule : au moins une personne', () {
      expect(SampleSize.slovin(population: 1, marginOfError: 0.05).sampleSize, 1);
    });

    test('saisies invalides refusées avec un message', () {
      expect(() => SampleSize.slovin(population: 0, marginOfError: 0.05), throwsA(isA<SampleSizeInputError>()));
      expect(() => SampleSize.slovin(population: 100, marginOfError: 0), throwsA(isA<SampleSizeInputError>()));
      expect(() => SampleSize.slovin(population: 100, marginOfError: 0.6), throwsA(isA<SampleSizeInputError>()));
    });
  });

  group('Cochran', () {
    test('95 %, e = 5 %, p = 0,5, population inconnue → 385', () {
      final r = SampleSize.cochran(confidence: ConfidenceLevel.p95, marginOfError: 0.05);
      expect(r.exactValue, closeTo(384.16, 0.0001));
      expect(r.sampleSize, 385);
      expect(r.steps.map((s) => s.formula), contains('Z² = 1,96² = 3,8416'));
      expect(r.steps.map((s) => s.formula), contains('n₀ = 3,8416 × 0,25 ÷ 0,0025 = 384,16'));
    });

    test('avec correction pour population finie (N = 1 000) → 278', () {
      final r = SampleSize.cochran(confidence: ConfidenceLevel.p95, marginOfError: 0.05, population: 1000);
      expect(r.exactValue, closeTo(277.74, 0.01));
      expect(r.sampleSize, 278);
      expect(r.steps.any((s) => s.title.contains('population finie')), isTrue);
    });

    test('autres niveaux de confiance', () {
      // 90 % : 1,645² × 0,25 / 0,0025 = 270,6
      expect(SampleSize.cochran(confidence: ConfidenceLevel.p90, marginOfError: 0.05).sampleSize, 271);
      // 99 % : 2,576² × 0,25 / 0,0025 = 663,58
      expect(SampleSize.cochran(confidence: ConfidenceLevel.p99, marginOfError: 0.05).sampleSize, 664);
    });

    test('une proportion attendue de 0,2 réduit l\'échantillon', () {
      // 3,8416 × 0,16 / 0,0025 = 245,86
      expect(SampleSize.cochran(confidence: ConfidenceLevel.p95, marginOfError: 0.05, proportion: 0.2).sampleSize,
          246);
    });

    test('petite population : avertissement de recensement', () {
      final r = SampleSize.cochran(confidence: ConfidenceLevel.p95, marginOfError: 0.05, population: 50);
      expect(r.sampleSize, 45); // 384,16 / (1 + 383,16 / 50) = 44,34
      expect(r.warning, isNotNull);
    });

    test('proportion invalide refusée', () {
      expect(() => SampleSize.cochran(confidence: ConfidenceLevel.p95, marginOfError: 0.05, proportion: 1),
          throwsA(isA<SampleSizeInputError>()));
    });
  });

  group('Saisie', () {
    test('pourcentages', () {
      expect(SampleSize.parsePercent('5'), closeTo(0.05, 1e-12));
      expect(SampleSize.parsePercent('2,5 %'), closeTo(0.025, 1e-12));
      expect(() => SampleSize.parsePercent('abc'), throwsA(isA<SampleSizeInputError>()));
    });

    test('entiers avec séparateurs', () {
      expect(SampleSize.parseInt('1 000'), 1000);
      expect(SampleSize.parseInt('12.500'), 12500);
      expect(() => SampleSize.parseInt('12,5'), throwsA(isA<SampleSizeInputError>()));
    });
  });
}
