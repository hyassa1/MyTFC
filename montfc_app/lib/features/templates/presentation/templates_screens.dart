import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/content/content_kinds.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/sync/sync_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/domain/profile.dart';
import '../../store/domain/entitlement.dart';
import '../../store/presentation/paid_feature_gate.dart';
import '../../store/presentation/store_providers.dart';
import '../../works/data/works_providers.dart';
import '../domain/document_template.dart';

final documentTemplatesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(contentStoreProvider).list(ContentKind.documentTemplate);
});

/// Plan et normes d'un modèle : null si pas encore téléchargé (contenu payant).
final documentBodyProvider =
    FutureProvider.family<({List<PlanItem> plan, DocFormatting formatting})?, String>((ref, id) async {
  ref.watch(contentRevisionProvider);
  final body = await ref.watch(contentStoreProvider).body(BodyKind.document, id);
  if (body == null) return null;
  return (
    plan: PlanItem.listFrom(body['structure']),
    formatting: DocFormatting.fromJson(Map<String, dynamic>.from((body['formatting'] as Map?) ?? const {})),
  );
});

/// Liste des modèles : ceux du type de travail de l'étudiant en premier.
class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(documentTemplatesProvider).value ?? const [];
    final workType = ref.watch(authControllerProvider).profile?.workType;
    final rights = ref.watch(entitlementsProvider).value ?? EntitlementSet.empty;
    final ordered = [
      ...templates.where((t) => t['work_type'] == workType?.code),
      ...templates.where((t) => t['work_type'] != workType?.code),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Modèles de document')),
      body: ordered.isEmpty
          ? const Center(child: Text('Les modèles seront disponibles après ta première connexion.'))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('Chaque modèle donne le plan attendu, les consignes de chaque partie et les normes '
                      'de mise en forme. Le texte, c\'est toi qui l\'écris.'),
                ),
                for (final t in ordered)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(t['title'] as String),
                    subtitle: Text([
                      WorkType.fromCode(t['work_type'] as String?)?.label,
                      if (rights.hasAccess(AppFeature.docTemplate, resourceId: t['id'] as String)) 'Débloqué',
                    ].whereType<String>().join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.template(t['id'] as String)),
                  ),
              ],
            ),
    );
  }
}

/// Un modèle : plan avec consignes, normes, et adoption pour son travail.
class TemplateScreen extends ConsumerWidget {
  const TemplateScreen({super.key, required this.templateId});

  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta =
        (ref.watch(documentTemplatesProvider).value ?? const []).where((t) => t['id'] == templateId).firstOrNull;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(meta?['title'] as String? ?? 'Modèle')),
        body: PaidFeatureGate(
          feature: AppFeature.docTemplate,
          resourceId: templateId,
          child: ref.watch(documentBodyProvider(templateId)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Center(child: Text('Modèle illisible.')),
                data: (body) => body == null
                    ? const _NotDownloaded()
                    : Column(
                        children: [
                          const TabBar(tabs: [Tab(text: 'Plan et consignes'), Tab(text: 'Normes')]),
                          Expanded(
                            child: TabBarView(children: [
                              _PlanView(templateId: templateId, template: body.plan, formatting: body.formatting),
                              ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  for (final line in body.formatting.summary())
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.check, size: 18),
                                      title: Text(line),
                                    ),
                                  const SizedBox(height: 8),
                                  const Text('Ces normes sont appliquées automatiquement à l\'export Word et PDF.'),
                                ],
                              ),
                            ]),
                          ),
                        ],
                      ),
              ),
        ),
      ),
    );
  }
}

class _NotDownloaded extends ConsumerWidget {
  const _NotDownloaded();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Ce modèle est débloqué mais pas encore téléchargé. Connecte-toi à internet un instant.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
              child: const Text('Télécharger maintenant'),
            ),
          ]),
        ),
      );
}

/// Plan : celui de l'étudiant s'il a adopté ce modèle, sinon celui du modèle.
class _PlanView extends ConsumerStatefulWidget {
  const _PlanView({required this.templateId, required this.template, required this.formatting});

  final String templateId;
  final List<PlanItem> template;
  final DocFormatting formatting;

  @override
  ConsumerState<_PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends ConsumerState<_PlanView> {
  List<PlanItem>? _plan;
  bool _adopted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final work = await ref.read(worksRepositoryProvider).current();
    final saved = work?.documentTemplateId == widget.templateId ? PlanItem.listFrom(work!.plan) : const <PlanItem>[];
    if (!mounted) return;
    setState(() {
      _adopted = saved.isNotEmpty;
      _plan = saved.isNotEmpty ? saved : widget.template;
    });
  }

  Future<void> _save(List<PlanItem> plan, {bool adopt = false}) async {
    setState(() {
      _plan = plan;
      if (adopt) _adopted = true;
    });
    final repo = ref.read(worksRepositoryProvider);
    final work = await repo.currentOrNew();
    await repo.save(work.withPlan(widget.templateId, [for (final i in plan) i.toJson()]));
    ref.invalidate(currentWorkProvider);
    unawaited(ref.read(syncControllerProvider.notifier).syncNow());
  }

  Future<String?> _ask(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim().isEmpty ? null : controller.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    if (plan == null) return const Center(child: CircularProgressIndicator());
    final labels = PlanNumbering.labels(plan, widget.formatting);

    List<Widget> tiles(List<PlanItem> items, int depth) => [
          for (final item in items) ...[
            ExpansionTile(
              key: PageStorageKey(item.id),
              tilePadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 8),
              title: Text(
                [labels[item.id], item.title].whereType<String>().join(' : '),
                style: TextStyle(fontWeight: item.level <= 1 ? FontWeight.bold : FontWeight.normal),
              ),
              subtitle: item.required ? null : const Text('Facultatif'),
              childrenPadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 16, bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.guidance != null) Text(item.guidance!),
                if (_adopted)
                  Wrap(spacing: 4, children: [
                    TextButton(
                      onPressed: () async {
                        final t = await _ask('Ton intitulé', initial: item.title);
                        if (t != null) await _save(PlanEdit.rename(plan, item.id, t));
                      },
                      child: const Text('Renommer'),
                    ),
                    if (item.level >= 1 && item.level < 4 && item.kind == SectionKind.body)
                      TextButton(
                        onPressed: () async {
                          final t = await _ask('Nouvelle sous-partie');
                          if (t != null) await _save(PlanEdit.addChild(plan, item.id, t, const Uuid().v4()));
                        },
                        child: const Text('Ajouter une sous-partie'),
                      ),
                    IconButton(
                      tooltip: 'Monter',
                      onPressed: () => _save(PlanEdit.move(plan, item.id, -1)),
                      icon: const Icon(Icons.arrow_upward, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Descendre',
                      onPressed: () => _save(PlanEdit.move(plan, item.id, 1)),
                      icon: const Icon(Icons.arrow_downward, size: 18),
                    ),
                    if (!item.required)
                      TextButton(
                        onPressed: () => _save(PlanEdit.remove(plan, item.id)),
                        child: const Text('Retirer'),
                      ),
                  ]),
              ],
            ),
            ...tiles(item.children, depth + 1),
          ],
        ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!_adopted)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () => _save(widget.template, adopt: true),
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Utiliser ce plan pour mon travail'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Expanded(child: Text('C\'est ton plan : adapte les intitulés à ton sujet.')),
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Revenir au plan du modèle ?'),
                      content: const Text('Tes intitulés personnalisés seront remplacés.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rétablir')),
                      ],
                    ),
                  );
                  if (ok == true) await _save(widget.template);
                },
                child: const Text('Rétablir'),
              ),
            ]),
          ),
        ...tiles(plan, 0),
      ],
    );
  }
}
