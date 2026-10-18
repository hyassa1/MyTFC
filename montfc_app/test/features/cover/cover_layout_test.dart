import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/features/cover/domain/cover_fields.dart';
import 'package:montfc/features/cover/domain/cover_layout.dart';
import 'package:montfc/features/profile/domain/profile.dart';

import 'cover_test_data.dart';

void main() {
  group('champs {{cle}}', () {
    test('majuscules avec accents, minuscules, champ inconnu vide', () {
      final v = {'faculty': 'Sciences économiques', 'x': 'ABC'};
      expect(CoverLayout.fill('FACULTÉ DE {{faculty|upper}}', v), 'FACULTÉ DE SCIENCES ÉCONOMIQUES');
      expect(CoverLayout.fill('{{ x | lower }}', v), 'abc');
      expect(CoverLayout.fill('[{{absent}}]', v), '[]');
      expect(CoverLayout.fill('{{absent}}', v, missing: (k) => '<$k>'), '<absent>');
    });
  });

  group('modèles de démonstration', () {
    final values = {
      'faculty': 'Sciences économiques',
      'department': '',
      'title': 'La gestion de la trésorerie dans les PME de Kinshasa',
      'student_name': 'Mbuyi Kalala Jean',
      'grade': 'Mémoire présenté et défendu en vue de l\'obtention du grade de licencié',
      'discipline': 'gestion financière',
      'director': 'Prof. Lukusa',
      'supervisor': '',
      'academic_year': '2025-2026',
    };

    test('UNIKIN : cadre double, blocs conditionnels retirés, titre dans un cadre', () {
      final l = layout(unikinId);
      expect(l.page.border, CoverBorder.double);
      expect(l.page.margins.left, 2.5);
      final blocks = l.resolve(values);
      final texts = [
        for (final b in blocks)
          if (b is TextBlock) b.text,
      ];
      expect(texts.first, 'UNIVERSITÉ DE KINSHASA');
      expect(texts, contains('FACULTÉ DE SCIENCES ÉCONOMIQUES'));
      expect(texts.any((t) => t.startsWith('DÉPARTEMENT')), isFalse, reason: 'département vide');
      expect(texts.any((t) => t.startsWith('Encadreur')), isFalse, reason: 'encadreur vide');
      expect(texts, contains('MBUYI KALALA JEAN'));
      expect(texts.last, 'Année académique 2025-2026');
      final box = blocks.whereType<BoxBlock>().single;
      expect((box.blocks.single as TextBlock).text, 'LA GESTION DE LA TRÉSORERIE DANS LES PME DE KINSHASA');
    });

    test('les trois modèles se lisent sans erreur', () {
      for (final id in layoutsJson().keys) {
        expect(layout(id).resolve(values), isNotEmpty, reason: id);
      }
    });
  });

  test('version de modèle plus récente que l\'app : message de mise à jour', () {
    expect(() => CoverLayout.fromJson({'schema_version': 2, 'blocks': []}),
        throwsA(isA<CoverLayoutException>().having((e) => e.message, 'message', contains('à jour'))));
  });

  test('type de bloc inconnu ignoré, valeurs par défaut sûres', () {
    final l = CoverLayout.fromJson({
      'blocks': [
        {'type': 'image', 'url': 'x'},
        {'type': 'text', 'text': 'A', 'indent_left_ratio': 5},
        'pas un bloc',
      ],
    });
    expect(l.blocks, hasLength(1));
    expect((l.blocks.single as TextBlock).indentLeftRatio, 0.9);
    expect(l.fontSize, 12);
    expect(l.page.widthCm, 21);
  });

  group('formulaire', () {
    final fields = CoverField.listFrom(coverTemplates().firstWhere((t) => t['id'] == genericId)['fields_schema']);
    const profile = Profile(
      id: 'u1',
      fullName: 'Mbuyi Kalala Jean',
      faculty: 'Droit',
      workType: WorkType.tfc,
      academicYear: '2025-2026',
    );

    test('pré-remplissage : saisie déjà faite > profil > vide', () {
      final v = CoverForm.initialValues(fields,
          saved: {'faculty': 'Sciences économiques'}, profile: profile, institutionName: 'ISC Kinshasa');
      expect(v['faculty'], 'Sciences économiques');
      expect(v['student_name'], 'Mbuyi Kalala Jean');
      expect(v['institution_name'], 'ISC Kinshasa');
      expect(v['grade'], 'tfc');
      expect(v['director'], '');
    });

    test('validation : obligatoires, année académique, liste', () {
      final v = CoverForm.initialValues(fields, profile: profile, institutionName: 'ISC');
      final errors = CoverForm.validate(fields, {...v, 'academic_year': '2025-2027', 'grade': 'doctorat'});
      expect(errors.keys, containsAll(['title', 'director', 'discipline', 'academic_year', 'grade']));
      expect(errors.containsKey('supervisor'), isFalse, reason: 'facultatif');
      expect(errors['academic_year'], contains('2025-2026'));
    });

    test('impression : la liste affiche le libellé complet', () {
      final d = CoverForm.displayValues(fields, {'grade': 'tfc'});
      expect(d['grade'], startsWith('Travail de fin de cycle'));
    });
  });
}
