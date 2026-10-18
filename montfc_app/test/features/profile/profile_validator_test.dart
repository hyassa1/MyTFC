import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/features/profile/domain/profile.dart';

void main() {
  const complete = Profile(
    id: 'u1',
    fullName: 'Mukendi Kabasele Grâce',
    institutionId: 'inst-1',
    faculty: 'Sciences économiques',
    level: AcademicLevel.l3,
    workType: WorkType.memoireLicence,
    academicYear: '2025-2026',
  );

  test('un profil complet est valide', () {
    expect(ProfileValidator.validate(complete), isEmpty);
    expect(complete.isComplete, isTrue);
  });

  test('chaque champ obligatoire manquant a son message', () {
    const empty = Profile(id: 'u1');
    expect(ProfileValidator.validate(empty).keys,
        containsAll(['full_name', 'institution_id', 'faculty', 'level', 'work_type', 'academic_year']));
    expect(empty.isComplete, isFalse);
  });

  test('« Autre » établissement : le nom est obligatoire', () {
    expect(ProfileValidator.validate(complete, institutionIsOther: true).keys, ['institution_other']);
    expect(ProfileValidator.validate(complete.copyWith(institutionOther: 'ISC Kinshasa'), institutionIsOther: true),
        isEmpty);
  });

  test('année académique : deux années consécutives', () {
    expect(ProfileValidator.isValidAcademicYear('2025-2026'), isTrue);
    expect(ProfileValidator.isValidAcademicYear('2025-2027'), isFalse);
    expect(ProfileValidator.isValidAcademicYear('2025/2026'), isFalse);
    expect(ProfileValidator.isValidAcademicYear(null), isFalse);
  });

  test('l\'année académique commence en septembre', () {
    expect(ProfileValidator.currentAcademicYear(DateTime(2026, 10, 18)), '2026-2027');
    expect(ProfileValidator.currentAcademicYear(DateTime(2026, 7, 1)), '2025-2026');
    expect(ProfileValidator.academicYearChoices(DateTime(2026, 10, 18)), ['2025-2026', '2026-2027', '2027-2028']);
  });

  test('aller-retour JSON avec les codes de la base', () {
    final p = Profile.fromJson({'id': 'u1', 'phone': '243812345678', ...complete.toUpdateJson()});
    expect(p.level, AcademicLevel.l3);
    expect(p.workType, WorkType.memoireLicence);
    expect(complete.toUpdateJson()['level'], 'L3');
    expect(complete.toUpdateJson()['work_type'], 'memoire_licence');
    expect(complete.toUpdateJson().containsKey('phone'), isFalse, reason: 'le téléphone n\'est pas modifiable');
  });
}
