import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/sync_controller.dart';
import '../../store/domain/entitlement.dart';
import '../../store/presentation/paid_feature_gate.dart';
import '../../works/data/works_providers.dart';
import '../domain/apa.dart';
import '../domain/source.dart';
import 'bibliography_providers.dart';
import 'styled_text_view.dart';

/// Ajout ou modification d'une source, avec l'aperçu APA en direct.
class SourceFormScreen extends ConsumerWidget {
  const SourceFormScreen({super.key, this.sourceId});

  /// null = nouvelle source.
  final String? sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(sourceId == null ? 'Nouvelle source' : 'Modifier la source')),
      body: PaidFeatureGate(
        feature: AppFeature.bibliography,
        child: sources.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('Impossible de lire tes sources.')),
          data: (list) {
            final existing = sourceId == null ? null : list.where((s) => s.id == sourceId).firstOrNull;
            if (sourceId != null && existing == null) return const Center(child: Text('Source introuvable.'));
            return _SourceForm(initial: existing);
          },
        ),
      ),
    );
  }
}

/// Champs texte du formulaire (clé = clé JSON de la source).
const _textKeys = [
  'organization', 'year', 'title', 'subtitle', 'edition', 'publisher', 'place', 'chapter_title', 'pages',
  'journal', 'volume', 'issue', 'doi', 'url', 'degree', 'institution', 'site_name',
];

class _SourceForm extends ConsumerStatefulWidget {
  const _SourceForm({this.initial});

  final Source? initial;

  @override
  ConsumerState<_SourceForm> createState() => _SourceFormState();
}

class _SourceFormState extends ConsumerState<_SourceForm> {
  late SourceKind _kind = widget.initial?.kind ?? SourceKind.book;
  late bool _collective = widget.initial?.organization != null;
  late bool _chapter = widget.initial?.isChapter ?? false;
  late final List<(TextEditingController, TextEditingController)> _authors = _people(widget.initial?.authors);
  late final List<(TextEditingController, TextEditingController)> _editors = _people(widget.initial?.editors);
  late final Map<String, TextEditingController> _text = {
    for (final k in _textKeys) k: TextEditingController(text: widget.initial?.toJson()[k]?.toString() ?? ''),
  };
  late DateTime? _published = widget.initial?.publishedDate;
  late DateTime? _accessed = widget.initial?.accessedDate ?? (widget.initial == null ? DateTime.now() : null);
  Map<String, String> _errors = {};

  static List<(TextEditingController, TextEditingController)> _people(List<Person>? list) => [
        for (final p in (list == null || list.isEmpty) ? const [Person(last: '')] : list)
          (TextEditingController(text: p.last), TextEditingController(text: p.first)),
      ];

  @override
  void dispose() {
    for (final c in [..._text.values, for (final (a, b) in [..._authors, ..._editors]) ...[a, b]]) {
      c.dispose();
    }
    super.dispose();
  }

  Source _source() {
    String? t(String k) => _text[k]!.text.trim().isEmpty ? null : _text[k]!.text.trim();
    List<Person> people(List<(TextEditingController, TextEditingController)> rows) => [
          for (final (last, first) in rows)
            if (last.text.trim().isNotEmpty) Person(last: last.text.trim(), first: first.text.trim()),
        ];
    final isBook = _kind == SourceKind.book;
    return Source(
      id: widget.initial?.id ?? const Uuid().v4(),
      kind: _kind,
      workId: widget.initial?.workId ?? ref.read(currentWorkProvider).value?.id,
      organization: _collective ? t('organization') : null,
      authors: _collective ? const [] : people(_authors),
      year: t('year'),
      title: t('title') ?? '',
      subtitle: t('subtitle'),
      edition: isBook ? t('edition') : null,
      publisher: isBook ? t('publisher') : null,
      place: isBook ? t('place') : null,
      chapterTitle: isBook && _chapter ? t('chapter_title') : null,
      editors: isBook && _chapter ? people(_editors) : const [],
      pages: (isBook && _chapter) || _kind == SourceKind.article || _kind == SourceKind.legalText ? t('pages') : null,
      journal: _kind == SourceKind.article || _kind == SourceKind.legalText ? t('journal') : null,
      volume: _kind == SourceKind.article ? t('volume') : null,
      issue: _kind == SourceKind.article || _kind == SourceKind.legalText ? t('issue') : null,
      doi: _kind == SourceKind.article ? t('doi') : null,
      url: t('url'),
      degree: _kind == SourceKind.thesis ? t('degree') : null,
      institution: _kind == SourceKind.thesis ? t('institution') : null,
      siteName: _kind == SourceKind.website ? t('site_name') : null,
      publishedDate: _kind == SourceKind.website ? _published : null,
      accessedDate: _kind == SourceKind.website ? _accessed : null,
    );
  }

  Future<void> _save() async {
    final source = _source();
    final errors = source.validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    await ref.read(bibliographyRepositoryProvider).save(source);
    ref.invalidate(sourcesProvider);
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) context.pop();
  }

  Widget _field(String key, String label, {String? hint, TextInputType? keyboard, int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _text[key],
          keyboardType: keyboard,
          maxLines: maxLines,
          minLines: 1,
          textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(labelText: label, hintText: hint, errorText: _errors[key]),
          onChanged: (_) => setState(() => _errors = Map.of(_errors)..remove(key)),
        ),
      );

  Widget _peopleEditor(String title, List<(TextEditingController, TextEditingController)> rows, {String? error}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          for (var i = 0; i < rows.length; i++)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: rows[i].$1,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nom'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: rows[i].$2,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Prénom(s)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (rows.length > 1)
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() => rows.removeAt(i)),
                  ),
              ],
            ),
          if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton.icon(
            onPressed: () => setState(() => rows.add((TextEditingController(), TextEditingController()))),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Ajouter une personne'),
          ),
        ],
      );

  Future<void> _pickDate(bool accessed) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: now,
      initialDate: (accessed ? _accessed : _published) ?? now,
    );
    if (picked != null) setState(() => accessed ? _accessed = picked : _published = picked);
  }

  @override
  Widget build(BuildContext context) {
    final preview = Apa.reference(_source());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<SourceKind>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Type de source'),
          items: [for (final k in SourceKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
          onChanged: (k) => setState(() {
            _kind = k ?? _kind;
            _errors = {};
          }),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auteur collectif (ministère, entreprise, ONG…)'),
          value: _collective,
          onChanged: (v) => setState(() => _collective = v),
        ),
        if (_collective)
          _field('organization', 'Nom de l\'organisation', hint: 'Banque centrale du Congo')
        else ...[
          _peopleEditor('Auteurs (dans l\'ordre de la couverture)', _authors),
          const SizedBox(height: 8),
        ],
        if (_kind == SourceKind.book)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Chapitre d\'un ouvrage collectif'),
            value: _chapter,
            onChanged: (v) => setState(() => _chapter = v),
          ),
        if (_kind == SourceKind.book && _chapter) _field('chapter_title', 'Titre du chapitre'),
        _field('title', switch (_kind) {
          SourceKind.book when _chapter => 'Titre de l\'ouvrage collectif',
          SourceKind.legalText => 'Intitulé complet du texte',
          SourceKind.website => 'Titre de la page',
          _ => 'Titre',
        }, hint: _kind == SourceKind.legalText ? 'Loi n° 18/035 du 13 décembre 2018 fixant…' : null, maxLines: 3),
        if (_kind != SourceKind.legalText) _field('subtitle', 'Sous-titre (facultatif)'),
        _field('year', 'Année (vide si sans date)', keyboard: TextInputType.number),
        if (_kind == SourceKind.book) ...[
          if (_chapter) ...[
            _peopleEditor('Directeurs de l\'ouvrage (dir.)', _editors, error: _errors['editors']),
            _field('pages', 'Pages du chapitre', hint: '45-67'),
          ],
          _field('edition', 'Édition (vide si 1re)', hint: '2', keyboard: TextInputType.number),
          _field('publisher', 'Éditeur', hint: 'Presses universitaires de Kinshasa'),
          _field('place', 'Lieu d\'édition (pour les notes)', hint: 'Kinshasa'),
        ],
        if (_kind == SourceKind.article) ...[
          _field('journal', 'Revue'),
          _field('volume', 'Volume', keyboard: TextInputType.number),
          _field('issue', 'Numéro'),
          _field('pages', 'Pages de l\'article', hint: '101-120'),
          _field('doi', 'DOI (facultatif)', hint: '10.1234/abcd', keyboard: TextInputType.url),
        ],
        if (_kind == SourceKind.thesis) ...[
          _field('degree', 'Type de travail', hint: 'Mémoire de licence'),
          _field('institution', 'Établissement', hint: 'Université de Kinshasa'),
        ],
        if (_kind == SourceKind.legalText) ...[
          _field('journal', 'Publication', hint: 'Journal officiel de la République démocratique du Congo'),
          _field('issue', 'Numéro du Journal officiel', hint: 'spécial'),
          _field('pages', 'Colonnes ou pages (facultatif)'),
        ],
        if (_kind == SourceKind.website) ...[
          _field('site_name', 'Nom du site'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date de publication (facultatif)'),
            subtitle: Text(_published == null ? 'Non indiquée' : frenchDate(_published!)),
            onTap: () => _pickDate(false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date de consultation'),
            subtitle: Text(_accessed == null ? 'Non indiquée' : frenchDate(_accessed!)),
            onTap: () => _pickDate(true),
          ),
        ],
        if (_kind != SourceKind.thesis || _text['url']!.text.isNotEmpty)
          _field('url', _kind == SourceKind.website ? 'Adresse de la page' : 'Lien (facultatif)',
              hint: 'https://', keyboard: TextInputType.url),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aperçu APA 7', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                StyledTextView(preview),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
