/// Niveau d'études (miroir de l'enum SQL `public.academic_level`).
enum AcademicLevel {
  g1('G1', 'G1 (graduat 1)'),
  g2('G2', 'G2 (graduat 2)'),
  g3('G3', 'G3 (graduat 3)'),
  l1('L1', 'L1 (licence 1)'),
  l2('L2', 'L2 (licence 2)'),
  l3('L3', 'L3 (licence 3)'),
  m1('M1', 'M1 (master 1)'),
  m2('M2', 'M2 (master 2)'),
  other('AUTRE', 'Autre');

  const AcademicLevel(this.code, this.label);

  final String code;
  final String label;

  static AcademicLevel? fromCode(String? code) =>
      values.where((v) => v.code == code).firstOrNull;
}

/// Type de travail (miroir de l'enum SQL `public.work_type`).
enum WorkType {
  tfc('tfc', 'TFC (travail de fin de cycle)'),
  memoireLicence('memoire_licence', 'Mémoire de licence'),
  memoireMaster('memoire_master', 'Mémoire de master');

  const WorkType(this.code, this.label);

  final String code;
  final String label;

  static WorkType? fromCode(String? code) => values.where((v) => v.code == code).firstOrNull;
}

/// Profil de l'étudiant (table `public.profiles`).
class Profile {
  const Profile({
    required this.id,
    this.phone,
    this.fullName,
    this.institutionId,
    this.institutionOther,
    this.faculty,
    this.department,
    this.level,
    this.workType,
    this.academicYear,
  });

  final String id;
  final String? phone;
  final String? fullName;
  final String? institutionId;

  /// Nom saisi quand l'établissement est « Autre ».
  final String? institutionOther;
  final String? faculty;
  final String? department;
  final AcademicLevel? level;
  final WorkType? workType;

  /// Format « 2025-2026 ».
  final String? academicYear;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        phone: json['phone'] as String?,
        fullName: json['full_name'] as String?,
        institutionId: json['institution_id'] as String?,
        institutionOther: json['institution_other'] as String?,
        faculty: json['faculty'] as String?,
        department: json['department'] as String?,
        level: AcademicLevel.fromCode(json['level'] as String?),
        workType: WorkType.fromCode(json['work_type'] as String?),
        academicYear: json['academic_year'] as String?,
      );

  /// Colonnes modifiables par l'étudiant (le téléphone ne l'est pas).
  Map<String, dynamic> toUpdateJson() => {
        'full_name': fullName?.trim(),
        'institution_id': institutionId,
        'institution_other': _blankToNull(institutionOther),
        'faculty': faculty?.trim(),
        'department': _blankToNull(department),
        'level': level?.code,
        'work_type': workType?.code,
        'academic_year': academicYear,
      };

  Map<String, dynamic> toJson() => {'id': id, 'phone': phone, ...toUpdateJson()};

  /// Vrai quand toutes les informations obligatoires sont remplies.
  bool get isComplete => ProfileValidator.validate(this).isEmpty;

  Profile copyWith({
    String? fullName,
    String? institutionId,
    String? institutionOther,
    String? faculty,
    String? department,
    AcademicLevel? level,
    WorkType? workType,
    String? academicYear,
  }) =>
      Profile(
        id: id,
        phone: phone,
        fullName: fullName ?? this.fullName,
        institutionId: institutionId ?? this.institutionId,
        institutionOther: institutionOther ?? this.institutionOther,
        faculty: faculty ?? this.faculty,
        department: department ?? this.department,
        level: level ?? this.level,
        workType: workType ?? this.workType,
        academicYear: academicYear ?? this.academicYear,
      );

  static String? _blankToNull(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
}

/// Règles de validation du profil (messages en français, par champ).
abstract final class ProfileValidator {
  /// Code de l'établissement « Autre » (table institutions).
  static const otherInstitutionCode = 'AUTRE';

  static Map<String, String> validate(Profile p, {bool institutionIsOther = false}) {
    final errors = <String, String>{};
    final name = p.fullName?.trim() ?? '';
    if (name.length < 3) {
      errors['full_name'] = 'Indique ton nom complet.';
    } else if (name.length > 120) {
      errors['full_name'] = '120 caractères au maximum.';
    }
    if (p.institutionId == null) errors['institution_id'] = 'Choisis ton établissement.';
    if (institutionIsOther && (p.institutionOther?.trim().isEmpty ?? true)) {
      errors['institution_other'] = 'Indique le nom de ton établissement.';
    }
    if (p.faculty?.trim().isEmpty ?? true) errors['faculty'] = 'Indique ta faculté.';
    if (p.level == null) errors['level'] = 'Choisis ton niveau.';
    if (p.workType == null) errors['work_type'] = 'Choisis le type de travail.';
    if (!isValidAcademicYear(p.academicYear)) errors['academic_year'] = 'Choisis l\'année académique.';
    return errors;
  }

  /// « 2025-2026 » : deux années consécutives.
  static bool isValidAcademicYear(String? value) {
    final m = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(value ?? '');
    if (m == null) return false;
    return int.parse(m.group(2)!) == int.parse(m.group(1)!) + 1;
  }

  /// L'année académique commence en octobre en RDC : de septembre à
  /// décembre 2026, on propose 2026-2027 ; de janvier à août, 2025-2026.
  static String currentAcademicYear(DateTime now) {
    final start = now.month >= 9 ? now.year : now.year - 1;
    return '$start-${start + 1}';
  }

  /// Choix proposés : l'année précédente, la courante et la suivante.
  static List<String> academicYearChoices(DateTime now) {
    final start = int.parse(currentAcademicYear(now).substring(0, 4));
    return [for (var y = start - 1; y <= start + 1; y++) '$y-${y + 1}'];
  }
}
