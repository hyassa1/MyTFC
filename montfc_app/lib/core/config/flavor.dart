/// Variante de l'application (voir ARCHITECTURE.md §2).
///
/// * [store]  : distribuée par Google Play / App Store. Les achats passent
///   uniquement par la facturation du store ; aucune mention du paiement web.
/// * [direct] : APK distribué hors store. Paiement mobile money intégré.
enum AppFlavor {
  store,
  direct;

  /// Nom utilisé côté serveur (`user_devices.app_flavor`, `app_settings`).
  String get code => name;
}
