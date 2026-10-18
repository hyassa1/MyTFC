import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/content/content_kinds.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/sync/sync_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';

/// Établissements disponibles (cache local, rechargé après chaque synchro).
final institutionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(contentStoreProvider).list(ContentKind.institution);
});

/// Création (après la première connexion) ou modification du profil.
class ProfileFormScreen extends ConsumerStatefulWidget {
  const ProfileFormScreen({super.key, this.isSetup = false, this.redirectTo});

  final bool isSetup;
  final String? redirectTo;

  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends ConsumerState<ProfileFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _other;
  late final TextEditingController _faculty;
  late final TextEditingController _department;
  String? _institutionId;
  AcademicLevel? _level;
  WorkType? _workType;
  String? _year;
  Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(authControllerProvider).profile;
    _name = TextEditingController(text: p?.fullName);
    _other = TextEditingController(text: p?.institutionOther);
    _faculty = TextEditingController(text: p?.faculty);
    _department = TextEditingController(text: p?.department);
    _institutionId = p?.institutionId;
    _level = p?.level;
    _workType = p?.workType;
    _year = p?.academicYear ?? ProfileValidator.currentAcademicYear(DateTime.now());
  }

  @override
  void dispose() {
    for (final c in [_name, _other, _faculty, _department]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isOther(List<Map<String, dynamic>> institutions) => institutions
      .any((i) => i['id'] == _institutionId && i['code'] == ProfileValidator.otherInstitutionCode);

  Future<void> _save(List<Map<String, dynamic>> institutions) async {
    final auth = ref.read(authControllerProvider);
    final base = auth.profile ?? Profile(id: auth.user!.id, phone: auth.user!.phone);
    final isOther = _isOther(institutions);
    final profile = base.copyWith(
      fullName: _name.text,
      institutionId: _institutionId,
      institutionOther: isOther ? _other.text : '',
      faculty: _faculty.text,
      department: _department.text,
      level: _level,
      workType: _workType,
      academicYear: _year,
    );
    final errors = ProfileValidator.validate(profile, institutionIsOther: isOther);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).saveProfile(profile);
      if (!mounted) return;
      if (widget.isSetup) {
        context.go(widget.redirectTo ?? Routes.home);
      } else {
        context.pop();
      }
    } on ProfileSaveException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final institutions = ref.watch(institutionsProvider).value ?? const [];
    final years = ProfileValidator.academicYearChoices(DateTime.now());
    if (_year != null && !years.contains(_year)) years.insert(0, _year!);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isSetup ? 'Ton profil' : 'Modifier mon profil'),
        automaticallyImplyLeading: !widget.isSetup,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.isSetup) ...[
            const Text('Ces informations servent à pré-remplir ta page de garde et tes documents.'),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nom complet',
              helperText: 'Nom, post-nom et prénom',
              errorText: _errors['full_name'],
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: institutions.any((i) => i['id'] == _institutionId) ? _institutionId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Université ou institut', errorText: _errors['institution_id']),
            items: [
              for (final i in institutions)
                DropdownMenuItem(value: i['id'] as String, child: Text(i['name'] as String, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _institutionId = v),
          ),
          if (_isOther(institutions)) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _other,
              decoration: InputDecoration(labelText: 'Nom de l\'établissement', errorText: _errors['institution_other']),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _faculty,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Faculté', hintText: 'Ex. Sciences économiques et de gestion', errorText: _errors['faculty']),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _department,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Département (facultatif)'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AcademicLevel>(
            initialValue: _level,
            decoration: InputDecoration(labelText: 'Niveau', errorText: _errors['level']),
            items: [for (final l in AcademicLevel.values) DropdownMenuItem(value: l, child: Text(l.label))],
            onChanged: (v) => setState(() => _level = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<WorkType>(
            initialValue: _workType,
            decoration: InputDecoration(labelText: 'Type de travail', errorText: _errors['work_type']),
            items: [for (final w in WorkType.values) DropdownMenuItem(value: w, child: Text(w.label))],
            onChanged: (v) => setState(() => _workType = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _year,
            decoration: InputDecoration(labelText: 'Année académique', errorText: _errors['academic_year']),
            items: [for (final y in years) DropdownMenuItem(value: y, child: Text(y))],
            onChanged: (v) => setState(() => _year = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _save(institutions),
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
