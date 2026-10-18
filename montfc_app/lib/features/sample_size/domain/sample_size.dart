import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Une étape du calcul, affichée à l'étudiant pour qu'il comprenne (et
/// puisse reproduire dans son travail) chaque opération.
class CalcStep {
  const CalcStep({required this.title, required this.formula, this.note});

  final String title;

  /// Opération avec les valeurs, par exemple « 1 000 × 0,0025 = 2,5 ».
  final String formula;

  /// Explication complémentaire facultative.
  final String? note;
}

/// Résultat d'un calcul de taille d'échantillon.
class SampleSizeResult {
  const SampleSizeResult({
    required this.sampleSize,
    required this.exactValue,
    required this.steps,
    this.warning,
  });

  /// Taille retenue, arrondie à l'unité supérieure.
  final int sampleSize;

  /// Valeur avant arrondi.
  final double exactValue;

  final List<CalcStep> steps;

  /// Mise en garde éventuelle (ex. échantillon presque égal à la population).
  final String? warning;
}

/// Erreur de saisie, avec un message en français.
class SampleSizeInputError implements Exception {
  const SampleSizeInputError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Niveaux de confiance usuels et leur valeur Z (loi normale, bilatéral).
enum ConfidenceLevel {
  p90(90, 1.645),
  p95(95, 1.96),
  p99(99, 2.576);

  const ConfidenceLevel(this.percent, this.z);

  final int percent;
  final double z;
}

/// Calculs de taille d'échantillon (fonctions pures, testées).
abstract final class SampleSize {
  static final NumberFormat _num = NumberFormat('#,##0.####', 'fr');
  static final NumberFormat _int = NumberFormat('#,##0', 'fr');

  /// Formatage français : virgule décimale, espace des milliers.
  static String fmt(num value) => value == value.roundToDouble() && value.abs() < 1e15
      ? _int.format(value)
      : _num.format(value);

  /// Arrondi à l'unité supérieure, sans être piégé par les imprécisions des
  /// nombres à virgule (ex. 100,0000000001 doit donner 100).
  static int ceilSafe(double x) => (x - 1e-9).ceil();

  /// Formule de Slovin : n = N / (1 + N·e²).
  ///
  /// [population] : taille de la population N (entier ≥ 1).
  /// [marginOfError] : marge d'erreur e, en proportion (0,05 pour 5 %).
  static SampleSizeResult slovin({required int population, required double marginOfError}) {
    _checkPopulation(population);
    _checkMargin(marginOfError);

    final n = population.toDouble();
    final e2 = marginOfError * marginOfError;
    final ne2 = n * e2;
    final denominator = 1 + ne2;
    final exact = n / denominator;
    final result = math.max(1, ceilSafe(exact));

    return SampleSizeResult(
      sampleSize: result,
      exactValue: exact,
      steps: [
        CalcStep(
          title: 'Données',
          formula: 'N = ${fmt(n)} ; e = ${fmt(marginOfError)} (soit ${fmt(marginOfError * 100)} %)',
          note: 'N est la taille de la population étudiée, e la marge d\'erreur acceptée.',
        ),
        CalcStep(title: 'Marge d\'erreur au carré', formula: 'e² = ${fmt(marginOfError)}² = ${fmt(e2)}'),
        CalcStep(title: 'Produit N × e²', formula: '${fmt(n)} × ${fmt(e2)} = ${fmt(ne2)}'),
        CalcStep(title: 'Dénominateur', formula: '1 + ${fmt(ne2)} = ${fmt(denominator)}'),
        CalcStep(title: 'Division', formula: 'n = ${fmt(n)} ÷ ${fmt(denominator)} = ${fmt(_round2(exact))}'),
        CalcStep(
          title: 'Arrondi à l\'unité supérieure',
          formula: 'n = $result',
          note: 'On arrondit toujours vers le haut : arrondir vers le bas ferait dépasser la marge d\'erreur choisie.',
        ),
      ],
    );
  }

  /// Formule de Cochran : n₀ = Z² · p · (1 − p) / e², avec correction pour
  /// population finie si [population] est connue : n = n₀ / (1 + (n₀ − 1) / N).
  ///
  /// [proportion] : proportion attendue p (0,5 si elle est inconnue, ce qui
  /// donne la taille la plus prudente).
  static SampleSizeResult cochran({
    required ConfidenceLevel confidence,
    required double marginOfError,
    double proportion = 0.5,
    int? population,
  }) {
    _checkMargin(marginOfError);
    if (proportion <= 0 || proportion >= 1) {
      throw const SampleSizeInputError('La proportion p doit être comprise entre 0 et 1 (exclus), par exemple 0,5.');
    }
    if (population != null) _checkPopulation(population);

    final z = confidence.z;
    final z2 = z * z;
    final pq = proportion * (1 - proportion);
    final e2 = marginOfError * marginOfError;
    final n0 = z2 * pq / e2;

    final steps = <CalcStep>[
      CalcStep(
        title: 'Données',
        formula: 'confiance = ${confidence.percent} % ; e = ${fmt(marginOfError)} ; p = ${fmt(proportion)}'
            '${population != null ? ' ; N = ${fmt(population)}' : ''}',
        note: proportion == 0.5
            ? 'p = 0,5 est utilisé quand la proportion est inconnue : c\'est la valeur qui donne l\'échantillon le plus grand, donc le plus prudent.'
            : null,
      ),
      CalcStep(
        title: 'Valeur Z',
        formula: 'confiance ${confidence.percent} % → Z = ${fmt(z)}',
        note: 'Valeur lue dans la table de la loi normale centrée réduite.',
      ),
      CalcStep(title: 'Z au carré', formula: 'Z² = ${fmt(z)}² = ${fmt(z2)}'),
      CalcStep(title: 'Variabilité p × (1 − p)', formula: '${fmt(proportion)} × ${fmt(1 - proportion)} = ${fmt(pq)}'),
      CalcStep(title: 'Marge d\'erreur au carré', formula: 'e² = ${fmt(marginOfError)}² = ${fmt(e2)}'),
      CalcStep(
        title: 'Taille pour une grande population',
        formula: 'n₀ = ${fmt(z2)} × ${fmt(pq)} ÷ ${fmt(e2)} = ${fmt(_round2(n0))}',
      ),
    ];

    var exact = n0;
    String? warning;
    if (population != null) {
      exact = n0 / (1 + (n0 - 1) / population);
      steps.add(CalcStep(
        title: 'Correction pour population finie',
        formula: 'n = ${fmt(_round2(n0))} ÷ (1 + (${fmt(_round2(n0))} − 1) ÷ ${fmt(population)}) = ${fmt(_round2(exact))}',
        note: 'Quand la population est connue et limitée, on peut interroger moins de personnes.',
      ));
    }
    final result = math.max(1, ceilSafe(exact));
    steps.add(CalcStep(title: 'Arrondi à l\'unité supérieure', formula: 'n = $result'));

    if (population != null && result >= population * 0.8) {
      warning = 'L\'échantillon représente presque toute la population : envisage d\'interroger tout le monde (recensement).';
    }
    return SampleSizeResult(sampleSize: result, exactValue: exact, steps: steps, warning: warning);
  }

  /// Lit une marge d'erreur saisie en pourcentage (« 5 », « 5 % », « 2,5 »).
  static double parsePercent(String input) {
    final cleaned = input.replaceAll('%', '').replaceAll(' ', '').replaceAll(',', '.');
    final value = double.tryParse(cleaned);
    if (value == null) throw const SampleSizeInputError('Saisis un pourcentage, par exemple 5.');
    return value / 100;
  }

  /// Lit un entier saisi avec ou sans séparateurs (« 1 000 », « 1000 »).
  static int parseInt(String input) {
    final value = int.tryParse(input.replaceAll(RegExp(r'[\s.  ]'), ''));
    if (value == null) throw const SampleSizeInputError('Saisis un nombre entier, par exemple 1000.');
    return value;
  }

  static void _checkPopulation(int n) {
    if (n < 1) throw const SampleSizeInputError('La population N doit être un entier supérieur ou égal à 1.');
  }

  static void _checkMargin(double e) {
    if (e <= 0 || e >= 0.5) {
      throw const SampleSizeInputError('La marge d\'erreur doit être comprise entre 0 et 50 % (souvent 5 %).');
    }
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}
