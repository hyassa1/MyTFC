/// Modèle de questionnaire d'enquête (corps `questionnaire_template_bodies`)
/// et adaptation par l'étudiant. Le modèle est une structure : l'étudiant le
/// complète avec les questions propres à ses hypothèses.
library;

import 'dart:convert';

enum QuestionType {
  single('Choix unique'),
  multiple('Choix multiples'),
  scale('Échelle'),
  number('Nombre'),
  open('Question ouverte');

  const QuestionType(this.label);
  final String label;

  static QuestionType fromCode(String? c) => values.where((v) => v.name == c).firstOrNull ?? open;
}

/// Domaine (miroir de l'enum SQL `public.questionnaire_domain`).
const questionnaireDomains = {
  'gestion': 'Gestion et sciences commerciales',
  'economie': 'Économie',
  'droit': 'Droit',
  'sante': 'Santé publique',
  'informatique': 'Informatique',
  'education': 'Sciences de l\'éducation',
};

class Question {
  const Question({required this.id, required this.type, required this.text, this.options = const []});

  final String id;
  final QuestionType type;
  final String text;

  /// Choix proposés (ou degrés de l'échelle).
  final List<String> options;

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: j['id'] as String,
        type: QuestionType.fromCode(j['type'] as String?),
        text: j['text'] as String? ?? '',
        options: [for (final o in (j['options'] ?? j['scale'] ?? const []) as List) o.toString()],
      );

  Map<String, dynamic> toJson() => {'id': id, 'type': type.name, 'text': text, if (options.isNotEmpty) 'options': options};
}

class QuestionSection {
  const QuestionSection({required this.title, this.guidance, this.questions = const []});

  final String title;
  final String? guidance;
  final List<Question> questions;
}

class QuestionnaireVariable {
  const QuestionnaireVariable({required this.key, required this.label, this.example});
  final String key;
  final String label;
  final String? example;
}

class QuestionnaireTemplate {
  const QuestionnaireTemplate({
    this.variables = const [],
    this.intro,
    this.sections = const [],
    this.closing,
    this.tips = const [],
  });

  final List<QuestionnaireVariable> variables;
  final String? intro;
  final List<QuestionSection> sections;
  final String? closing;
  final List<String> tips;

  factory QuestionnaireTemplate.fromJson(Map<String, dynamic> j) => QuestionnaireTemplate(
        variables: [
          for (final v in (j['variables'] as List?) ?? const [])
            if (v is Map && v['key'] is String)
              QuestionnaireVariable(
                key: v['key'] as String,
                label: v['label'] as String? ?? v['key'] as String,
                example: v['example'] as String?,
              ),
        ],
        intro: j['intro'] as String?,
        sections: [
          for (final s in (j['sections'] as List?) ?? const [])
            if (s is Map)
              QuestionSection(
                title: s['title'] as String? ?? '',
                guidance: s['guidance'] as String?,
                questions: [
                  for (final q in (s['questions'] as List?) ?? const [])
                    if (q is Map && q['id'] is String) Question.fromJson(Map<String, dynamic>.from(q)),
                ],
              ),
        ],
        closing: j['closing'] as String?,
        tips: [for (final t in (j['tips'] as List?) ?? const []) t.toString()],
      );
}

/// Adaptation du modèle par l'étudiant (gardée sur le téléphone).
class QuestionnaireDraft {
  const QuestionnaireDraft({this.values = const {}, this.removed = const {}, this.added = const {}});

  /// Valeurs des variables ({{organisation}}…).
  final Map<String, String> values;

  /// Questions du modèle retirées.
  final Set<String> removed;

  /// Questions ajoutées, par numéro de section.
  final Map<int, List<Question>> added;

  factory QuestionnaireDraft.decode(String? raw) {
    if (raw == null) return const QuestionnaireDraft();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return QuestionnaireDraft(
      values: Map<String, String>.from((j['values'] as Map?) ?? const {}),
      removed: Set<String>.from((j['removed'] as List?) ?? const []),
      added: {
        for (final e in ((j['added'] as Map?) ?? const {}).entries)
          int.parse(e.key as String): [
            for (final q in e.value as List) Question.fromJson(Map<String, dynamic>.from(q as Map)),
          ],
      },
    );
  }

  String encode() => jsonEncode({
        'values': values,
        'removed': removed.toList(),
        'added': {for (final e in added.entries) '${e.key}': [for (final q in e.value) q.toJson()]},
      });

  QuestionnaireDraft copyWith({Map<String, String>? values, Set<String>? removed, Map<int, List<Question>>? added}) =>
      QuestionnaireDraft(values: values ?? this.values, removed: removed ?? this.removed, added: added ?? this.added);

  QuestionnaireDraft toggle(String questionId) => copyWith(
      removed: removed.contains(questionId) ? (Set.of(removed)..remove(questionId)) : {...removed, questionId});

  QuestionnaireDraft add(int section, Question q) =>
      copyWith(added: {...added, section: [...?added[section], q]});

  QuestionnaireDraft deleteAdded(String questionId) => copyWith(added: {
        for (final e in added.entries) e.key: e.value.where((q) => q.id != questionId).toList(),
      });
}

/// Questionnaire final, prêt à imprimer (variables remplies, numérotation continue).
class FinalQuestionnaire {
  const FinalQuestionnaire({this.intro, required this.sections, this.closing});
  final String? intro;
  final List<({String title, List<({int number, Question question})> questions})> sections;
  final String? closing;

  static final _var = RegExp(r'\{\{\s*([a-zA-Z0-9_]+)\s*\}\}');

  static String fill(String text, Map<String, String> values) => text.replaceAllMapped(_var, (m) {
        final v = values[m.group(1)]?.trim() ?? '';
        return v.isEmpty ? '…' : v;
      });

  factory FinalQuestionnaire.build(QuestionnaireTemplate t, QuestionnaireDraft d) {
    var n = 0;
    final sections = <({String title, List<({int number, Question question})> questions})>[];
    for (var i = 0; i < t.sections.length; i++) {
      final s = t.sections[i];
      final qs = [
        ...s.questions.where((q) => !d.removed.contains(q.id)),
        ...?d.added[i],
      ];
      if (qs.isEmpty) continue;
      sections.add((
        title: fill(s.title, d.values),
        questions: [
          for (final q in qs)
            (
              number: ++n,
              question: Question(
                id: q.id,
                type: q.type,
                text: fill(q.text, d.values),
                options: [for (final o in q.options) fill(o, d.values)],
              ),
            ),
        ],
      ));
    }
    return FinalQuestionnaire(
      intro: t.intro == null ? null : fill(t.intro!, d.values),
      sections: sections,
      closing: t.closing,
    );
  }

  int get questionCount => sections.fold(0, (n, s) => n + s.questions.length);
}
