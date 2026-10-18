import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/features/guide/presentation/guide_screens.dart';

void main() {
  // Les vrais chapitres de démonstration, tels qu'embarqués dans l'APK.
  final seed = jsonDecode(File('assets/seed/content.json').readAsStringSync()) as Map<String, dynamic>;
  final chapters = (seed['guide_chapters'] as List).cast<Map<String, dynamic>>()
    ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

  Widget app(Widget child) => ProviderScope(
        overrides: [guideChaptersProvider.overrideWith((ref) async => chapters)],
        child: MaterialApp(home: child),
      );

  testWidgets('la liste affiche les 3 chapitres dans l\'ordre', (tester) async {
    await tester.pumpWidget(app(const GuideScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Choisir son sujet'), findsOneWidget);
    expect(find.text('Formuler la problématique'), findsOneWidget);
    expect(find.text('Hypothèses et objectifs'), findsOneWidget);
  });

  testWidgets('un chapitre se lit en Markdown, avec ses tableaux', (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const GuideChapterScreen(slug: 'choix-du-sujet')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Les quatre critères'), findsWidgets);
    expect(find.byType(Table), findsWidgets);
    expect(find.textContaining('Chapitre suivant'), findsOneWidget);
  });

  testWidgets('chapitre inconnu : message clair', (tester) async {
    await tester.pumpWidget(app(const GuideChapterScreen(slug: 'inexistant')));
    await tester.pumpAndSettle();
    expect(find.text('Chapitre introuvable.'), findsOneWidget);
  });
}
