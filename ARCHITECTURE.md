# MonTFC — Proposition d'architecture (V1 / MVP)

> Statut : **validé le 18/10/2026** avec les choix par défaut de la section 9. Module 1 (base Supabase) livré dans `supabase/`.
> Les points marqués **[À VALIDER]** sont des choix par défaut que j'ai faits ; il suffit de les confirmer ou de les corriger.

Sommaire

1. Vue d'ensemble
2. Facturation Play Store / App Store (point bloquant à lire en premier)
3. Schéma de la base de données (tables, relations, RLS)
4. Fonctions serveur (Edge Functions) et module de paiement
5. Application Flutter : arborescence et choix techniques
6. Panneau d'administration et page de paiement web : arborescence
7. Hors ligne, synchronisation et protection du contenu
8. Plan de livraison module par module
9. Questions ouvertes

---

## 1. Vue d'ensemble

```
┌──────────────────────────┐        ┌───────────────────────────────────────────┐
│ App Flutter (Android/iOS)│        │ Supabase                                  │
│  - Riverpod              │ HTTPS  │  - Auth (téléphone + OTP SMS)             │
│  - SQLite local (sqflite)│◄──────►│  - PostgreSQL + RLS                       │
│  - Contenu payant chiffré│        │  - Edge Functions (Deno/TypeScript)       │
│  - Export DOCX / PDF     │        │      payment-init, payment-webhook, ...   │
└──────────────────────────┘        │  - pg_cron (expiration des paiements)     │
                                    └───────────────▲───────────────────────────┘
┌──────────────────────────┐                        │ webhook (callback)
│ Web (React + Vite)       │                ┌───────┴────────┐
│  /admin  : administration│◄──────────────►│ FlexPay (RDC)  │──► Orange / Airtel / M-Pesa
│  /payer  : paiement web  │                └────────────────┘
└──────────────────────────┘
```

Principes :

- **Le serveur est la seule source de vérité pour les droits d'accès.** L'application garde une copie locale (pour le hors ligne) mais ne peut jamais s'accorder un droit elle-même : la table `entitlements` n'est modifiable que par les fonctions serveur.
- **Contenu en base, pas dans l'APK.** Guide, modèles de page de garde, modèles de documents et questionnaires sont stockés en Markdown / JSON dans PostgreSQL, modifiables depuis l'admin sans mise à jour de l'application.
- **Règle éditoriale :** aucun contenu ne contient de texte de TFC/mémoire déjà rédigé. Les modèles ne contiennent que la structure, des consignes (« Ici, présentez… ») et des champs à remplir. Cette règle sera rappelée dans l'admin à côté de chaque éditeur.
- **Abstraction du paiement côté serveur** (`PaymentProvider` en TypeScript) : changer FlexPay pour MaxiCash = ajouter un fichier et changer une variable d'environnement.

---

## 2. Facturation Play Store / App Store (à lire en premier)

### Ce que disent les règles (vérifié le 18/10/2026)

- **Google Play** : les contenus et fonctions numériques vendus *dans* une application distribuée par Play doivent passer par Google Play Billing. Depuis le 30 juin 2026, Google ouvre un programme de « billing choice » (facturation alternative ou lien vers son propre site web) mais **uniquement au Royaume-Uni, dans l'EEE et aux États-Unis** pour l'instant ; d'autres marchés suivront « marché par marché », sans liste publiée. **La RDC n'est pas annoncée.** ([annonce Google](https://android-developers.googleblog.com/2026/06/play-expanded-billing.html), [9to5Google](https://9to5google.com/2026/06/24/google-play-store-external-billing-june-30/))
- **App Store** : même logique (achat intégré Apple obligatoire pour les contenus numériques), avec une exception pour les liens externes uniquement sur le storefront américain.
- Dans les deux cas, une application **peut donner accès à un contenu acheté ailleurs** (sur le web) tant qu'elle **ne contient aucun bouton, lien ni message incitant à payer en dehors** du store.
- Conséquence : **intégrer Orange Money / Airtel / M-Pesa directement dans la version Play Store violerait la règle** et exposerait l'application à une suppression.

### Stratégie proposée [À VALIDER]

Une seule base de code, **deux variantes de build** (flavors Flutter) et une page web :

| Canal | Distribution | Paiement dans l'app | Conforme |
|---|---|---|---|
| `store` | Google Play (puis App Store) | **Google Play Billing / Apple IAP** uniquement. Aucune mention du paiement web. Les droits achetés sur le web sont reconnus automatiquement (même numéro de téléphone = même compte). | Oui |
| `direct` | APK téléchargeable depuis le site montfc (et partage WhatsApp) | **Mobile money** (FlexPay) directement dans l'app | Oui (hors store, les règles Play ne s'appliquent pas) |
| Web `/payer` | Site montfc | Mobile money (FlexPay) | Oui |

- Le choix des canaux de paiement affichés est piloté **par la base** (table `app_settings`, clé `payment_channels`, par plateforme et par variante). Si Google ouvre le programme « billing choice » à la RDC, on active le lien web dans la variante `store` sans republier l'application.
- Achats Play : vérifiés côté serveur (fonction `verify-store-purchase` + API Google Play Developer avec un compte de service) avant de créer le droit.
- Réalité terrain à garder en tête : en RDC, peu d'étudiants ont une carte bancaire ; Google Play Billing y sera peu utilisé. **Le canal principal de revenus sera vraisemblablement l'APK `direct` + la page web.** La variante `store` sert surtout à la visibilité et à la confiance.
- Prix Play : définis dans la Play Console (Google convertit en devise locale). Les prix en base (CDF/USD) servent au mobile money ; l'admin affichera un rappel pour garder les deux cohérents.
- **Avant la publication**, vérifier dans la Play Console (*Monétisation → Programmes de facturation*) si la RDC est devenue éligible. Je le rappellerai dans le README.

---

## 3. Schéma de la base de données

### 3.1 Diagramme des relations (simplifié)

```
auth.users 1─1 profiles ─┬─< user_devices
                         ├─< student_works ─< bibliography_entries
                         ├─< payments >── products ─< product_prices
                         │       │            │
                         │       ├── promo_codes >── ambassadors ─< commissions
                         │       └─< payment_events
                         └─< entitlements >── products

institutions ─< cover_templates
             ─< profiles
guide_chapters, document_templates, questionnaire_templates (contenu)
app_settings, app_admins
```

### 3.2 Tables

Conventions : clés `uuid` (`gen_random_uuid()`), dates `timestamptz`, colonnes `created_at`/`updated_at` (trigger), suppression logique `deleted_at` sur le contenu synchronisé (pour propager les suppressions aux téléphones hors ligne). Montants en **entiers dans l'unité mineure** (centimes USD, CDF entier) pour éviter les erreurs d'arrondi.

**Référentiels et profil**

| Table | Colonnes principales | Remarques |
|---|---|---|
| `institutions` | `id`, `code` (UNIKIN, UPN, ISTA, ISS, UPC, UCC, ULK, ISP_GOMBE, AUTRE), `name`, `city`, `is_active` | Sert au profil et aux statistiques par université |
| `profiles` | `id` (= `auth.users.id`), `phone`, `full_name`, `institution_id`, `institution_other` (texte si « Autre »), `faculty`, `department`, `level` (enum : G1…G3, L1…L3, M1, M2), `work_type` (enum : `tfc`, `memoire_licence`, `memoire_master`), `academic_year` (ex. `2025-2026`), `active_device_id`, `created_at` | Créé par trigger à l'inscription. Faculté et département en texte libre pour la V1 [À VALIDER] |
| `user_devices` | `id`, `user_id`, `device_id` (identifiant généré et stocké par l'app), `platform`, `model`, `app_version`, `app_flavor`, `last_seen_at`, `revoked_at` | Historique des appareils |
| `app_admins` | `user_id`, `role` (`admin`, `editor`) | Les admins se connectent par e-mail + mot de passe |
| `app_settings` | `key`, `value jsonb` | Ex. `payment_channels`, `usd_cdf_rate_display`, version minimale de l'app |

**Contenu (modifiable depuis l'admin)**

| Table | Colonnes principales | Accès |
|---|---|---|
| `guide_chapters` | `id`, `slug`, `position`, `title`, `summary`, `body_md`, `is_published`, `version`, `updated_at`, `deleted_at` | Gratuit |
| `cover_templates` | `id`, `institution_id` (null = générique), `name`, `fields_schema jsonb` (liste des champs du formulaire), `layout jsonb` (lignes, alignement, taille, gras, espacements, placeholders `{{student_name}}`), `preview_md`, `is_published`, `version`, `updated_at`, `deleted_at` | Métadonnées publiques ; `layout` réservé aux ayants droit |
| `document_templates` | `id`, `work_type`, `title`, `description`, `structure jsonb` (arborescence des parties avec consignes), `formatting jsonb` (marges, police, taille, interligne, numérotation, styles de titres), `is_published`, `version`, `updated_at`, `deleted_at` | idem |
| `questionnaire_templates` | `id`, `domain` (enum : gestion, economie, droit, sante, informatique, education), `title`, `description`, `body jsonb` (sections, questions, types de réponses), `is_published`, `version`, `updated_at`, `deleted_at` | idem |

Pour les trois tables payantes, le **corps** du modèle (`layout`, `structure`, `body`) est séparé des métadonnées : les métadonnées sont lisibles par tous (catalogue, aperçu), le corps n'est renvoyé que par la fonction `get_paid_content()` qui vérifie le droit. Concrètement : deux tables par type (`cover_templates` + `cover_template_bodies`, etc.) avec une RLS différente [À VALIDER, c'est la façon la plus simple de faire respecter la règle au niveau de PostgreSQL].

**Travail de l'étudiant (synchronisé)**

| Table | Colonnes principales |
|---|---|
| `student_works` | `id`, `user_id`, `title` (sujet), `work_type`, `director`, `supervisor`, `cover_template_id`, `cover_data jsonb` (valeurs du formulaire), `plan jsonb` (plan hiérarchique saisi par l'étudiant), `document_template_id`, `updated_at`, `deleted_at` |
| `bibliography_entries` | `id`, `user_id`, `work_id`, `kind` (enum : `book`, `article`, `thesis`, `website`, `legal_text`), `data jsonb` (auteurs, titre, éditeur, lieu, année, revue, volume, pages, URL, date de consultation, juridiction, n° de texte…), `updated_at`, `deleted_at` |

La liste de vérification avant dépôt reste **uniquement locale**, comme demandé.

**Commerce**

| Table | Colonnes principales | Remarques |
|---|---|---|
| `products` | `id`, `code` (ex. `COVER_PAGE`, `DOC_TEMPLATE`, `QUESTIONNAIRE`, `PACK_FINALISTE`), `name`, `description`, `kind` (`unit` / `pack`), `feature` (`cover_page`, `doc_template`, `questionnaire`, `all`), `requires_resource` (bool : l'achat vise-t-il un modèle précis ?), `duration_days` (null = permanent ; 365 pour le pack), `play_product_id`, `apple_product_id`, `is_active`, `position` | |
| `product_prices` | `product_id`, `currency` (`CDF`/`USD`), `amount_minor`, `valid_from` | Prix modifiables sans mise à jour |
| `entitlements` | `id`, `user_id`, `product_id`, `feature`, `resource_id` (null = toute la fonction), `starts_at`, `expires_at` (null = permanent), `source` (`payment`, `store`, `admin_grant`), `payment_id` (unique), `revoked_at` | **Écriture serveur uniquement** |
| `payments` | `id`, `user_id`, `product_id`, `resource_id`, `channel` (`mobile_money_app`, `mobile_money_web`, `google_play`, `app_store`), `provider` (`flexpay`, `maxicash`, `mock`, `google`, `apple`), `currency`, `amount_gross_minor`, `discount_minor`, `amount_net_minor`, `promo_code_id`, `msisdn`, `operator` (`orange`, `airtel`, `vodacom`), `status` (`pending`, `processing`, `succeeded`, `failed`, `expired`, `cancelled`), `provider_reference`, `failure_reason`, `idempotency_key` (unique), `expires_at`, `confirmed_at`, `created_at` | Historique des achats = lecture de cette table |
| `payment_events` | `id`, `provider`, `provider_event_id`, `payment_id`, `payload jsonb`, `received_at` ; **unique (`provider`, `provider_event_id`)** | Journal brut des webhooks, base de l'idempotence |
| `ambassadors` | `id`, `full_name`, `phone`, `institution_id`, `payout_msisdn`, `is_active`, `user_id` (optionnel) | |
| `promo_codes` | `id`, `code` (unique, majuscules), `ambassador_id`, `discount_percent` (0 à 90 %), `commission_percent` (0 à 100 % du montant payé), `applies_to` (liste de produits, null = tous), `valid_from`, `valid_to`, `max_uses`, `uses_count`, `is_active` | |
| `commissions` | `id`, `ambassador_id`, `payment_id` (**unique**), `currency`, `amount_minor`, `status` (`due`, `paid`, `cancelled`), `paid_at`, `paid_reference` | Créée dans la même transaction que le déblocage |

### 3.3 Fonctions SQL clés

- `is_admin()` : `exists(select 1 from app_admins where user_id = auth.uid())`.
- `has_access(feature text, resource uuid)` : vrai si un droit non révoqué, non expiré existe pour `auth.uid()` avec `feature = 'all'` ou (`feature` = la fonction et `resource_id` null ou égal). `SECURITY DEFINER`, `search_path` fixé.
- `confirm_payment(payment_id, provider_reference, event_id)` : **une seule transaction**, idempotente :
  1. `update payments set status = 'succeeded' … where id = $1 and status in ('pending','processing') returning *` ;
  2. si aucune ligne (déjà traité, expiré ou échoué), on s'arrête sans rien faire ;
  3. sinon : insertion du droit (`payment_id` unique), incrément `promo_codes.uses_count`, insertion de la commission (`payment_id` unique).
  Une double notification ne peut donc jamais créer deux droits ni deux commissions.
- `quote_price(product_id, currency, promo_code)` : calcule le prix net côté serveur (l'app n'envoie jamais de montant).
- `sync_changes(since timestamptz)` : renvoie en un seul appel tout le contenu modifié depuis la dernière synchro (chapitres, métadonnées de modèles, travaux de l'étudiant, droits) → une seule requête réseau à chaque reconnexion.
- Vues/RPC du tableau de bord (réservées à `is_admin()`) : `admin_stats_signups(from,to)`, `admin_stats_sales_daily(from,to)`, `admin_stats_revenue_by_institution(from,to)`, `admin_commissions_due()`.

### 3.4 Règles RLS

RLS activée sur **toutes** les tables. Le rôle `service_role` (utilisé seulement dans les Edge Functions) contourne la RLS.

| Table | `select` | `insert` / `update` / `delete` |
|---|---|---|
| `institutions`, `guide_chapters`, `products`, `product_prices`, métadonnées des modèles | tout le monde (`anon` + `authenticated`) si publié/actif ; admin : tout | admin seulement |
| `*_bodies` (corps des modèles payants) | `is_admin() or has_access(feature, template_id)` | admin seulement |
| `profiles` | `id = auth.uid()` ou admin | `update` par le propriétaire, **sauf** `phone` et `active_device_id` (bloqués par trigger) |
| `user_devices` | propriétaire ou admin | serveur seulement |
| `student_works`, `bibliography_entries` | `user_id = auth.uid()` | `user_id = auth.uid()` (et `with check` identique) |
| `entitlements` | propriétaire ou admin | **serveur seulement** (aucune politique d'écriture pour `authenticated`) |
| `payments` | propriétaire ou admin | serveur seulement (création via `payment-init`) |
| `payment_events`, `commissions`, `ambassadors`, `promo_codes` | admin seulement (un ambassadeur pourra voir ses commissions en V2) | admin / serveur |
| `app_settings` | tout le monde (clés publiques) | admin |

Les codes promo ne sont pas lisibles par l'app : la validation passe par `quote_price()`, ce qui empêche de lister les codes.

---

## 4. Fonctions serveur et module de paiement

### 4.1 Edge Functions (Supabase, Deno/TypeScript)

| Fonction | Rôle |
|---|---|
| `claim-device` | Appelée après chaque connexion OTP : enregistre l'appareil, le marque actif dans `profiles.active_device_id` et **révoque les autres sessions** (`auth.admin.signOut(jwt, 'others')`). L'ancien appareil perd l'accès à l'expiration de son jeton (réglée à 15 min) ; l'app vérifie aussi `active_device_id` à chaque reprise et se déconnecte proprement. |
| ~~`payment-quote`~~ | Remplacée par la fonction SQL `quote_price()`, appelée directement par l'app (utilisateurs connectés uniquement) |
| `payment-init` | Crée le paiement `pending`, appelle `provider.initiate()` (push USSD sur le téléphone), renvoie l'`id` |
| `payment-webhook` | Point d'entrée de l'agrégateur : vérifie l'authenticité, journalise dans `payment_events` (doublon → réponse 200 immédiate), appelle `confirm_payment()` ou marque l'échec |
| `payment-status` | Interrogée par l'app (toutes les 5 s pendant 2 min max) ; si le webhook tarde, interroge l'agrégateur (`provider.checkStatus()`) puis applique le même traitement idempotent |
| `verify-store-purchase` | Vérifie un achat Google Play / Apple auprès du store et crée le droit |
| `get-paid-content` | (optionnel, si on préfère au RLS) renvoie le corps d'un modèle chiffré pour l'appareil |
| `pg_cron` toutes les 5 min | Passe en `expired` les paiements `pending` dont `expires_at` est dépassé (10 min par défaut) après une dernière vérification chez l'agrégateur |

### 4.2 Interface `PaymentProvider`

```ts
// supabase/functions/_shared/payments/provider.ts
export interface PaymentProvider {
  readonly name: 'flexpay' | 'maxicash' | 'mock';
  /** Lance la demande de paiement (push USSD / page de confirmation). */
  initiate(req: InitiateRequest): Promise<InitiateResult>;
  /** Vérifie l'authenticité d'un webhook et le traduit en événement normalisé. */
  parseWebhook(req: Request): Promise<NormalizedEvent>;
  /** Interroge l'agrégateur sur l'état d'une transaction. */
  checkStatus(providerReference: string): Promise<NormalizedStatus>;
}
```

- Implémentations : `FlexPayProvider` (première, **[À VALIDER] FlexPay plutôt que MaxiCash** car il couvre M-Pesa, Orange Money et Airtel Money en CDF et USD via un push direct sur le téléphone, ce qui correspond au flux demandé), `MockProvider` (tests et démo : succès, échec, délai, double webhook configurables), `MaxiCashProvider` plus tard.
- Sélection : variable d'environnement `PAYMENT_PROVIDER`. Clés : `FLEXPAY_MERCHANT`, `FLEXPAY_TOKEN`, `FLEXPAY_WEBHOOK_SECRET`… **uniquement dans les secrets Supabase**, jamais dans l'app ni dans le dépôt.
- Le webhook FlexPay n'étant pas signé de façon forte selon la documentation que je connais, `parseWebhook` ne fait pas confiance au contenu : il **reconfirme toujours l'état via `checkStatus()`** avant de débloquer. (À revérifier sur la documentation actuelle de FlexPay au moment du codage.)

### 4.3 Flux de paiement mobile money

```
App/Web            payment-init           FlexPay            Téléphone        payment-webhook
  │ offre + n° MM ──►│ quote + insert pending│                   │                   │
  │                  │── initiate ─────────►│── push USSD ──────►│                   │
  │◄── payment_id ───│                       │                   │ saisit son PIN    │
  │ (écran « Confirmez sur votre téléphone », sondage payment-status)                 │
  │                  │                       │── callback ──────────────────────────►│
  │                  │                       │◄── checkStatus ───────────────────────│
  │                  │                       │                   confirm_payment() (transaction)
  │◄── status = succeeded (sondage ou Realtime) → rafraîchit les droits → contenu téléchargé
```

Cas gérés : en attente (écran d'attente + reprise si l'app est fermée), échec (raison lisible : solde insuffisant, annulé, PIN incorrect), délai dépassé (expiration auto, bouton « Réessayer »), double notification (unicité `payment_events` + `confirm_payment` idempotent), webhook perdu (`payment-status` et le cron vont chercher l'état).

---

## 5. Application Flutter

### 5.1 Choix techniques (orientés poids de l'APK et données)

| Besoin | Paquet | Pourquoi |
|---|---|---|
| État | `flutter_riverpod` (+ `riverpod_annotation`) | Demandé |
| Navigation | `go_router` | Standard, léger |
| Backend | `supabase_flutter` | Auth, base, Realtime |
| Base locale | `sqflite` | Utilise le SQLite d'Android : n'ajoute presque rien à l'APK (contrairement à SQLCipher, +3 à 4 Mo par architecture) |
| Chiffrement du contenu payant | `cryptography` (AES-256-GCM en Dart) + `flutter_secure_storage` (clé dans le Keystore Android) | Chiffre seulement les colonnes payantes, sans moteur SQL chiffré |
| Markdown | `flutter_markdown_plus` | `flutter_markdown` n'est plus maintenu |
| PDF | `pdf` (Dart pur) | Pas de dépendance native |
| DOCX | `archive` + gabarits OOXML minimaux (quelques Ko) | Pas de bon paquet DOCX en Dart ; on génère le XML Word nous-mêmes. La table des matières est un champ Word mis à jour à l'ouverture |
| Police PDF | **Tinos** (Apache 2.0, mêmes métriques que Times New Roman), ~400 Ko | Times New Roman n'est pas redistribuable. Le DOCX, lui, indique bien « Times New Roman » (police présente sur les PC) |
| Partage / enregistrement | `share_plus`, `path_provider` (+ dossier Téléchargements via `MediaStore` sur Android) | WhatsApp passe par la feuille de partage |
| Connectivité | `connectivity_plus` | Déclencher la synchro |
| Appareil | `device_info_plus` + UUID stocké en stockage sécurisé | Identifiant d'appareil stable sans permission sensible |
| Achats store (variante `store`) | `in_app_purchase` | Uniquement compilé dans la variante `store` |
| Captures d'écran | petit canal natif Kotlin (`FLAG_SECURE` activé/désactivé par écran) | Évite un paquet supplémentaire |

Poids : build `--split-per-abi` (APK `direct`) / AAB (Play), R8, `--obfuscate --split-debug-info`, `--tree-shake-icons`, pas d'images (icônes Material uniquement, logos en texte). Estimation **10 à 14 Mo par architecture**, sous l'objectif de 20 Mo.

### 5.2 Arborescence

Organisation **par fonctionnalité**, chaque fonctionnalité séparée en `data` / `domain` / `presentation`.

```
montfc_app/
├── pubspec.yaml
├── analysis_options.yaml
├── android/                      # flavors store/direct, FLAG_SECURE (MainActivity.kt), R8
├── ios/
├── assets/
│   ├── fonts/Tinos-*.ttf
│   ├── docx/                     # gabarits OOXML (document.xml, styles.xml, settings.xml…)
│   └── seed/                     # contenu gratuit de secours (premier lancement hors ligne)
├── lib/
│   ├── main_store.dart           # point d'entrée variante Play/App Store
│   ├── main_direct.dart          # point d'entrée variante APK direct
│   ├── bootstrap.dart            # init Supabase, base locale, ProviderScope
│   ├── app.dart                  # MaterialApp.router, thème, locale fr
│   ├── core/
│   │   ├── config/               # env.dart (URL/anon key via --dart-define), flavor.dart
│   │   ├── router/               # app_router.dart, garde d'authentification et d'accès
│   │   ├── theme/
│   │   ├── database/             # local_database.dart (sqflite, migrations), tables locales
│   │   ├── security/             # content_cipher.dart, secure_screen.dart, device_id.dart
│   │   ├── network/              # connectivity_provider.dart, supabase_provider.dart
│   │   ├── sync/                 # sync_service.dart (sync_changes + file d'envoi)
│   │   ├── errors/               # failures.dart, messages en français
│   │   └── widgets/              # composants communs
│   └── features/
│       ├── auth/                 # téléphone, OTP, claim-device, déconnexion forcée
│       │   ├── data/  domain/  presentation/
│       ├── profile/              # profil, historique des achats
│       ├── guide/                # chapitres de méthodologie (gratuit)
│       ├── sample_size/          # Slovin, Cochran (gratuit)
│       │   └── domain/slovin.dart, cochran.dart, sample_size_result.dart
│       ├── checklist/            # liste avant dépôt (locale)
│       ├── works/                # « Mon travail » : sujet, directeur, plan
│       ├── cover_page/           # formulaire, aperçu, rendu depuis layout JSON
│       ├── bibliography/
│       │   └── domain/formatters/apa7_formatter.dart, footnote_formatter.dart
│       ├── templates/            # modèles de document et questionnaires
│       ├── export/               # docx_builder.dart, pdf_builder.dart, share_service.dart
│       ├── store/                # catalogue, prix CDF/USD, droits (entitlements)
│       └── payment/
│           ├── domain/payment_channel.dart        # abstraction côté app
│           ├── data/mobile_money_channel.dart      # via Edge Functions (variante direct)
│           ├── data/store_billing_channel.dart     # in_app_purchase (variante store)
│           └── presentation/                       # choix opérateur, attente, résultat
└── test/
    ├── features/sample_size/     # Slovin, Cochran
    ├── features/bibliography/    # APA 7, notes de bas de page, tri
    └── features/payment/         # flux complet avec agrégateur simulé
```

---

## 6. Panneau d'administration et page de paiement web

**[À VALIDER] React + Vite + TypeScript + `supabase-js`**, hébergé en statique (Netlify, Vercel ou Cloudflare Pages, gratuits). Plus simple que Flutter web pour des tableaux et formulaires, et la même application porte la page de paiement publique.

```
montfc_web/
├── package.json
├── .env.example                  # VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY (clé publique seulement)
├── src/
│   ├── main.tsx, App.tsx, router.tsx
│   ├── lib/supabase.ts, auth.ts, format.ts (CDF/USD)
│   ├── components/               # Table, Formulaire, MarkdownEditor, JsonEditor, StatCard, Chart
│   ├── admin/
│   │   ├── Dashboard.tsx         # inscrits, achats/jour, revenus, revenus par université, commissions dues
│   │   ├── guide/                # chapitres (Markdown + aperçu)
│   │   ├── cover-templates/      # modèles de page de garde (JSON + aperçu)
│   │   ├── document-templates/
│   │   ├── questionnaires/
│   │   ├── products/             # offres et prix
│   │   ├── promo-codes/
│   │   ├── ambassadors/          # + commissions, marquer « payée »
│   │   └── payments/             # recherche, détail, attribution manuelle d'un droit
│   └── pay/
│       ├── PayPage.tsx           # connexion par OTP → offre → numéro mobile money
│       └── PayStatus.tsx         # attente / succès / échec
└── public/
```

```
supabase/
├── config.toml
├── migrations/                   # 0001_schema.sql, 0002_rls.sql, 0003_functions.sql, 0004_cron.sql
├── seed.sql                      # démo : 3 chapitres, 3 pages de garde, 1 modèle de mémoire, offres, institutions
└── functions/
    ├── _shared/
    │   ├── payments/provider.ts, flexpay.ts, mock.ts, factory.ts
    │   ├── supabase_admin.ts, cors.ts, errors.ts
    ├── claim-device/  payment-quote/  payment-init/  payment-webhook/
    ├── payment-status/  verify-store-purchase/
    └── tests/                    # tests Deno du flux de paiement avec MockProvider
```

Le dépôt final regroupe `montfc_app/`, `montfc_web/`, `supabase/` et `README.md` dans `/mnt/project-files/montfc/` (ou dans un dépôt GitHub si tu m'en indiques un).

---

## 7. Hors ligne, synchronisation et protection du contenu

- **Premier lancement** : le contenu gratuit de secours (`assets/seed`) est disponible immédiatement ; à la première connexion, `sync_changes(since = null)` télécharge la version à jour.
- **Synchro incrémentale** : on stocke la date de dernière synchro ; à chaque reconnexion, un seul appel renvoie ce qui a changé (y compris les suppressions via `deleted_at`). Le contenu est en texte/JSON compressé (gzip par Supabase), donc quelques dizaines de Ko par synchro.
- **Écritures hors ligne** (travaux, bibliographie) : enregistrées localement avec un indicateur « à envoyer » ; envoyées à la reconnexion. Conflits : **la dernière modification gagne** (`updated_at`), suffisant pour un utilisateur sur un seul appareil.
- **Droits hors ligne** : copie locale chiffrée des droits avec leur date d'expiration. L'app respecte l'expiration même hors ligne ; le serveur reste l'arbitre à chaque reconnexion (un droit révoqué disparaît). Le corps des modèles payants n'est téléchargé que si le serveur l'autorise (RLS).
- **Chiffrement local** : corps des modèles payants chiffrés en AES-256-GCM, clé aléatoire stockée dans le Keystore Android / Keychain iOS. Le contenu gratuit et les travaux de l'étudiant ne sont pas chiffrés (inutile et coûteux).
- **Captures d'écran** : `FLAG_SECURE` activé à l'entrée des écrans payants (modèles, page de garde, questionnaires), désactivé en sortie. Sur iOS, il n'existe pas d'équivalent strict ; on masque le contenu à l'enregistrement d'écran (`UIScreen.capturedDidChange`).
- **Fichiers exportés** : aucune restriction, ils appartiennent à l'étudiant.

---

## 8. Plan de livraison module par module

Après validation, je livre dans cet ordre, avec un point d'étape à la fin de chaque module :

1. **Base Supabase** : migrations (schéma, RLS, fonctions SQL, cron) + données de démonstration.
2. **Socle Flutter** : projet, flavors, thème, routeur, base locale, synchro, chiffrement.
3. **Authentification et profil** : OTP, appareil unique, profil.
4. **Fonctions gratuites** : guide, calculateur (avec tests), liste de vérification.
5. **Boutique et paiement** : catalogue, Edge Functions, `PaymentProvider` FlexPay + simulé, écrans de paiement, historique (avec tests du flux).
6. **Page de garde** (formulaire, aperçu, export).
7. **Bibliographie** (APA 7, notes de bas de page, tri, export, avec tests).
8. **Modèles de document et questionnaires**.
9. **Export DOCX / PDF complet** et partage WhatsApp.
10. **Panneau d'administration et page de paiement web**.
11. **README** (installation, clés, publication Play Store).

Note : je n'ai pas de SDK Flutter ni de projet Supabase connectés ici. J'écrirai le code et lancerai les tests qui ne dépendent que de Dart/Deno si je peux installer les outils dans mon environnement ; sinon je te dirai précisément ce qui n'a pas pu être exécuté.

---

## 9. Questions ouvertes

Les réponses par défaut ci-dessous seront appliquées si tu valides sans commentaire :

1. **Canaux de paiement** : variante Play Store avec Google Play Billing uniquement + APK direct et page web avec mobile money (section 2). *Défaut : oui.*
2. **Agrégateur** : FlexPay en premier. *Défaut : FlexPay.* As-tu déjà un compte marchand chez l'un des deux ?
3. **Portée des achats à l'unité** : « Page de garde » débloque le générateur pour tous les établissements, de façon permanente ; « Un modèle » débloque un modèle de document ou un questionnaire précis, de façon permanente ; la bibliographie et l'export complet (plan, table des matières, bibliographie) sont réservés au **Pack Finaliste** (12 mois). *Défaut : comme décrit.*
4. **Admin** : React + Vite plutôt que Flutter web. *Défaut : React.*
5. **Fournisseur SMS pour l'OTP** : Supabase exige un fournisseur (Twilio, Vonage, MessageBird…). Twilio fonctionne vers le +243 mais coûte cher ; on peut brancher un fournisseur SMS local via le « Send SMS Hook » de Supabase. *Défaut : Twilio pour démarrer, hook local plus tard.*
6. **Faculté / département** : texte libre en V1 (listes déroulantes en V2). *Défaut : texte libre.*
