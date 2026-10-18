import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/router/routes.dart';
import '../../../core/sync/sync_controller.dart';
import '../../store/domain/entitlement.dart';
import '../../store/presentation/paid_feature_gate.dart';
import '../../store/presentation/store_providers.dart';
import '../domain/apa.dart';
import '../domain/source.dart';
import '../domain/styled_text.dart';
import 'bibliography_providers.dart';
import 'styled_text_view.dart';

/// Bibliographie de l'étudiant : liste APA 7 triée, notes de bas de page,
/// copie et partage (Pack Finaliste).
class BibliographyScreen extends ConsumerWidget {
  const BibliographyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? const <Source>[];
    final order = ref.watch(bibliographyOrderProvider);
    final hasAccess =
        ref.watch(hasAccessProvider((feature: AppFeature.bibliography, resourceId: null))).value ?? false;

    Future<void> copyAll() async {
      await Clipboard.setData(ClipboardData(text: BibliographySorter.asText(sources, order)));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Bibliographie copiée. Colle-la dans ton travail.')));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bibliographie'),
        actions: [
          if (hasAccess && sources.isNotEmpty) ...[
            IconButton(tooltip: 'Copier tout', icon: const Icon(Icons.copy_all_outlined), onPressed: copyAll),
            IconButton(
              tooltip: 'Partager',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePlus.instance.share(ShareParams(
                text: BibliographySorter.asText(sources, order),
                subject: 'Bibliographie',
              )),
            ),
          ],
        ],
      ),
      floatingActionButton: hasAccess
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.sourceNew),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une source'),
            )
          : null,
      body: PaidFeatureGate(
        feature: AppFeature.bibliography,
        child: sources.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Ajoute chaque ouvrage, article ou site que tu consultes, au fur et à mesure. '
                    'MonTFC les met en forme (APA 7) et te donne les notes de bas de page.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  SegmentedButton<BibliographyOrder>(
                    segments: const [
                      ButtonSegment(value: BibliographyOrder.alphabetical, label: Text('Alphabétique')),
                      ButtonSegment(value: BibliographyOrder.byKind, label: Text('Par type')),
                    ],
                    selected: {order},
                    onSelectionChanged: (s) => ref.read(bibliographyOrderProvider.notifier).set(s.first),
                  ),
                  const SizedBox(height: 8),
                  for (final section in BibliographySorter.sections(sources, order)) ...[
                    if (section.title != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 4),
                        child: Text(section.title!.toUpperCase(), style: Theme.of(context).textTheme.titleSmall),
                      ),
                    for (final s in section.sources) _SourceTile(source: s),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SourceTile extends ConsumerWidget {
  const _SourceTile({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> delete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Supprimer cette source ?'),
          content: StyledTextView(Apa.reference(source)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
          ],
        ),
      );
      if (ok != true) return;
      await ref.read(bibliographyRepositoryProvider).delete(source.id);
      ref.invalidate(sourcesProvider);
      ref.read(syncControllerProvider.notifier).syncNow();
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: StyledTextView(Apa.reference(source)),
      onTap: () => context.push(Routes.sourceEdit(source.id)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => switch (v) {
          'note' => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => FootnoteSheet(source: source),
            ),
          'edit' => context.push(Routes.sourceEdit(source.id)),
          _ => delete(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'note', child: Text('Note de bas de page')),
          PopupMenuItem(value: 'edit', child: Text('Modifier')),
          PopupMenuItem(value: 'delete', child: Text('Supprimer')),
        ],
      ),
    );
  }
}

/// Formes de citation d'une source, à copier dans le travail.
class FootnoteSheet extends StatefulWidget {
  const FootnoteSheet({super.key, required this.source});

  final Source source;

  @override
  State<FootnoteSheet> createState() => _FootnoteSheetState();
}

class _FootnoteSheetState extends State<FootnoteSheet> {
  final _page = TextEditingController();

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = _page.text.trim().isEmpty ? null : _page.text;
    final forms = <(String, StyledText)>[
      ('Première citation (note complète)', Footnote.full(widget.source, locator: loc)),
      ('Même source que la note précédente', Footnote.ibid(locator: loc)),
      ('Source déjà citée plus haut', Footnote.short(widget.source, locator: loc)),
      ('Citation dans le texte (APA)', StyledText([StyledRun(Apa.inText(widget.source, locator: loc))])),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Note de bas de page', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _page,
              decoration: const InputDecoration(
                labelText: 'Page citée (facultatif)',
                hintText: '45, 45-47 ou art. 12',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            for (final (label, text) in forms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label, style: Theme.of(context).textTheme.labelMedium),
                subtitle: StyledTextView(text),
                trailing: IconButton(
                  tooltip: 'Copier',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text.plain));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copié.')));
                  },
                ),
              ),
            const Text(
              'Dans Word, mets en italique les passages en italique ci-dessus (titres, Ibid., op. cit.).',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
