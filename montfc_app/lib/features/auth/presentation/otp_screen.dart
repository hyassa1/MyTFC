import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../domain/auth_failure.dart';
import '../domain/phone_number.dart';
import 'auth_controller.dart';

/// Connexion, étape 2 : saisie du code reçu par SMS.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone, this.redirectTo});

  final PhoneNumber phone;
  final String? redirectTo;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _resendDelay = 60;

  final _code = TextEditingController();
  String? _error;
  bool _verifying = false;
  int _secondsLeft = _resendDelay;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendDelay);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) t.cancel();
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).verifyCode(widget.phone, _code.text);
      if (!mounted) return;
      // Si le profil est incomplet, la garde de navigation ouvre d'abord la
      // création du profil, puis cette page.
      context.go(widget.redirectTo ?? Routes.home);
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authControllerProvider.notifier).sendCode(widget.phone.e164);
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nouveau code envoyé.')));
      }
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Code de vérification')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Saisis le code à 6 chiffres envoyé au ${widget.phone.display}.'),
            const SizedBox(height: 24),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
              decoration: InputDecoration(hintText: '••••••', errorText: _error, errorMaxLines: 3),
              onChanged: (v) {
                if (v.length == 6 && !_verifying) _verify();
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _verifying ? null : _verify,
              child: _verifying
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Valider'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _secondsLeft > 0 ? null : _resend,
              child: Text(_secondsLeft > 0 ? 'Renvoyer le code dans $_secondsLeft s' : 'Renvoyer le code'),
            ),
            TextButton(onPressed: () => context.pop(), child: const Text('Changer de numéro')),
          ],
        ),
      );
}
