# MonTFC — guide d'installation et de publication

MonTFC aide les finalistes congolais (Kinshasa d'abord) à **rédiger eux-mêmes** leur TFC ou mémoire :
méthodologie, modèles, mise en forme. L'application ne fournit jamais de travail déjà rédigé : les modèles
contiennent des plans et des consignes, et les exports ne portent que des repères gris
« [Consigne à effacer : …] » que l'étudiant remplace par son propre texte.

| Dossier | Contenu |
|---|---|
| `montfc_app/` | Application Flutter (Android d'abord, iOS ensuite), Riverpod, hors ligne |
| `supabase/` | Base PostgreSQL (schéma, RLS, fonctions), Edge Functions (paiement, Google Play), données de démo, tests |
| `web/` | Panneau d'administration (`/admin`) et page de paiement mobile money (`/payer`), React + Vite |
| `ARCHITECTURE.md` | Choix d'architecture validés et schéma de la base |
| `exemples-export/` | Exemples de fichiers produits par l'application (DOCX et PDF) |

---

## 1. Prérequis

- Flutter 3.47 (stable) ou plus récent, Android SDK récent, Java 17.
- Node.js 20 ou plus (projet web).
- Un projet Supabase (offre gratuite suffisante pour démarrer) et la CLI Supabase.
- Deno 2 (seulement pour lancer les tests des Edge Functions).
- PostgreSQL 15 ou plus en local (seulement pour les tests de la base sans Docker).

---

## 2. Supabase

### 2.1 Créer la base

```bash
cd supabase
supabase login
supabase link --project-ref VOTRE_REF
supabase db push                       # applique migrations/ (schéma, fonctions, RLS, tâche planifiée)
psql "$(supabase db url)" -f seed.sql  # données de démo (à faire une fois, sur un projet vide)
```

Les données de démo contiennent : 3 chapitres du guide, 3 pages de garde (UNIKIN, UPN, générique),
1 modèle de mémoire, 1 modèle de questionnaire (gestion), 4 offres avec leurs prix en CDF et en USD,
des établissements de Kinshasa et les réglages de l'application.

La migration `20261018000004_cron.sql` active `pg_cron` pour faire expirer toutes les 5 minutes les
paiements non confirmés. Si `pg_cron` n'est pas activé sur ton projet : *Database > Extensions > pg_cron*.

En local : `supabase start` puis `supabase db reset` (applique les migrations et `seed.sql`).

### 2.2 Connexion par SMS (Twilio)

Dans le tableau de bord : *Authentication > Sign In / Providers > Phone* :

1. Activer **Phone** et choisir **Twilio** (ou Twilio Verify).
2. Renseigner `Account SID`, `Auth Token` et `Message Service SID` (ces clés restent chez Supabase,
   jamais dans l'application).
3. Modèle du SMS : `MonTFC : ton code est {{ .Code }}. Ne le partage avec personne.`
4. *Authentication > Sessions* : durée du jeton d'accès 900 s (15 min). C'est ce qui limite la durée
   pendant laquelle un ancien téléphone garde l'accès après la règle « un seul appareil actif ».
5. Désactiver l'inscription par e-mail.

Pour un fournisseur SMS local plus tard (Africa's Talking, agrégateur congolais), utiliser le
« Send SMS Hook » de Supabase : l'application ne change pas.

Le numéro de test `243810000001` / code `123456` déclaré dans `config.toml` ne sert qu'en local.
**Ne pas le déclarer sur le projet de production.**

### 2.3 Secrets des Edge Functions

Toutes les clés sont des **secrets côté serveur**. Aucune ne va dans l'application ni dans le site web.

```bash
supabase secrets set \
  MONTFC_ENV=production \
  PAYMENT_PROVIDER=flexpay \
  FLEXPAY_MERCHANT=... \
  FLEXPAY_TOKEN=... \
  PAYMENT_WEBHOOK_SECRET="$(openssl rand -hex 32)" \
  GOOGLE_PLAY_PACKAGE_NAME=cd.montfc.app \
  GOOGLE_PLAY_SERVICE_ACCOUNT="$(cat compte-de-service.json)"
```

| Variable | Rôle |
|---|---|
| `MONTFC_ENV` | `production` en production. Interdit l'agrégateur simulé et les achats de test Google Play. |
| `PAYMENT_PROVIDER` | `flexpay` (réel) ou `mock` (simulé, refusé si `MONTFC_ENV=production`). |
| `FLEXPAY_MERCHANT`, `FLEXPAY_TOKEN` | Identifiants marchand FlexPay. |
| `FLEXPAY_BASE_URL`, `FLEXPAY_CHECK_URL` | Facultatif : adresses de l'API FlexPay si elles diffèrent des valeurs par défaut (bac à sable). |
| `PAYMENT_WEBHOOK_SECRET` | Secret ajouté à l'adresse de rappel ; tout rappel sans ce secret est refusé. |
| `PAYMENT_CALLBACK_URL` | Facultatif : adresse de rappel (par défaut `…/functions/v1/payment-webhook`). |
| `PAYMENT_TTL_MINUTES` | Facultatif : délai de confirmation sur le téléphone (10 par défaut). |
| `GOOGLE_PLAY_PACKAGE_NAME` | Identifiant de l'application sur le Play Store (`cd.montfc.app`). |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | Contenu JSON de la clé du compte de service Google (voir §5.3). |
| `GOOGLE_PLAY_ACCEPT_TEST_PURCHASES` | `true` pour accepter les achats des testeurs de licence en production (à éviter). |

`SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` sont fournis automatiquement aux fonctions par Supabase.

### 2.4 Déployer les fonctions

```bash
supabase functions deploy claim-device
supabase functions deploy payment-init
supabase functions deploy payment-status
supabase functions deploy payment-webhook --no-verify-jwt   # appelée par FlexPay
supabase functions deploy verify-store-purchase
```

Chez FlexPay, déclarer l'adresse de rappel indiquée par `PAYMENT_CALLBACK_URL` (ou la valeur par défaut).
Le statut d'un paiement n'est jamais pris tel quel du rappel : le serveur revérifie auprès de FlexPay
avant d'accorder le droit, et un même paiement ne peut accorder qu'un seul droit (idempotence).

### 2.5 Créer un compte administrateur

1. Se connecter une fois sur `/admin` (ou dans l'application) avec son numéro, pour créer le compte.
2. Dans *SQL Editor* :

```sql
insert into public.app_admins (user_id, role)
select id, 'admin' from auth.users where phone = '243812345678';   -- sans le « + »
```

Rôles : `admin` voit tout (tableau de bord, ventes, prix, codes promo, ambassadeurs, étudiants, réglages) ;
`editor` ne voit que les contenus. **Limite V1** : cette séparation est faite par l'interface ; la base
autorise les deux rôles à écrire. Ne donner le rôle `editor` qu'à des personnes de confiance.

La session du panneau web n'est pas soumise à la règle « un appareil actif » de l'application. En
revanche, se connecter à l'application avec le même numéro déconnecte les autres sessions, y compris le
panneau : il suffit de se reconnecter.

---

## 3. Application mobile (Flutter)

### 3.1 Configuration

```bash
cd montfc_app
cp env/example.json env/prod.json    # renseigner l'adresse du projet et la clé PUBLIQUE
flutter pub get
```

`env/*.json` ne contient que `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY` (clé publique, protégée par la
RLS). Ces fichiers sont exclus de git. Ne jamais y mettre la clé `service_role` ni une clé FlexPay.

### 3.2 Deux variantes

| Variante | Identifiant | Paiement | Distribution |
|---|---|---|---|
| `store` | `cd.montfc.app` | Google Play Billing uniquement | Play Store |
| `direct` | `cd.montfc.app.direct` | Mobile money (FlexPay) | APK téléchargé depuis le site |

Pourquoi : les règles de Google Play imposent sa facturation pour les contenus numériques vendus dans
une application du Play Store. La variante Play Store ne propose donc **aucun** lien ni bouton de paiement
mobile money. Le réglage `payment_channels` (panneau *Réglages*) permettra d'ouvrir d'autres moyens sans
republier si Google autorise un jour la facturation alternative en RDC (voir `ARCHITECTURE.md` §2).

```bash
# Développement
flutter run --flavor direct -t lib/main_direct.dart --dart-define-from-file=env/dev.json

# APK direct (un fichier par architecture, plus léger)
flutter build apk --flavor direct -t lib/main_direct.dart --release \
  --split-per-abi --obfuscate --split-debug-info=build/symbols \
  --dart-define-from-file=env/prod.json

# Bundle Play Store
flutter build appbundle --flavor store -t lib/main_store.dart --release \
  --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/prod.json
```

### 3.3 Taille de l'APK (objectif : moins de 20 Mo)

```bash
flutter build apk --flavor direct -t lib/main_direct.dart --release --split-per-abi \
  --analyze-size --target-platform android-arm64 --dart-define-from-file=env/prod.json
ls -lh build/app/outputs/flutter-apk/
```

Leviers déjà en place : `--split-per-abi`, R8 (`minifyEnabled` + `shrinkResources`), pas de SDK lourd,
une seule police embarquée (Liberation Serif, 4 fichiers, environ 1,5 Mo), icônes Material réduites
automatiquement. L'APK n'a pas pu être construit dans l'environnement de développement (accès aux
serveurs Google bloqué) : **mesurer la taille au premier build**. Sur le Play Store, le bundle permet à
Google d'envoyer à chaque téléphone uniquement ce dont il a besoin.

### 3.4 Clé de signature

```bash
keytool -genkey -v -keystore ~/montfc-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Créer `android/key.properties` (jamais commité) :

```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/chemin/vers/montfc-upload.jks
```

Sans ce fichier, la version de publication est signée avec la clé de debug (utile pour tester, refusée
par le Play Store). Garder une sauvegarde de la clé : la perdre empêche de publier une mise à jour de
l'APK direct.

### 3.5 Contenu gratuit embarqué

`assets/seed/content.json` est le contenu gratuit disponible dès le premier lancement, même sans
connexion. Le régénérer après avoir modifié `supabase/seed.sql` :

```bash
bash ../supabase/tests/local/run_db_tests.sh --export-seed assets/seed/content.json
```

---

## 4. Site web (administration et paiement)

```bash
cd web
cp .env.example .env.local    # VITE_SUPABASE_URL et VITE_SUPABASE_PUBLISHABLE_KEY (clé publique)
npm ci
npm run dev                   # http://localhost:5173/admin et /payer
npm test                      # tests
npm run build                 # produit dist/
```

Hébergement statique (Netlify, Vercel, Cloudflare Pages) : publier `dist/` et rediriger toutes les
adresses vers `index.html` (application à page unique). Le fichier `public/_redirects` fourni le fait
sur Netlify et Cloudflare Pages. Ajouter l'adresse du site dans *Authentication > URL Configuration*.

- **`/payer`** : page publique de paiement mobile money (même compte que l'application, connexion par
  SMS). Lien utilisable depuis la variante directe ou partagé par un ambassadeur :
  `https://votre-site/payer?offre=PACK_FINALISTE`, ou `?offre=QUESTIONNAIRE&modele=<id>` pour un modèle précis.
- **`/admin`** : tableau de bord (inscrits, achats par jour, revenus, revenus par université, commissions
  dues et « Marquer payé »), contenus (guide, pages de garde, modèles, questionnaires, établissements),
  offres et prix, codes promo, ambassadeurs, recherche d'un étudiant (droits, paiements, ajout manuel
  d'un droit) et réglages.

Supprimer un contenu le retire (suppression douce) : il disparaît des téléphones à la synchronisation
suivante, sans casser les achats passés.

---

## 5. Publication sur le Play Store

### 5.1 Fiche et règles

1. Créer l'application dans la Play Console avec l'identifiant `cd.montfc.app`.
2. Remplir : description en français, captures, icône, politique de confidentialité (numéro de téléphone,
   profil académique, historique d'achats ; aucune donnée revendue), questionnaire « Sécurité des
   données », classification du contenu, public cible (adultes).
3. Indiquer dans la description que l'application aide à rédiger et ne fournit pas de travaux rédigés.

### 5.2 Produits intégrés

*Monétiser > Produits > Produits intégrés à l'application*. Créer ces produits **consommables**
(identifiants déjà enregistrés dans la table `products`) :

| Identifiant Play | Offre |
|---|---|
| `montfc_cover_page` | Pages de garde (toutes) |
| `montfc_doc_template` | Un modèle de document |
| `montfc_questionnaire` | Un modèle de questionnaire |
| `montfc_pack_finaliste` | Pack Finaliste (12 mois) |

Ils sont consommables pour qu'un étudiant puisse acheter plusieurs modèles et renouveler son pack. Le
droit est créé et gardé par **notre serveur** après vérification auprès de Google ; l'achat n'est
consommé qu'ensuite (sinon Google le rembourse automatiquement au bout de 3 jours). Fixer les prix Play
en cohérence avec ceux du panneau (Google peut arrondir selon le pays).

### 5.3 Compte de service pour la vérification des achats

1. Google Cloud Console : créer un compte de service, activer l'API **Google Play Android Developer**,
   télécharger sa clé JSON.
2. Play Console > *Utilisateurs et autorisations* : inviter l'adresse du compte de service avec les
   droits « Afficher les données financières » et « Gérer les commandes et les abonnements ».
3. Mettre le contenu du JSON dans le secret `GOOGLE_PLAY_SERVICE_ACCOUNT` (§2.3). La propagation des
   droits peut prendre jusqu'à 24 h.

### 5.4 Tests puis production

1. Ajouter les testeurs de licence (*Paramètres > Test de licence*), publier en **test interne**.
2. Sur un projet Supabase de test (`MONTFC_ENV` différent de `production`), les achats de test sont
   acceptés. En production ils sont refusés sauf si `GOOGLE_PLAY_ACCEPT_TEST_PURCHASES=true`.
3. Vérifier : achat, déblocage, restauration après réinstallation, refus d'un achat fait sur un autre compte.
4. Publier en production avec `flutter build appbundle --flavor store …` (§3.2).

**Point à vérifier avant le lancement** : que le compte marchand Google Play puisse être ouvert pour un
éditeur basé en RDC et que les étudiants puissent payer (carte, solde Google Play, facturation opérateur).
Si ce n'est pas le cas, la variante directe (APK + mobile money) reste le canal principal.

---

## 6. Tests

| Commande | Ce qui est testé |
|---|---|
| `cd montfc_app && flutter test` | 144 tests : calculateur (Slovin, Cochran), bibliographie APA 7 et notes, plan et numérotation, questionnaires, page de garde, export DOCX/PDF, flux de paiement mobile money et Google Play (agrégateur simulé), droits, synchronisation, écrans |
| `bash supabase/tests/local/run_db_tests.sh` | Base : RLS, droits, prix, codes promo, commissions, synchronisation |
| `cd supabase/functions && bash ../tests/local/run_db_tests.sh --exec deno test --allow-env --allow-net=127.0.0.1 --allow-read .` | 33 tests : paiement de bout en bout avec l'agrégateur simulé, rappels, idempotence, FlexPay, vérification Google Play |
| `cd web && npm test` | 14 tests : montants, téléphone, formulaires d'administration, page de paiement |

Les exports d'exemple se régénèrent avec `MONTFC_EXPORT_DIR=/un/dossier flutter test test/features/export`.

---

## 7. Formats des contenus

Tous les contenus se modifient dans le panneau (champs JSON vérifiés avant l'envoi). Les exemples
complets sont dans `supabase/seed.sql`.

**Page de garde.** `fields_schema` liste les champs à remplir par l'étudiant
(`key`, `label`, `type` : `text`, `textarea` ou `select`, `required`, `max_length`, `help`,
`prefill` : `profile.full_name`, `profile.faculty`…). La mise en page (`layout`, protégée) :

```json
{
  "schema_version": 1,
  "page": { "size": "A4", "margins_cm": { "top": 2, "bottom": 2, "left": 2.5, "right": 2 }, "border": "double" },
  "font": { "family": "Times New Roman", "size": 12 },
  "blocks": [
    { "type": "text", "text": "FACULTÉ DE {{faculty|upper}}", "align": "center", "bold": true },
    { "type": "text", "text": "DÉPARTEMENT DE {{department|upper}}", "align": "center", "if": "department" },
    { "type": "rule", "thickness_pt": 1 },
    { "type": "spacer", "height_cm": 3 },
    { "type": "box", "border": "single", "padding_cm": 0.4, "blocks": [ { "type": "text", "text": "{{title|upper}}" } ] }
  ]
}
```

`{{cle}}` insère un champ, `|upper` le met en majuscules, `"if": "cle"` masque le bloc si le champ est
vide. Un `schema_version` plus récent que celui de l'application est ignoré proprement (mettre l'appli à
jour d'abord).

**Modèle de document.** `structure` : liste de parties (`id`, `title`, `kind` : `preliminary`, `body`
ou `annex`, `heading_level`, `required`, `page_break_before`, `guidance`, `children`). `formatting` :
police, taille, interligne, marges, styles des titres. Les `guidance` sont des **consignes**, jamais du
texte à recopier.

**Questionnaire.** `variables` (à adapter par l'étudiant), `intro`, `sections` avec leurs `questions`
(`single`, `multiple`, `scale`, `number`, `open`), `closing`, `tips`.

---

## 8. Limites connues de la V1

- Brouillons de questionnaire : enregistrés seulement sur le téléphone (non synchronisés).
- Rôle `editor` : restreint par l'interface, pas par la base (§2.5).
- iOS : le code est prêt (Riverpod, chiffrement par Keychain) mais l'achat App Store n'est pas encore
  branché ; la variante iOS ne propose donc pas d'achat pour l'instant.
- Le sommaire des fichiers DOCX se met à jour à l'ouverture dans Word (Word demande la confirmation).
- APK non mesuré dans l'environnement de développement (§3.3).

---

## 9. Licences

- **Liberation Serif** (police des aperçus et des PDF, métriquement compatible avec Times New Roman) :
  SIL Open Font License 1.1, fichier `montfc_app/assets/fonts/LICENSE-LiberationSerif-OFL.txt`, affichée
  dans l'écran des licences de l'application.
- Les fichiers exportés appartiennent à l'étudiant : aucune restriction n'y est ajoutée.
