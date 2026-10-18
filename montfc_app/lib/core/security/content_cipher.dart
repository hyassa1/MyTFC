import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'key_store.dart';

/// Chiffrement local du contenu payant (AES-256-GCM).
///
/// La clé est générée aléatoirement au premier usage et conservée dans le
/// Keystore Android / Keychain iOS ([SecretStore]). Elle ne quitte jamais
/// l'appareil : si l'application est réinstallée, le contenu payant est
/// simplement re-téléchargé depuis le serveur (qui vérifie les droits).
///
/// Format chiffré : base64( nonce(12) | texte chiffré | mac(16) ).
class ContentCipher {
  ContentCipher(this._secrets);

  static const _keyName = 'content_key_v1';

  final SecretStore _secrets;
  final AesGcm _algorithm = AesGcm.with256bits();
  SecretKey? _key;

  Future<SecretKey> _loadKey() async {
    final cached = _key;
    if (cached != null) return cached;

    final stored = await _secrets.read(_keyName);
    if (stored != null) {
      return _key = SecretKey(base64Decode(stored));
    }
    final created = await _algorithm.newSecretKey();
    await _secrets.write(_keyName, base64Encode(await created.extractBytes()));
    return _key = created;
  }

  Future<String> encrypt(String plainText) async {
    final box = await _algorithm.encrypt(utf8.encode(plainText), secretKey: await _loadKey());
    return base64Encode(box.concatenation());
  }

  /// Lève [ContentCipherException] si le texte a été altéré ou si la clé a changé.
  Future<String> decrypt(String cipherText) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(cipherText),
        nonceLength: _algorithm.nonceLength,
        macLength: _algorithm.macAlgorithm.macLength,
      );
      return utf8.decode(await _algorithm.decrypt(box, secretKey: await _loadKey()));
    } on SecretBoxAuthenticationError {
      throw const ContentCipherException('Contenu local altéré ou illisible.');
    } on FormatException {
      throw const ContentCipherException('Contenu local illisible.');
    }
  }

  Future<String> encryptJson(Object? value) => encrypt(jsonEncode(value));

  Future<Object?> decryptJson(String cipherText) async => jsonDecode(await decrypt(cipherText));
}

class ContentCipherException implements Exception {
  const ContentCipherException(this.message);
  final String message;

  @override
  String toString() => 'ContentCipherException: $message';
}
