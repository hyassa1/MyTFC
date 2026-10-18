import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/content/content_kinds.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/sync/sync_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/profile_form_screen.dart';
import '../../store/domain/entitlement.dart';
import '../../store/presentation/paid_feature_gate.dart';
import '../../works/data/works_providers.dart';
import '../domain/cover_fields.dart';
import '../domain/cover_layout.dart';
import 'cover_preview.dart';

/// Modèles de page de garde (liste publique, lisible hors ligne).
final coverTemplatesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(contentStoreProvider).list(ContentKind.coverTemplate);
});

/// Mise en page d'un modèle : null si pas encore téléchargée (contenu payant,
/// envoyé par le serveur seulement après l'achat).
final coverLayoutProvider = FutureProvider.family<CoverLayout?, String>((ref, id) async {
  ref.watch(contentRevisionProvider);
  final body = await ref.watch(contentStoreProvider).body(BodyKind.cover, id);
  final layout = body?['layout'];
  return layout is Map ? CoverLayout.fromJson(Map<String, dynamic>.from(layout)) : null;
});

/// Nom de l'établissement du profil (ou celui saisi pour « Autre »).
String? institutionNameOf(Profile? profile, List<Map<String, dynamic>> institutions) {
  if (profile == null) return null;
  final inst = institutions.where((i) => i['id'] == profile.institutionId).firstOrNull;
  if (inst == null || inst['code'] == 'AUTRE') return profile.institutionOther;
  return inst['name'] as String?;
}

/// Choix du modèle : celui de l'établissement de l'étudiant en premier.
class CoverTemplatesScreen extends ConsumerWidget {
  const CoverTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(coverTemplatesProvider).value ?? const [];
    final profile = ref.watch(authControllerProvider).profile;
    final savedId = ref.watch(currentWorkProvider).value?.coverTemplateId;

    final mine = templates.where((t) => t['institution_id'] != null && t['institution_id'] == profile?.institutionId);
    final ordered = [...mine, ...templates.where((t) => !mine.contains(t))];

    return Scaffold(
      appBar: AppBar(title: const Text('Page de garde')),
      body: ordered.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Les modèles seront disponibles après ta première connexion à internet.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('Choisis le modèle de ton établissement. Tes informations sont gardées si tu '
                      'changes de modèle.'),
                ),
                for (final t in ordered)
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(t['name'] as String),
                    subtitle: Text(t['id'] == savedId
                        ? 'Ta page de garde actuelle'
                        : mine.contains(t)
                            ? 'Ton établissement'
                            : (t['description'] as String? ?? '')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.coverEditor(t['id'] as String)),
                  ),
              ],
            ),
    );
  }
}

/// Saisie et aperçu d'une page de garde (contenu payant).
class CoverEditorScreen extends ConsumerWidget {
  const CoverEditorScreen({super.key, required this.templateId});

  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template =
        (ref.watch(coverTemplatesProvider).value ?? const []).where((t) => t['id'] == templateId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(template?['name'] as String? ?? 'Page de garde')),
      body: PaidFeatureGate(
        feature: AppFeature.coverPage,
        resourceId: templateId,
        child: template == null
            ? const Center(child: Text('Modèle introuvable.'))
            : ref.watch(coverLayoutProvider(templateId)).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(e is CoverLayoutException ? e.message : 'Modèle illisible.',
                          textAlign: TextAlign.center),
                    ),
                  ),
                  data: (layout) => layout == null
                      ? const _NotDownloaded()
                      : _CoverEditor(
                          templateId: templateId,
                          fields: CoverField.listFrom(template['fields_schema']),
                          layout: layout,
                        ),
                ),
      ),
    );
  }
}

class _NotDownloaded extends ConsumerWidget {
  const _NotDownloaded();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(syncControllerProvider.select((s) => s.running));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ce modèle est débloqué mais pas encore téléchargé sur ton téléphone. '
                'Connecte-toi à internet un instant.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: running ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
              child: const Text('Télécharger maintenant'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverEditor extends ConsumerStatefulWidget {
  const _CoverEditor({required this.templateId, required this.fields, required this.layout});

  final String templateId;
  final List<CoverField> fields;
  final CoverLayout layout;

  @override
  ConsumerState<_CoverEditor> createState() => _CoverEditorState();
}

class _CoverEditorState extends ConsumerState<_CoverEditor> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _controllers = <String, TextEditingController>{};
  Map<String, String> _values = {};
  Map<String, String> _errors = {};
  bool _loaded = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      // Passer à l'aperçu enregistre ce qui a été saisi.
      if (_tabs.index == 1 && _dirty) _save(quiet: true);
    });
    _load();
  }

  Future<void> _load() async {
    final work = await ref.read(worksRepositoryProvider).current();
    final profile = ref.read(authControllerProvider).profile;
    final institutions = await ref.read(institutionsProvider.future);
    final values = CoverForm.initialValues(
      widget.fields,
      saved: work?.coverData ?? const {},
      profile: profile,
      institutionName: institutionNameOf(profile, institutions),
    );
    if (!mounted) return;
    setState(() {
      _values = values;
      for (final f in widget.fields) {
        _controllers[f.key] = TextEditingController(text: values[f.key]);
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    if (_dirty) unawaited(_save(quiet: true));
    _tabs.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String key, String value) => setState(() {
        _values = {..._values, key: value};
        _errors = Map.of(_errors)..remove(key);
        _dirty = true;
      });

  Future<void> _save({bool quiet = false}) async {
    if (!quiet) {
      final errors = CoverForm.validate(widget.fields, _values);
      setState(() => _errors = errors);
      if (errors.isNotEmpty) {
        _tabs.index = 0;
        return;
      }
    }
    final repo = ref.read(worksRepositoryProvider);
    final work = await repo.currentOrNew();
    await repo.save(work.withCover(widget.templateId, _values));
    _dirty = false;
    // Envoi au serveur dès que possible (sauvegarde, autre appareil).
    unawaited(ref.read(syncControllerProvider.notifier).syncNow());
    ref.invalidate(currentWorkProvider);
    if (!quiet && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page de garde enregistrée sur ton téléphone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final display = CoverForm.displayValues(widget.fields, _values);
    final labels = {for (final f in widget.fields) f.key: f.label};

    return Column(
      children: [
        TabBar(controller: _tabs, tabs: const [Tab(text: 'Informations'), Tab(text: 'Aperçu')]),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final f in widget.fields) ...[_field(f), const SizedBox(height: 12)],
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Enregistrer'),
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CoverPreview(
                    layout: widget.layout,
                    // Champ vide : repère visible dans l'aperçu, rien à l'export.
                    blocks: widget.layout.resolve(display, missing: (k) => '[${labels[k] ?? k}]'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Vérifie l\'orthographe des noms et du sujet avant l\'impression : le jury y est attentif.',
                      textAlign: TextAlign.center),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(CoverField f) {
    final label = f.required ? '${f.label} *' : f.label;
    switch (f.type) {
      case CoverFieldType.select:
        final value = f.options.any((o) => o.value == _values[f.key]) ? _values[f.key] : null;
        return DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, errorText: _errors[f.key], helperText: f.help),
          items: [
            for (final o in f.options)
              DropdownMenuItem(value: o.value, child: Text(o.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => _set(f.key, v ?? ''),
        );
      case CoverFieldType.academicYear:
        final years = ProfileValidator.academicYearChoices(DateTime.now());
        final current = _values[f.key];
        if (current != null && current.isNotEmpty && !years.contains(current)) years.insert(0, current);
        return DropdownButtonFormField<String>(
          initialValue: current == null || current.isEmpty ? null : current,
          decoration: InputDecoration(labelText: label, errorText: _errors[f.key]),
          items: [for (final y in years) DropdownMenuItem(value: y, child: Text(y))],
          onChanged: (v) => _set(f.key, v ?? ''),
        );
      case CoverFieldType.text || CoverFieldType.textarea:
        return TextField(
          controller: _controllers[f.key],
          maxLength: f.maxLength,
          minLines: f.type == CoverFieldType.textarea ? 2 : 1,
          maxLines: f.type == CoverFieldType.textarea ? 5 : 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, errorText: _errors[f.key], helperText: f.help,
              helperMaxLines: 3),
          onChanged: (v) => _set(f.key, v),
        );
    }
  }
}
