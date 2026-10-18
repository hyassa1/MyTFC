import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Bloque les captures et l'enregistrement d'écran tant qu'un écran payant
/// est affiché (FLAG_SECURE sur Android, voir MainActivity.kt).
///
/// Utilisation : envelopper le contenu de l'écran payant.
/// ```dart
/// SecureScreen(child: CoverPreview(...))
/// ```
/// Un compteur gère les écrans imbriqués : le drapeau n'est retiré qu'à la
/// fermeture du dernier écran protégé.
///
/// iOS ne permet pas d'interdire les captures ; la protection y sera limitée
/// au masquage pendant l'enregistrement d'écran (prévu au module Page de garde).
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  static const MethodChannel _channel = MethodChannel('cd.montfc/secure_screen');
  static int _activeCount = 0;

  @visibleForTesting
  static int get activeCount => _activeCount;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> _acquire() async {
    _activeCount++;
    if (_activeCount == 1 && _supported) {
      await _channel.invokeMethod<void>('enable');
    }
  }

  static Future<void> _release() async {
    if (_activeCount == 0) return;
    _activeCount--;
    if (_activeCount == 0 && _supported) {
      await _channel.invokeMethod<void>('disable');
    }
  }

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    SecureScreen._acquire();
  }

  @override
  void dispose() {
    SecureScreen._release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
