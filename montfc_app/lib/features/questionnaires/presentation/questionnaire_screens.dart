import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/content/content_kinds.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/sync/sync_controller.dart';
import '../../store/domain/entitlement.dart';
import '../../store/presentation/paid_feature_gate.dart';
import '../../store/presentation/store_providers.dart';
import '../domain/questionnaire.dart';

final questionnaireTemplatesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(contentStoreProvider).list(ContentKind.questionnaireTemplate);
});

final questionnaireBodyProvider = FutureProvider.family<QuestionnaireTemplate?, String>((ref, id) async {
  ref.watch(contentRevisionProvider);
  final body = await ref.watch(contentStoreProvider).body(BodyKind.questionnaire, id);
  final json = body?['body'];
  return json is Map ? QuestionnaireTemplate.fromJson(Map<String, dynamic>.from(json)) : null;
});

/// Adaptation d'un questionnaire, gardée sur le téléphone.
String questionnaireDraftKey(String id) => 'questionnaire.draft.$id';

/// Questionnaires classés par domaine.
class QuestionnairesScreen extends ConsumerWidget {
  const QuestionnairesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(questionnaireTemplatesProvider).value ?? const [];
    final rights = ref.watch(entitlementsProvider).value ?? EntitlementSet.empty;
    return Scaffold(
      appBar: AppBar(title: const Text('Questionnaires d\'enquête')),
      body: templates.isEmpty
          ? const Center(child: Text('Les questionnaires seront disponibles après ta première connexion.'))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final domain in questionnaireDomains.entries)
                  if (templates.where((t) => t['domain'] == domain.key).toList() case final list
                      when list.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(domain.value, style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final t in list)
                      ListTile(
                        leading: const Icon(Icons.quiz_outlined),
                        title: Text(t['title'] as String),
                        subtitle: Text([
                          t['description'] as String?,
                          if (rights.hasAccess(AppFeature.questionnaire, resourceId: t['id'] as String)) 'Débloqué',
                        ].whereType<String>().join(' · ')),
                        onTap: () => context.push(Routes.questionnaire(t['id'] as String)),
                      ),
                  ],
              ],
            ),
    );
  }
}

class QuestionnaireScreen extends ConsumerWidget {
  const QuestionnaireScreen({super.key, required this.templateId});

  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = (ref.watch(questionnaireTemplatesProvider).value ?? const [])
        .where((t) => t['id'] == templateId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(meta?['title'] as String? ?? 'Questionnaire')),
      body: PaidFeatureGate(
        feature: AppFeature.questionnaire,
        resourceId: templateId,
        child: ref.watch(questionnaireBodyProvider(templateId)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('Questionnaire illisible.')),
              data: (t) => t == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Ce questionnaire est débloqué mais pas encore téléchargé. '
                              'Connecte-toi à internet un instant.', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
                            child: const Text('Télécharger maintenant'),
                          ),
                        ]),
                      ),
                    )
                  : _QuestionnaireEditor(templateId: templateId, template: t),
            ),
      ),
    );
  }
}

class _QuestionnaireEditor extends ConsumerStatefulWidget {
  const _QuestionnaireEditor({required this.templateId, required this.template});

  final String templateId;
  final QuestionnaireTemplate template;

  @override
  ConsumerState<_QuestionnaireEditor> createState() => _QuestionnaireEditorState();
}

class _QuestionnaireEditorState extends ConsumerState<_QuestionnaireEditor> {
  QuestionnaireDraft? _draft;
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    ref.read(kvStoreProvider).get(questionnaireDraftKey(widget.templateId)).then((raw) {
      if (!mounted) return;
      final draft = QuestionnaireDraft.decode(raw);
      setState(() {
        _draft = draft;
        for (final v in widget.template.variables) {
          _controllers[v.key] = TextEditingController(text: draft.values[v.key] ?? '');
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _update(QuestionnaireDraft d) async {
    setState(() => _draft = d);
    await ref.read(kvStoreProvider).set(questionnaireDraftKey(widget.templateId), d.encode());
  }

  Future<void> _addQuestion(int section) async {
    final text = TextEditingController();
    var type = QuestionType.open;
    final options = TextEditingController();
    final q = await showDialog<Question>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nouvelle question'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: text,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Question'),
              ),
              DropdownButtonFormField<QuestionType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type de réponse'),
                items: [for (final t in QuestionType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: (v) => setLocal(() => type = v ?? type),
              ),
              if (type == QuestionType.single || type == QuestionType.multiple || type == QuestionType.scale)
                TextField(
                  controller: options,
                  decoration: const InputDecoration(labelText: 'Choix, séparés par des points-virgules',
                      hintText: 'Oui ; Non ; Je ne sais pas'),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (text.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  Question(
                    id: 'perso-${const Uuid().v4()}',
                    type: type,
                    text: text.text.trim(),
                    options: type == QuestionType.open || type == QuestionType.number
                        ? const []
                        : options.text.split(';').map((o) => o.trim()).where((o) => o.isNotEmpty).toList(),
                  ),
                );
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    options.dispose();
    if (q != null) await _update(_draft!.add(section, q));
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final t = widget.template;
    final theme = Theme.of(context);
    final result = FinalQuestionnaire.build(t, d);
    final numbers = {
      for (final s in result.sections)
        for (final q in s.questions) q.question.id: q.number,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (t.tips.isNotEmpty)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Avant de commencer', style: theme.textTheme.titleSmall),
                for (final tip in t.tips) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $tip')),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        for (final v in t.variables)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _controllers[v.key],
              decoration: InputDecoration(labelText: v.label, hintText: v.example),
              onChanged: (value) => _update(d.copyWith(values: {...d.values, v.key: value})),
            ),
          ),
        if (result.intro != null) ...[
          Text('Présentation', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(result.intro!),
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < t.sections.length; i++) ...[
          Text(FinalQuestionnaire.fill(t.sections[i].title, d.values).toUpperCase(), style: theme.textTheme.titleSmall),
          if (t.sections[i].guidance != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t.sections[i].guidance!, style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ),
          for (final q in [...t.sections[i].questions, ...?d.added[i]])
            _QuestionTile(
              number: numbers[q.id],
              question: q,
              values: d.values,
              custom: q.id.startsWith('perso-'),
              onToggle: () => _update(q.id.startsWith('perso-') ? d.deleteAdded(q.id) : d.toggle(q.id)),
            ),
          TextButton.icon(
            onPressed: () => _addQuestion(i),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter ma question'),
          ),
          const SizedBox(height: 8),
        ],
        Text('${result.questionCount} questions retenues. L\'export Word et PDF reprend ce questionnaire.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.number,
    required this.question,
    required this.values,
    required this.custom,
    required this.onToggle,
  });

  /// null = question retirée.
  final int? number;
  final Question question;
  final Map<String, String> values;
  final bool custom;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final removed = number == null;
    final style = removed
        ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
        : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${removed ? '' : '$number. '}${FinalQuestionnaire.fill(question.text, values)}', style: style),
      subtitle: Text(
        question.options.isEmpty
            ? question.type.label
            : '${question.type.label} : ${question.options.map((o) => FinalQuestionnaire.fill(o, values)).join(' / ')}',
        style: style,
      ),
      trailing: IconButton(
        tooltip: custom ? 'Supprimer' : (removed ? 'Remettre' : 'Retirer'),
        icon: Icon(custom ? Icons.delete_outline : (removed ? Icons.undo : Icons.remove_circle_outline)),
        onPressed: onToggle,
      ),
    );
  }
}
