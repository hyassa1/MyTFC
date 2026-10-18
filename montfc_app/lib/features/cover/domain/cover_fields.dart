import '../../profile/domain/profile.dart';

/// Type de champ du formulaire de page de garde (`fields_schema`).
enum CoverFieldType {
  text,
  textarea,
  select,
  academicYear;

  static CoverFieldType fromCode(String? code) => switch (code) {
        'textarea' => textarea,
        'select' => select,
        'academic_year' => academicYear,
        _ => text,
      };
}

class CoverOption {
  const CoverOption(this.value, this.label);
  final String value;
  final String label;
}

/// Champ du formulaire, décrit par le modèle (modifiable depuis l'admin).
class CoverField {
  const CoverField({
    required this.key,
    required this.label,
    this.type = CoverFieldType.text,
    this.required = false,
    this.maxLength,
    this.prefill,
    this.options = const [],
    this.defaultValue,
    this.help,
  });

  final String key;
  final String label;
  final CoverFieldType type;
  final bool required;
  final int? maxLength;

  /// Source du pré-remplissage, ex. « profile.full_name ».
  final String? prefill;
  final List<CoverOption> options;
  final String? defaultValue;
  final String? help;

  factory CoverField.fromJson(Map<String, dynamic> j) => CoverField(
        key: j['key'] as String,
        label: j['label'] as String? ?? j['key'] as String,
        type: CoverFieldType.fromCode(j['type'] as String?),
        required: j['required'] == true,
        maxLength: (j['max_length'] as num?)?.toInt(),
        prefill: j['prefill'] as String?,
        options: [
          for (final o in (j['options'] as List?) ?? const [])
            if (o is Map) CoverOption(o['value'].toString(), (o['label'] ?? o['value']).toString()),
        ],
        defaultValue: j['default'] as String?,
        help: j['help'] as String?,
      );

  static List<CoverField> listFrom(Object? schema) => [
        for (final f in (schema as List?) ?? const [])
          if (f is Map && f['key'] is String) CoverField.fromJson(Map<String, dynamic>.from(f)),
      ];

  /// Valeur à imprimer : pour une liste, le libellé de l'option choisie.
  String display(String? raw) {
    final value = raw?.trim() ?? '';
    if (type == CoverFieldType.select) {
      return options.where((o) => o.value == value).firstOrNull?.label ?? value;
    }
    return value;
  }
}

/// Règles du formulaire de page de garde.
abstract final class CoverForm {
  static final _year = RegExp(r'^(\d{4})-(\d{4})$');

  /// Valeurs de départ : ce que l'étudiant a déjà saisi, sinon son profil,
  /// sinon la valeur par défaut du modèle.
  static Map<String, String> initialValues(
    List<CoverField> fields, {
    Map<String, String> saved = const {},
    Profile? profile,
    String? institutionName,
  }) {
    String? fromProfile(String? source) => switch (source) {
          'profile.full_name' => profile?.fullName,
          'profile.faculty' => profile?.faculty,
          'profile.department' => profile?.department,
          'profile.work_type' => profile?.workType?.code,
          'profile.academic_year' => profile?.academicYear,
          'profile.institution_name' => institutionName,
          _ => null,
        };
    return {
      for (final f in fields)
        f.key: saved[f.key] ?? fromProfile(f.prefill) ?? f.defaultValue ?? '',
    };
  }

  /// Erreurs par clé de champ (vide si tout est bon).
  static Map<String, String> validate(List<CoverField> fields, Map<String, String> values) {
    final errors = <String, String>{};
    for (final f in fields) {
      final v = values[f.key]?.trim() ?? '';
      if (v.isEmpty) {
        if (f.required) errors[f.key] = 'Champ obligatoire.';
        continue;
      }
      if (f.maxLength != null && v.length > f.maxLength!) {
        errors[f.key] = '${f.maxLength} caractères au maximum.';
      } else if (f.type == CoverFieldType.select && !f.options.any((o) => o.value == v)) {
        errors[f.key] = 'Choisis une valeur dans la liste.';
      } else if (f.type == CoverFieldType.academicYear) {
        final m = _year.firstMatch(v);
        if (m == null || int.parse(m.group(2)!) != int.parse(m.group(1)!) + 1) {
          errors[f.key] = 'Format attendu : 2025-2026.';
        }
      }
    }
    return errors;
  }

  /// Valeurs prêtes à imprimer (libellés des listes).
  static Map<String, String> displayValues(List<CoverField> fields, Map<String, String> values) => {
        ...values.map((k, v) => MapEntry(k, v.trim())),
        for (final f in fields) f.key: f.display(values[f.key]),
      };
}
