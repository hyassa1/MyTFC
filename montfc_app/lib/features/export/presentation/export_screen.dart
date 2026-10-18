import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../bibliography/presentation/bibliography_providers.dart';
import '../../cover/domain/cover_fields.dart';
import '../../cover/presentation/cover_screens.dart';
import '../../questionnaires/domain/questionnaire.dart';
import '../../questionnaires/presentation/questionnaire_screens.dart';
import '../../store/domain/entitlement.dart';
import '../../store/presentation/store_providers.dart';
import '../../templates/domain/document_template.dart';
import '../../templates/presentation/templates_screens.dart';
import '../../works/data/works_providers.dart';
import '../../works/domain/student_work.dart';
import '../data/export_service.dart';
import '../domain/export_builders.dart';
import '../domain/export_document.dart';

final exportServiceProvider = Provider<ExportService>((ref) => ExportService());

final exportFormatProvider =
    NotifierProvider<ExportFormatController, ExportFormat>(ExportFormatController.new);

class ExportFormatController extends Notifier<ExportFormat> {
  @override
  ExportFormat build() => ExportFormat.docx;

  void set(ExportFormat f) => state = f;
}

/// Ce qui peut être exporté, selon les droits et ce que l'étudiant a préparé.
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(currentWorkProvider).value;
    final rights = ref.watch(entitlementsProvider).value ?? EntitlementSet.empty;
    final sources = ref.watch(sourcesProvider).value ?? const [];
    final questionnaires = ref.watch(questionnaireTemplatesProvider).value ?? const [];
    final format = ref.watch(exportFormatProvider);
    final coverId = work?.coverTemplateId;
    final docId = work?.documentTemplateId;

    return Scaffold(
      appBar: AppBar(title: const Text('Export Word et PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ExportFormat>(
            segments: [for (final f in ExportFormat.values) ButtonSegment(value: f, label: Text(f.label))],
            selected: {format},
            onSelectionChanged: (s) => ref.read(exportFormatProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 8),
          Text(
            format == ExportFormat.docx
                ? 'Word : à compléter sur ordinateur. Les styles, la numérotation des pages et la table des matières '
                    'sont déjà en place.'
                : 'PDF : pour imprimer ou envoyer tel quel.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _ExportCard(
            icon: Icons.article_outlined,
            title: 'Page de garde',
            unlocked: coverId != null && rights.hasAccess(AppFeature.coverPage, resourceId: coverId),
            missing: coverId == null ? ('Remplis d\'abord ta page de garde.', Routes.cover) : null,
            build: () => _coverDocument(ref, work!),
          ),
          _ExportCard(
            icon: Icons.menu_book_outlined,
            title: 'Mon travail complet',
            subtitle: 'Page de garde, plan aux normes, consignes à remplacer par ton texte, bibliographie, '
                'table des matières.',
            unlocked: rights.hasAccess(AppFeature.export),
            missing: docId == null ? ('Choisis d\'abord le plan de ton travail.', Routes.templates) : null,
            build: () => _workDocument(ref, work!),
          ),
          _ExportCard(
            icon: Icons.format_list_bulleted,
            title: 'Bibliographie',
            unlocked: rights.hasAccess(AppFeature.bibliography),
            missing: sources.isEmpty ? ('Ajoute d\'abord tes sources.', Routes.bibliography) : null,
            build: () async => ExportBuilders.bibliography(sources, ref.read(bibliographyOrderProvider)),
          ),
          for (final q in questionnaires)
            if (rights.hasAccess(AppFeature.questionnaire, resourceId: q['id'] as String))
              _ExportCard(
                icon: Icons.quiz_outlined,
                title: 'Questionnaire : ${q['title']}',
                unlocked: true,
                build: () => _questionnaireDocument(ref, q['id'] as String, q['title'] as String),
              ),
          const SizedBox(height: 16),
          const Text(
            'Les fichiers exportés t\'appartiennent : tu peux les modifier, les imprimer et les partager librement.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static String _suffix(StudentWork work) {
    final name = work.coverData['student_name']?.trim() ?? '';
    return name.isEmpty ? '' : ' - ${name.split(' ').first}';
  }

  static Future<ExportSection?> _coverSection(WidgetRef ref, StudentWork work) async {
    final id = work.coverTemplateId;
    if (id == null) return null;
    final layout = await ref.read(coverLayoutProvider(id).future);
    final meta = (await ref.read(coverTemplatesProvider.future)).where((t) => t['id'] == id).firstOrNull;
    if (layout == null || meta == null) return null;
    final fields = CoverField.listFrom(meta['fields_schema']);
    return ExportBuilders.coverSection(layout, CoverForm.displayValues(fields, work.coverData));
  }

  static Future<ExportDocument> _coverDocument(WidgetRef ref, StudentWork work) async {
    final section = await _coverSection(ref, work);
    if (section == null) throw const ExportUnavailable();
    return ExportDocument(title: 'Page de garde${_suffix(work)}', sections: [section]);
  }

  static Future<ExportDocument> _workDocument(WidgetRef ref, StudentWork work) async {
    final body = await ref.read(documentBodyProvider(work.documentTemplateId!).future);
    // Le plan reste lisible même si le modèle n'est plus téléchargé : on prend celui de l'étudiant.
    final plan = work.plan.isNotEmpty ? PlanItem.listFrom(work.plan) : body?.plan ?? const <PlanItem>[];
    if (plan.isEmpty) throw const ExportUnavailable();
    return ExportBuilders.work(
      title: '${work.workType?.label ?? 'Travail'}${_suffix(work)}',
      plan: plan,
      formatting: body?.formatting ?? const DocFormatting(),
      cover: await _coverSection(ref, work),
      sources: await ref.read(sourcesProvider.future),
    );
  }

  static Future<ExportDocument> _questionnaireDocument(WidgetRef ref, String id, String title) async {
    final template = await ref.read(questionnaireBodyProvider(id).future);
    if (template == null) throw const ExportUnavailable();
    final draft = QuestionnaireDraft.decode(await ref.read(kvStoreProvider).get(questionnaireDraftKey(id)));
    return ExportBuilders.questionnaire(FinalQuestionnaire.build(template, draft), title: title);
  }
}

/// Contenu payant pas encore téléchargé sur le téléphone.
class ExportUnavailable implements Exception {
  const ExportUnavailable();
}

class _ExportCard extends ConsumerStatefulWidget {
  const _ExportCard({
    required this.icon,
    required this.title,
    required this.unlocked,
    required this.build,
    this.subtitle,
    this.missing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool unlocked;

  /// Ce qu'il faut préparer avant (message, page où le faire).
  final (String, String)? missing;
  final Future<ExportDocument> Function() build;

  @override
  ConsumerState<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends ConsumerState<_ExportCard> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await widget.build();
      await ref.read(exportServiceProvider).share(doc, ref.read(exportFormatProvider));
    } on ExportUnavailable {
      messenger.showSnackBar(const SnackBar(
          content: Text('Ce contenu n\'est pas encore téléchargé. Connecte-toi à internet un instant.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('L\'export n\'a pas abouti. Réessaie.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing = widget.missing;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(widget.icon),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
            ]),
            if (widget.subtitle != null) ...[const SizedBox(height: 4), Text(widget.subtitle!)],
            const SizedBox(height: 12),
            if (!widget.unlocked)
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.store),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Débloquer'),
              )
            else if (missing != null)
              TextButton(onPressed: () => context.push(missing.$2), child: Text(missing.$1))
            else
              FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.share),
                label: const Text('Créer et partager (WhatsApp…)'),
              ),
          ],
        ),
      ),
    );
  }
}
