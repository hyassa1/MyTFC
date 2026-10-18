import 'bootstrap.dart';
import 'core/config/flavor.dart';

/// Point d'entrée par défaut (`flutter run` sans --flavor) : variante directe.
/// Pour publier, utiliser main_store.dart ou main_direct.dart (voir README).
void main() => bootstrap(AppFlavor.direct);
