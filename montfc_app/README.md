# MonTFC — application mobile (Flutter)

Le guide complet (installation, clés, publication) est dans le [README à la racine](../README.md).

Commandes utiles :

```bash
flutter pub get
flutter test                                   # tests unitaires
flutter run --dart-define-from-file=env/dev.json   # copier env/example.json en env/dev.json
flutter build apk --flavor direct -t lib/main_direct.dart --split-per-abi --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/prod.json
flutter build appbundle --flavor store -t lib/main_store.dart --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/prod.json
```

Le contenu gratuit embarqué (`assets/seed/content.json`) se régénère depuis `supabase/seed.sql` :

```bash
bash ../supabase/tests/local/run_db_tests.sh --export-seed assets/seed/content.json
```
