import 'bootstrap.dart';
import 'core/config/flavor.dart';

/// Variante Google Play / App Store : achats par la facturation du store.
/// flutter build appbundle --flavor store -t lib/main_store.dart
void main() => bootstrap(AppFlavor.store);
