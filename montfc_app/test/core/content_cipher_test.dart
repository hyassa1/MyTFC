import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/security/content_cipher.dart';
import 'package:montfc/core/security/key_store.dart';

void main() {
  group('ContentCipher', () {
    test('chiffre puis déchiffre un JSON', () async {
      final cipher = ContentCipher(MemorySecretStore());
      final value = {'layout': 'secret', 'n': 3};
      final encrypted = await cipher.encryptJson(value);

      expect(encrypted.contains('secret'), isFalse, reason: 'le texte clair ne doit pas apparaître');
      expect(await cipher.decryptJson(encrypted), value);
    });

    test('deux chiffrements du même texte diffèrent (nonce aléatoire)', () async {
      final cipher = ContentCipher(MemorySecretStore());
      expect(await cipher.encrypt('abc'), isNot(await cipher.encrypt('abc')));
    });

    test('la clé est conservée et réutilisée', () async {
      final store = MemorySecretStore();
      final encrypted = await ContentCipher(store).encrypt('bonjour');
      expect(await ContentCipher(store).decrypt(encrypted), 'bonjour');
    });

    test('un contenu altéré est refusé', () async {
      final cipher = ContentCipher(MemorySecretStore());
      final encrypted = await cipher.encrypt('bonjour');
      final tampered = '${encrypted.substring(0, 20)}${encrypted[20] == 'A' ? 'B' : 'A'}${encrypted.substring(21)}';
      expect(() => cipher.decrypt(tampered), throwsA(isA<ContentCipherException>()));
    });

    test('un autre appareil (autre clé) ne peut pas lire le contenu', () async {
      final encrypted = await ContentCipher(MemorySecretStore()).encrypt('bonjour');
      expect(() => ContentCipher(MemorySecretStore()).decrypt(encrypted),
          throwsA(isA<ContentCipherException>()));
    });
  });
}
