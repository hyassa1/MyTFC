import '../../profile/domain/profile.dart';

/// Travail de l'étudiant (table `public.student_works`) : son sujet, sa page
/// de garde, son plan. Synchronisé entre le téléphone et le serveur.
class StudentWork {
  const StudentWork({
    required this.id,
    this.title,
    this.workType,
    this.director,
    this.supervisor,
    this.coverTemplateId,
    this.coverData = const {},
    this.plan = const [],
    this.documentTemplateId,
  });

  final String id;
  final String? title;
  final WorkType? workType;
  final String? director;
  final String? supervisor;
  final String? coverTemplateId;

  /// Valeurs saisies pour la page de garde, par clé de champ. Gardées d'un
  /// modèle à l'autre : changer de modèle ne fait rien perdre.
  final Map<String, String> coverData;
  final List<Object?> plan;
  final String? documentTemplateId;

  factory StudentWork.fromJson(Map<String, dynamic> j) => StudentWork(
        id: j['id'] as String,
        title: j['title'] as String?,
        workType: WorkType.fromCode(j['work_type'] as String?),
        director: j['director'] as String?,
        supervisor: j['supervisor'] as String?,
        coverTemplateId: j['cover_template_id'] as String?,
        coverData: {
          for (final e in ((j['cover_data'] as Map?) ?? const {}).entries)
            if (e.value != null) e.key as String: e.value.toString(),
        },
        plan: List<Object?>.from((j['plan'] as List?) ?? const []),
        documentTemplateId: j['document_template_id'] as String?,
      );

  /// Colonnes envoyées au serveur (push_changes).
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'work_type': workType?.code,
        'director': director,
        'supervisor': supervisor,
        'cover_template_id': coverTemplateId,
        'cover_data': coverData,
        'plan': plan,
        'document_template_id': documentTemplateId,
      };

  /// Enregistre une page de garde : les champs communs (sujet, directeur…)
  /// sont recopiés dans les colonnes du travail.
  StudentWork withCover(String templateId, Map<String, String> values) {
    String? v(String key) => (values[key]?.trim().isEmpty ?? true) ? null : values[key]!.trim();
    return StudentWork(
      id: id,
      title: v('title') ?? title,
      workType: WorkType.fromCode(values['grade']) ?? workType,
      director: v('director') ?? director,
      supervisor: v('supervisor'),
      coverTemplateId: templateId,
      coverData: {...coverData, ...values},
      plan: plan,
      documentTemplateId: documentTemplateId,
    );
  }

  /// Adopte (ou met à jour) le plan d'un modèle de document.
  StudentWork withPlan(String templateId, List<Object?> newPlan) => StudentWork(
        id: id,
        title: title,
        workType: workType,
        director: director,
        supervisor: supervisor,
        coverTemplateId: coverTemplateId,
        coverData: coverData,
        plan: newPlan,
        documentTemplateId: templateId,
      );
}
