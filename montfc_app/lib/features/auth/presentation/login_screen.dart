import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../domain/auth_failure.dart';
import '../domain/phone_number.dart';
import 'auth_controller.dart';

/// Connexion, étape 1 : saisie du numéro de téléphone.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.redirectTo});

  /// Page à ouvrir après la connexion (ex. une fonction payante).
  final String? redirectTo;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (PhoneNumber.tryParse(_phone.text) == null) {
      setState(() => _error = AuthFailure.invalidPhone.message);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final phone = await ref.read(authControllerProvider.notifier).sendCode(_phone.text);
      if (!mounted) return;
      context.push(Routes.otp, extra: (phone: phone, redirectTo: widget.redirectTo));
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final operator = PhoneNumber.tryParse(_phone.text)?.operator;
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Ton numéro de téléphone', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Tu vas recevoir un code par SMS. Un compte correspond à un numéro.'),
          const SizedBox(height: 24),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-.()]'))],
            decoration: InputDecoration(
              labelText: 'Numéro',
              hintText: '0812345678',
              prefixIcon: const Icon(Icons.phone_android),
              helperText: operator?.label,
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: _sending
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Recevoir le code'),
          ),
        ],
      ),
    );
  }
}
