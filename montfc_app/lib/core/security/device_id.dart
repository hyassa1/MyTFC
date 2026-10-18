import 'package:uuid/uuid.dart';

import 'key_store.dart';

/// Identifiant stable de l'installation, utilisé pour la règle « un compte =
/// un appareil actif ».
///
/// On génère un UUID au premier lancement et on le garde dans le stockage
/// sécurisé : aucune permission sensible n'est demandée (pas d'IMEI). Une
/// réinstallation produit un nouvel identifiant, ce qui revient à changer
/// d'appareil (l'ancien est alors déconnecté par le serveur).
class DeviceIdProvider {
  DeviceIdProvider(this._secrets);

  static const _keyName = 'device_id_v1';

  final SecretStore _secrets;
  String? _cached;

  Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    final stored = await _secrets.read(_keyName);
    if (stored != null) return _cached = stored;
    final created = const Uuid().v4();
    await _secrets.write(_keyName, created);
    return _cached = created;
  }
}
