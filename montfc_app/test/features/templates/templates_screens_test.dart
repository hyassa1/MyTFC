import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/database/kv_store.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/core/providers.dart';
import 'package:montfc/core/sync/sync_controller.dart';
import 'package:montfc/features/questionnaires/domain/questionnaire.dart';
import 'package:montfc/features/questionnaires/presentation/questionnaire_screens.dart';
import 'package:montfc/features/store/domain/entitlement.dart';
import 'package:montfc/features/store/domain/offer.dart';
import 'package:montfc/features/store/presentation/store_providers.dart';
import 'package:montfc/features/templates/domain/document_template.dart';
import 'package:montfc/features/templates/presentation/templates_screens.dart';
import 'package:montfc/features/works/data/works_providers.dart';
import 'package:montfc/features/works/data/works_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../payment/payment_test_support.dart';

const docId = '00000000-0000-4000-8000-000000000401';
const questId = '00000000-0000-4000-8000-000000000451';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  late LocalDatabase local;
  final doc = jsonDecode(File('test/fixtures/document_template.json').readAsStringSync()) as Map<String, dynamic>;
  final quest = jsonDecode(File('test/fixtures/questionnaire.json').readAsStringSync()) as Map<String, dynamic>;

  setUp(() async => local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<void> pump(WidgetTester tester, Widget home, {required AppFeature unlocked, required String id}) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localDatabaseProvider.overrideWithValue(local),
        worksRepositoryProvider.overrideWithValue(WorksRepository(local)),
        syncControllerProvider.overrideWith(FakeSyncController.new),
        offersProvider.overrideWith((ref) async => const <Offer>[packOffer]),
        entitlementsProvider.overrideWith((ref) async =>
            EntitlementSet([Entitlement(id: 'e', feature: unlocked, resourceId: id, startsAt: DateTime(2026))])),
        documentTemplatesProvider.overrideWith((ref) async => [
              {'id': docId, 'title': 'Mémoire de licence', 'work_type': 'memoire_licence'},
            ]),
        documentBodyProvider.overrideWith((ref, _) async => (
              plan: PlanItem.listFrom(doc['structure']),
              formatting: DocFormatting.fromJson(doc['formatting'] as Map<String, dynamic>),
            )),
        questionnaireTemplatesProvider.overrideWith((ref) async => [
              {'id': questId, 'title': 'Satisfaction', 'domain': 'gestion'},
            ]),
        questionnaireBodyProvider.overrideWith((ref, _) async => QuestionnaireTemplate.fromJson(quest)),
      ],
      child: MaterialApp(home: home),
    ));
    await settle(tester);
  }

  testWidgets('modèle acheté : plan numéroté, adopté pour le travail de l\'étudiant', (tester) async {
    await pump(tester, const TemplateScreen(templateId: docId), unlocked: AppFeature.docTemplate, id: docId);
    expect(find.textContaining('CHAPITRE I : Considérations générales'), findsOneWidget);
    expect(find.text('0.2. : Problématique'), findsOneWidget);

    await tester.tap(find.text('Utiliser ce plan pour mon travail'));
    await settle(tester);
    expect(find.textContaining('C\'est ton plan'), findsOneWidget);
    final work = await tester.runAsync(() => WorksRepository(local).current());
    expect(work?.documentTemplateId, docId);
    expect(work?.plan, isNotEmpty);
  });

  testWidgets('autre modèle que celui acheté : verrouillé', (tester) async {
    await pump(tester, const TemplateScreen(templateId: docId), unlocked: AppFeature.docTemplate, id: 'autre');
    expect(find.text('Contenu à débloquer'), findsOneWidget);
  });

  testWidgets('questionnaire : variables remplies et question retirée, gardées sur le téléphone', (tester) async {
    await pump(tester, const QuestionnaireScreen(templateId: questId), unlocked: AppFeature.questionnaire, id: questId);
    await tester.enterText(find.widgetWithText(TextField, 'Nom de l\'organisation étudiée'), 'la Regideso');
    await settle(tester);
    expect(find.textContaining('Comment jugez-vous l\'accueil reçu à la Regideso ?'), findsOneWidget);

    await tester.tap(find.byTooltip('Retirer').first);
    await settle(tester);
    expect(find.textContaining('9 questions retenues'), findsOneWidget);

    final raw = await tester.runAsync(() => KvStore(local).get(questionnaireDraftKey(questId)));
    final draft = QuestionnaireDraft.decode(raw);
    expect(draft.values['organisation'], 'la Regideso');
    expect(draft.removed, {'q1'});
  });
}
