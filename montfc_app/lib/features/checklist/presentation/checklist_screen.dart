import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/checklist_repository.dart';
import '../domain/checklist_items.dart';

final checklistRepositoryProvider =
    Provider<ChecklistRepository>((ref) => ChecklistRepository(ref.watch(localDatabaseProvider)));

/// Cases cochées (identifiants), enregistrées à chaque changement.
class ChecklistController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => ref.watch(checklistRepositoryProvider).checkedIds();

  Future<void> toggle(String id, bool checked) async {
    final current = {...?state.value};
    checked ? current.add(id) : current.remove(id);
    state = AsyncData(current);
    await ref.read(checklistRepositoryProvider).setChecked(id, checked);
  }

  Future<void> reset() async {
    state = const AsyncData({});
    await ref.read(checklistRepositoryProvider).reset();
  }
}

final checklistControllerProvider =
    AsyncNotifierProvider<ChecklistController, Set<String>>(ChecklistController.new);

/// Liste de vérification avant dépôt (gratuite, hors ligne).
class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({super.key});

  static final int _total = depositChecklist.fold(0, (n, s) => n + s.items.length);

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tout décocher ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tout décocher')),
        ],
      ),
    );
    if (ok == true) await ref.read(checklistControllerProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = ref.watch(checklistControllerProvider).value ?? const <String>{};
    final done = depositChecklist.expand((s) => s.items).where((i) => checked.contains(i.id)).length;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vérification avant dépôt'),
        actions: [
          IconButton(
            tooltip: 'Tout décocher',
            icon: const Icon(Icons.restart_alt),
            onPressed: done == 0 ? null : () => _confirmReset(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$done sur $_total points vérifiés', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _total == 0 ? 0 : done / _total),
              ],
            ),
          ),
          for (final section in depositChecklist) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(section.title, style: theme.textTheme.labelLarge),
            ),
            for (final item in section.items)
              CheckboxListTile(
                value: checked.contains(item.id),
                title: Text(item.label),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => ref.read(checklistControllerProvider.notifier).toggle(item.id, v ?? false),
              ),
          ],
        ],
      ),
    );
  }
}
