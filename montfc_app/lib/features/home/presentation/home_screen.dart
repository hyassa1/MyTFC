import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/sync_indicator.dart';

/// Accueil : accès aux fonctions gratuites et payantes.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _free = [
    _Entry(Icons.menu_book_outlined, 'Guide de méthodologie', 'Du choix du sujet à la soutenance', Routes.guide),
    _Entry(Icons.calculate_outlined, 'Calculateur d\'échantillon', 'Formules de Slovin et de Cochran', Routes.sampleSize),
    _Entry(Icons.checklist_outlined, 'Vérification avant dépôt', 'Ne rien oublier avant de déposer', Routes.checklist),
  ];

  static const _paid = [
    _Entry(Icons.article_outlined, 'Page de garde', 'Modèles par établissement', Routes.cover),
    _Entry(Icons.format_quote_outlined, 'Bibliographie', 'APA 7 et notes de bas de page', Routes.bibliography),
    _Entry(Icons.description_outlined, 'Modèles de document', 'TFC, mémoire de licence et de master', Routes.templates),
    _Entry(Icons.quiz_outlined, 'Questionnaires d\'enquête', 'Par domaine d\'étude', Routes.questionnaires),
    _Entry(Icons.ios_share_outlined, 'Export Word et PDF', 'Partage par WhatsApp', Routes.export),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MonTFC'),
        actions: [
          const SyncIndicator(),
          IconButton(
            tooltip: 'Mon profil',
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push(Routes.profile),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Rédige ton travail, pas à pas.', style: text.titleMedium),
          const SizedBox(height: 16),
          Text('Gratuit', style: text.labelLarge),
          const SizedBox(height: 8),
          ..._free.map((e) => _EntryTile(entry: e)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Outils du finaliste', style: text.labelLarge)),
              TextButton(onPressed: () => context.push(Routes.store), child: const Text('Voir les offres')),
            ],
          ),
          ..._paid.map((e) => _EntryTile(entry: e)),
        ],
      ),
    );
  }
}

class _Entry {
  const _Entry(this.icon, this.title, this.subtitle, this.route);
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final _Entry entry;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(entry.icon),
          title: Text(entry.title),
          subtitle: Text(entry.subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(entry.route),
        ),
      );
}
