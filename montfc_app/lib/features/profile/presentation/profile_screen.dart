import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../auth/domain/phone_number.dart';
import '../../auth/presentation/auth_controller.dart';
import 'profile_form_screen.dart';

/// Mon profil : informations, modification, déconnexion.
/// L'historique des achats est ajouté avec le module Paiement.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(authControllerProvider.notifier);
    final pending = await controller.pendingChanges();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: Text(pending > 0
            ? 'Attention : $pending modification(s) ne sont pas encore envoyées et seront perdues. '
                'Connecte-toi à internet et attends la synchronisation avant de te déconnecter.'
            : 'Tes travaux sont enregistrés sur ton compte. Tu les retrouveras en te reconnectant.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (ok != true) return;
    await controller.signOut();
    if (context.mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final p = auth.profile;
    final institutions = ref.watch(institutionsProvider).value ?? const [];
    final institution = institutions.where((i) => i['id'] == p?.institutionId).firstOrNull;
    final phone = PhoneNumber.tryParse(auth.user?.phone ?? p?.phone ?? '');

    String show(String? v) => (v == null || v.isEmpty) ? '—' : v;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(leading: const Icon(Icons.person_outline), title: Text(show(p?.fullName)), subtitle: Text(phone?.display ?? '')),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: Text(show(p?.institutionOther ?? institution?['name'] as String?)),
            subtitle: Text([p?.faculty, p?.department].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: Text(show(p?.workType?.label)),
            subtitle: Text('${p?.level?.code ?? ''} · ${p?.academicYear ?? ''}'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.profileEdit),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modifier'),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Mes achats'),
            onTap: () => context.push(Routes.store),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }
}
