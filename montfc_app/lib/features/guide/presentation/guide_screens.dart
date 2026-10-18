import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/content/content_kinds.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/sync/sync_controller.dart';

/// Chapitres du guide en cache local (gratuit, lisible hors ligne).
/// Rechargés automatiquement après chaque synchronisation.
final guideChaptersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(contentStoreProvider).list(ContentKind.guideChapter);
});

/// Liste des chapitres du guide de méthodologie.
class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(guideChaptersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Guide de méthodologie')),
      body: chapters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Impossible de lire le guide.')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Le guide sera disponible après ta première connexion à internet.',
                      textAlign: TextAlign.center),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = list[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(c['title'] as String),
                    subtitle: c['summary'] == null ? null : Text(c['summary'] as String),
                    onTap: () => context.push(Routes.guideChapter(c['slug'] as String)),
                  );
                },
              ),
      ),
    );
  }
}

/// Lecture d'un chapitre (Markdown), avec passage au chapitre suivant.
class GuideChapterScreen extends ConsumerWidget {
  const GuideChapterScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(guideChaptersProvider).value ?? const [];
    final index = chapters.indexWhere((c) => c['slug'] == slug);
    if (index < 0) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Chapitre introuvable.')),
      );
    }
    final chapter = chapters[index];
    final next = index + 1 < chapters.length ? chapters[index + 1] : null;

    return Scaffold(
      appBar: AppBar(title: Text(chapter['title'] as String)),
      body: Markdown(
        data: chapter['body_md'] as String? ?? '',
        selectable: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      ),
      bottomNavigationBar: next == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: () => context.pushReplacement(Routes.guideChapter(next['slug'] as String)),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('Chapitre suivant : ${next['title']}', overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
    );
  }
}
