import 'bootstrap.dart';
import 'core/config/flavor.dart';

/// Variante APK direct (hors store) : paiement mobile money intégré.
/// flutter build apk --flavor direct -t lib/main_direct.dart --split-per-abi
void main() => bootstrap(AppFlavor.direct);
