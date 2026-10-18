import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/features/questionnaires/domain/questionnaire.dart';
import 'package:montfc/features/templates/domain/document_template.dart';

void main() {
  final doc = jsonDecode(File('test/fixtures/document_template.json').readAsStringSync()) as Map<String, dynamic>;
  final plan = PlanItem.listFrom(doc['structure']);
  final formatting = DocFormatting.fromJson(doc['formatting'] as Map<String, dynamic>);

  group('modèle de mémoire', () {
    test('lecture : pages liminaires, corps, annexes ; sous-parties au niveau suivant', () {
      expect(plan.first.kind, SectionKind.preliminary);
      expect(plan.first.required, isFalse);
      final intro = plan.firstWhere((i) => i.id == 'introduction');
      expect(intro.numbered, isFalse);
      expect(intro.children.first.level, 2);
      expect(intro.children.first.required, isTrue, reason: 'sous-partie obligatoire par défaut');
      expect(intro.children.firstWhere((c) => c.id == 'intro-difficultes').required, isFalse);
    });

    test('numérotation : chapitres en chiffres romains, sections qui repartent à 1', () {
      final labels = PlanNumbering.labels(plan, formatting);
      expect(labels['introduction'], isNull, reason: 'introduction non numérotée');
      expect(labels['chap1'], 'CHAPITRE I');
      expect(labels['chap3'], 'CHAPITRE III');
      expect(labels['chap1-s2'], 'Section 2.');
      expect(labels['chap2-s1'], 'Section 1.');
      expect(labels['intro-etat'], '0.1.', reason: 'usage : 0.1, 0.2… dans l\'introduction');
      expect(labels['intro-subdivision'], '0.9.');
      expect(labels['bibliographie'], isNull);
    });

    test('aucun texte rédigé : seulement des titres et des consignes', () {
      void check(List<PlanItem> items) {
        for (final i in items) {
          expect(i.toJson().keys.toSet().difference({'id', 'title', 'kind', 'heading_level', 'numbered',
              'page_break_before', 'required', 'guidance', 'children'}), isEmpty);
          check(i.children);
        }
      }

      check(plan);
    });

    test('normes de mise en forme lisibles', () {
      expect(formatting.lineSpacing, 1.5);
      expect(formatting.marginsCm.left, 3);
      final summary = formatting.summary();
      expect(summary.first, 'Police : Times New Roman, taille 12');
      expect(summary, contains('Interligne : 1,5'));
      expect(summary.any((l) => l.contains('CHAPITRE I, en majuscules, gras')), isTrue);
    });
  });

  group('plan de l\'étudiant', () {
    test('renommer, ajouter, déplacer, retirer (les parties obligatoires restent)', () {
      var p = PlanEdit.rename(plan, 'chap2', 'Présentation de la Rawbank');
      p = PlanEdit.addChild(p, 'chap1', 'Revue empirique', 'n1');
      p = PlanEdit.move(p, 'chap1-s2', -1);
      p = PlanEdit.remove(p, 'epigraphe');
      p = PlanEdit.remove(p, 'chap3');

      expect(p.firstWhere((i) => i.id == 'chap2').title, 'Présentation de la Rawbank');
      final chap1 = p.firstWhere((i) => i.id == 'chap1');
      expect(chap1.children.map((c) => c.id), ['chap1-s2', 'chap1-s1', 'n1']);
      expect(chap1.children.last.level, 2);
      expect(p.any((i) => i.id == 'epigraphe'), isFalse);
      expect(p.any((i) => i.id == 'chap3'), isTrue, reason: 'obligatoire');
      expect(PlanNumbering.labels(p, formatting)['n1'], 'Section 3.');
    });

    test('aller-retour JSON (colonne student_works.plan)', () {
      final back = PlanItem.listFrom(jsonDecode(jsonEncode([for (final i in plan) i.toJson()])));
      expect(PlanEdit.count(back), PlanEdit.count(plan));
      expect(PlanNumbering.labels(back, formatting), PlanNumbering.labels(plan, formatting));
      expect(back.firstWhere((i) => i.id == 'intro-difficultes', orElse: () => back[5].children[7]).required,
          isFalse);
    });

    test('chiffres romains', () {
      expect([1, 4, 9, 14, 40, 2026].map(PlanNumbering.roman), ['I', 'IV', 'IX', 'XIV', 'XL', 'MMXXVI']);
      expect(PlanNumbering.apply('{alpha_upper}.', 3), 'C.');
    });
  });

  group('questionnaire', () {
    final t = QuestionnaireTemplate.fromJson(
        jsonDecode(File('test/fixtures/questionnaire.json').readAsStringSync()) as Map<String, dynamic>);

    test('variables remplies, questions retirées et ajoutées, numérotation continue', () {
      var d = const QuestionnaireDraft(values: {'organisation': 'la SNEL', 'service': 'la facturation'});
      d = d.toggle('q3').toggle('q7');
      d = d.add(1, const Question(id: 'perso-1', type: QuestionType.single, text: 'Revenez-vous à {{organisation}} ?',
          options: ['Oui', 'Non']));
      final q = FinalQuestionnaire.build(t, d);

      expect(q.intro, contains('sur la facturation de la SNEL'));
      expect(q.intro, contains('à …'), reason: 'établissement non rempli');
      final all = [for (final s in q.sections) ...s.questions];
      expect(all.map((x) => x.number), [for (var i = 1; i <= all.length; i++) i]);
      expect(all.any((x) => x.question.id == 'q3'), isFalse);
      expect(all.firstWhere((x) => x.question.id == 'perso-1').question.text, 'Revenez-vous à la SNEL ?');
      expect(q.questionCount, 9);

      final back = QuestionnaireDraft.decode(d.encode());
      expect(back.removed, {'q3', 'q7'});
      expect(back.added[1]!.single.options, ['Oui', 'Non']);
      expect(FinalQuestionnaire.build(t, back.toggle('q3')).questionCount, 10);
    });

    test('échelle lue comme une liste de choix', () {
      final q5 = t.sections[1].questions.first;
      expect(q5.type, QuestionType.scale);
      expect(q5.options, hasLength(5));
    });
  });
}
