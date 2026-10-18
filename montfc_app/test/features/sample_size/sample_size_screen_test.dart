import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:montfc/features/sample_size/presentation/sample_size_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  /// Écran haut, pour que le résultat (en bas de la liste) soit construit.
  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('Slovin : saisie, calcul et étapes affichées', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: SampleSizeScreen()));
    await tester.enterText(find.widgetWithText(TextField, 'Taille de la population (N)'), '1000');
    await tester.tap(find.text('Calculer').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('286 personnes'), findsOneWidget);
    expect(find.text('Le calcul, étape par étape'), findsOneWidget);
  });

  testWidgets('saisie invalide : message d\'erreur au lieu d\'un résultat', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: SampleSizeScreen()));
    await tester.enterText(find.widgetWithText(TextField, 'Taille de la population (N)'), 'abc');
    await tester.tap(find.text('Calculer').hitTestable());
    await tester.pump();
    expect(find.textContaining('nombre entier'), findsOneWidget);
    expect(find.textContaining('personnes'), findsNothing);
  });

  testWidgets('Cochran : 95 %, 5 %, population inconnue → 385', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: SampleSizeScreen()));
    await tester.tap(find.text('Cochran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calculer').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('385 personnes'), findsOneWidget);
  });
}
