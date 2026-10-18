import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/sync/sync_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/payment/presentation/store_billing_controller.dart';

/// Racine de l'application : thème, langue française, navigation.
class MonTfcApp extends ConsumerStatefulWidget {
  const MonTfcApp({super.key});

  @override
  ConsumerState<MonTfcApp> createState() => _MonTfcAppState();
}

class _MonTfcAppState extends ConsumerState<MonTfcApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Au retour au premier plan : l'appareil est-il toujours le seul actif ?
    // Puis synchronisation des changements éventuels.
    _lifecycle = AppLifecycleListener(onResume: () {
      ref.read(authControllerProvider.notifier).verifyDevice();
      ref.read(syncControllerProvider.notifier).syncNow();
    });
    // Variante store : achats Google Play restés en suspens (application
    // fermée pendant la validation) revérifiés à chaque connexion.
    if (ref.read(storeBillingProvider) != null) {
      ref.listenManual(authControllerProvider.select((s) => s.user?.id), (_, userId) {
        if (userId != null) ref.read(storeBillingControllerProvider.notifier).restore();
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Démarre la synchronisation (au lancement et au retour du réseau).
    ref.watch(syncControllerProvider.select((_) => null));

    // Messages ponctuels (ex. session fermée par un autre appareil).
    ref.listen(authControllerProvider.select((s) => s.notice), (_, notice) {
      if (notice == null) return;
      _messenger.currentState?.showSnackBar(
        SnackBar(content: Text(notice), duration: const Duration(seconds: 8)),
      );
      ref.read(authControllerProvider.notifier).clearNotice();
    });

    return MaterialApp.router(
      title: 'MonTFC',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
