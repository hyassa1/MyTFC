-- =============================================================================
-- MonTFC — Migration 1 : schéma (types, tables, index, déclencheurs)
-- -----------------------------------------------------------------------------
-- Conventions :
--   * Montants en « unités mineures » (×100) pour CDF comme pour USD
--     (ISO 4217 : 2 décimales pour les deux devises). 1,50 USD = 150.
--   * updated_at est géré par le serveur (déclencheur) sur le contenu ;
--     sur les données de l'étudiant, updated_at vient du téléphone (règle
--     « la dernière modification gagne ») et server_updated_at sert de curseur
--     de synchronisation.
--   * deleted_at = suppression logique, pour propager les suppressions aux
--     téléphones restés hors ligne.
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Types énumérés
-- -----------------------------------------------------------------------------
create type public.academic_level as enum
  ('G1', 'G2', 'G3', 'L1', 'L2', 'L3', 'M1', 'M2', 'AUTRE');

create type public.work_type as enum
  ('tfc', 'memoire_licence', 'memoire_master');

create type public.source_kind as enum
  ('book', 'article', 'thesis', 'website', 'legal_text');

create type public.questionnaire_domain as enum
  ('gestion', 'economie', 'droit', 'sante', 'informatique', 'education');

create type public.product_kind as enum ('unit', 'pack');

-- Fonction débloquée par un droit d'accès. 'all' = Pack Finaliste.
create type public.feature as enum
  ('cover_page', 'doc_template', 'questionnaire', 'bibliography', 'export', 'all');

create type public.currency as enum ('CDF', 'USD');

create type public.payment_status as enum
  ('pending', 'processing', 'succeeded', 'failed', 'expired', 'cancelled');

create type public.payment_channel as enum
  ('mobile_money_app', 'mobile_money_web', 'google_play', 'app_store', 'admin');

create type public.payment_provider as enum
  ('flexpay', 'maxicash', 'mock', 'google', 'apple', 'admin');

create type public.mm_operator as enum ('orange', 'airtel', 'vodacom', 'afrimoney');

create type public.entitlement_source as enum ('payment', 'store', 'admin_grant');

create type public.commission_status as enum ('due', 'paid', 'cancelled');

create type public.admin_role as enum ('admin', 'editor');

-- -----------------------------------------------------------------------------
-- Déclencheur générique : met à jour updated_at
-- -----------------------------------------------------------------------------
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Déclencheur pour les données synchronisées de l'étudiant :
-- server_updated_at = instant de réception par le serveur (curseur de synchro).
create or replace function public.tg_set_server_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.server_updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Référentiels
-- -----------------------------------------------------------------------------
create table public.institutions (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (code ~ '^[A-Z0-9_]+$'),
  name        text not null,
  city        text not null default 'Kinshasa',
  is_active   boolean not null default true,
  position    int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger institutions_updated_at before update on public.institutions
  for each row execute function public.tg_set_updated_at();

create table public.app_settings (
  key         text primary key,
  value       jsonb not null,
  is_public   boolean not null default true,   -- lisible par l'application
  updated_at  timestamptz not null default now()
);
create trigger app_settings_updated_at before update on public.app_settings
  for each row execute function public.tg_set_updated_at();

create table public.app_admins (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  role        public.admin_role not null default 'editor',
  created_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Profil et appareils
-- -----------------------------------------------------------------------------
create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  phone             text unique,
  full_name         text check (char_length(full_name) <= 120),
  institution_id    uuid references public.institutions (id),
  institution_other text check (char_length(institution_other) <= 120),
  faculty           text check (char_length(faculty) <= 120),
  department        text check (char_length(department) <= 120),
  level             public.academic_level,
  work_type         public.work_type,
  academic_year     text check (academic_year ~ '^[0-9]{4}-[0-9]{4}$'),
  active_device_id  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index profiles_institution_idx on public.profiles (institution_id);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.tg_set_updated_at();

create table public.user_devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  device_id     text not null check (char_length(device_id) between 8 and 128),
  platform      text not null check (platform in ('android', 'ios', 'web')),
  model         text,
  app_version   text,
  app_flavor    text check (app_flavor in ('store', 'direct', 'web')),
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  revoked_at    timestamptz,
  unique (user_id, device_id)
);

-- -----------------------------------------------------------------------------
-- Contenu : guide de méthodologie (gratuit)
-- -----------------------------------------------------------------------------
create table public.guide_chapters (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique check (slug ~ '^[a-z0-9-]+$'),
  position      int not null default 0,
  title         text not null,
  summary       text,
  body_md       text not null default '',
  is_published  boolean not null default false,
  version       int not null default 1,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index guide_chapters_updated_idx on public.guide_chapters (updated_at);
create trigger guide_chapters_updated_at before update on public.guide_chapters
  for each row execute function public.tg_set_updated_at();

-- -----------------------------------------------------------------------------
-- Contenu payant : métadonnées publiques + corps protégé (tables *_bodies)
-- -----------------------------------------------------------------------------

-- Modèles de page de garde (un par établissement, plus un générique)
create table public.cover_templates (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique check (code ~ '^[A-Z0-9_]+$'),
  institution_id  uuid references public.institutions (id),  -- null = générique
  name            text not null,
  description     text,
  -- Champs du formulaire (publics : ils ne révèlent pas la mise en page).
  fields_schema   jsonb not null default '[]'::jsonb
                  check (jsonb_typeof(fields_schema) = 'array'),
  position        int not null default 0,
  is_published    boolean not null default false,
  version         int not null default 1,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create trigger cover_templates_updated_at before update on public.cover_templates
  for each row execute function public.tg_set_updated_at();

create table public.cover_template_bodies (
  template_id uuid primary key references public.cover_templates (id) on delete cascade,
  layout      jsonb not null check (jsonb_typeof(layout) = 'object'),
  updated_at  timestamptz not null default now()
);
create trigger cover_template_bodies_updated_at before update on public.cover_template_bodies
  for each row execute function public.tg_set_updated_at();

-- Modèles de document (TFC, mémoire de licence, mémoire de master)
create table public.document_templates (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique check (code ~ '^[A-Z0-9_]+$'),
  work_type     public.work_type not null,
  title         text not null,
  description   text,
  position      int not null default 0,
  is_published  boolean not null default false,
  version       int not null default 1,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create trigger document_templates_updated_at before update on public.document_templates
  for each row execute function public.tg_set_updated_at();

create table public.document_template_bodies (
  template_id uuid primary key references public.document_templates (id) on delete cascade,
  structure   jsonb not null check (jsonb_typeof(structure) = 'array'),
  formatting  jsonb not null check (jsonb_typeof(formatting) = 'object'),
  updated_at  timestamptz not null default now()
);
create trigger document_template_bodies_updated_at before update on public.document_template_bodies
  for each row execute function public.tg_set_updated_at();

-- Modèles de questionnaires d'enquête
create table public.questionnaire_templates (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique check (code ~ '^[A-Z0-9_]+$'),
  domain        public.questionnaire_domain not null,
  title         text not null,
  description   text,
  position      int not null default 0,
  is_published  boolean not null default false,
  version       int not null default 1,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create trigger questionnaire_templates_updated_at before update on public.questionnaire_templates
  for each row execute function public.tg_set_updated_at();

create table public.questionnaire_template_bodies (
  template_id uuid primary key references public.questionnaire_templates (id) on delete cascade,
  body        jsonb not null check (jsonb_typeof(body) = 'object'),
  updated_at  timestamptz not null default now()
);
create trigger questionnaire_template_bodies_updated_at before update on public.questionnaire_template_bodies
  for each row execute function public.tg_set_updated_at();

-- -----------------------------------------------------------------------------
-- Travail de l'étudiant (synchronisé, créé hors ligne : id généré par l'app)
-- -----------------------------------------------------------------------------
create table public.student_works (
  id                    uuid primary key,
  user_id               uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title                 text check (char_length(title) <= 500),
  work_type             public.work_type,
  director              text check (char_length(director) <= 200),
  supervisor            text check (char_length(supervisor) <= 200),
  cover_template_id     uuid references public.cover_templates (id),
  cover_data            jsonb not null default '{}'::jsonb,
  plan                  jsonb not null default '[]'::jsonb,
  document_template_id  uuid references public.document_templates (id),
  updated_at            timestamptz not null default now(),   -- heure du téléphone
  server_updated_at     timestamptz not null default now(),   -- curseur de synchro
  deleted_at            timestamptz
);
create index student_works_user_idx on public.student_works (user_id, server_updated_at);
create trigger student_works_server_updated_at before insert or update on public.student_works
  for each row execute function public.tg_set_server_updated_at();

create table public.bibliography_entries (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  work_id            uuid references public.student_works (id) on delete cascade,
  kind               public.source_kind not null,
  data               jsonb not null check (jsonb_typeof(data) = 'object'),
  updated_at         timestamptz not null default now(),
  server_updated_at  timestamptz not null default now(),
  deleted_at         timestamptz
);
create index bibliography_entries_user_idx on public.bibliography_entries (user_id, server_updated_at);
create trigger bibliography_entries_server_updated_at before insert or update on public.bibliography_entries
  for each row execute function public.tg_set_server_updated_at();

-- -----------------------------------------------------------------------------
-- Commerce : offres, prix, ambassadeurs, codes promo
-- -----------------------------------------------------------------------------
create table public.products (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique check (code ~ '^[A-Z0-9_]+$'),
  name              text not null,
  description       text,
  kind              public.product_kind not null,
  feature           public.feature not null,
  -- true : l'achat porte sur un modèle précis (resource_id obligatoire).
  requires_resource boolean not null default false,
  -- null = accès permanent ; 365 pour le Pack Finaliste.
  duration_days     int check (duration_days is null or duration_days > 0),
  play_product_id   text unique,
  apple_product_id  text unique,
  is_active         boolean not null default true,
  position          int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (not requires_resource or feature in ('doc_template', 'questionnaire', 'cover_page'))
);
create trigger products_updated_at before update on public.products
  for each row execute function public.tg_set_updated_at();

create table public.product_prices (
  product_id    uuid not null references public.products (id) on delete cascade,
  currency      public.currency not null,
  amount_minor  bigint not null check (amount_minor > 0),
  updated_at    timestamptz not null default now(),
  primary key (product_id, currency)
);
create trigger product_prices_updated_at before update on public.product_prices
  for each row execute function public.tg_set_updated_at();

create table public.ambassadors (
  id              uuid primary key default gen_random_uuid(),
  full_name       text not null,
  phone           text not null,
  institution_id  uuid references public.institutions (id),
  payout_msisdn   text,                       -- numéro mobile money pour les commissions
  payout_operator public.mm_operator,
  user_id         uuid references auth.users (id) on delete set null,
  is_active       boolean not null default true,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create trigger ambassadors_updated_at before update on public.ambassadors
  for each row execute function public.tg_set_updated_at();

create table public.promo_codes (
  id                  uuid primary key default gen_random_uuid(),
  code                text not null unique check (code ~ '^[A-Z0-9_-]{3,32}$'),
  ambassador_id       uuid references public.ambassadors (id) on delete set null,
  -- Réduction pour l'acheteur, en pourcentage du prix (0 à 90 %).
  discount_percent    numeric(5,2) not null default 0 check (discount_percent between 0 and 90),
  -- Commission de l'ambassadeur, en pourcentage du montant payé (0 à 100 %).
  commission_percent  numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  applies_to          uuid[],                 -- null = toutes les offres
  valid_from          timestamptz,
  valid_to            timestamptz,
  max_uses            int check (max_uses is null or max_uses > 0),
  uses_count          int not null default 0,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger promo_codes_updated_at before update on public.promo_codes
  for each row execute function public.tg_set_updated_at();

-- -----------------------------------------------------------------------------
-- Paiements, journal des webhooks, droits d'accès, commissions
-- -----------------------------------------------------------------------------
create table public.payments (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users (id) on delete restrict,
  product_id          uuid not null references public.products (id),
  resource_id         uuid,
  channel             public.payment_channel not null,
  provider            public.payment_provider not null,
  currency            public.currency not null,
  amount_gross_minor  bigint not null check (amount_gross_minor >= 0),
  discount_minor      bigint not null default 0 check (discount_minor >= 0),
  amount_net_minor    bigint not null check (amount_net_minor >= 0),
  promo_code_id       uuid references public.promo_codes (id),
  msisdn              text,
  operator            public.mm_operator,
  status              public.payment_status not null default 'pending',
  provider_reference  text,
  failure_reason      text,
  idempotency_key     text not null unique,
  expires_at          timestamptz not null default (now() + interval '10 minutes'),
  confirmed_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (amount_net_minor = amount_gross_minor - discount_minor)
);
create index payments_user_idx on public.payments (user_id, created_at desc);
create index payments_status_idx on public.payments (status, expires_at);
create index payments_confirmed_idx on public.payments (confirmed_at) where status = 'succeeded';
create unique index payments_provider_ref_uidx on public.payments (provider, provider_reference)
  where provider_reference is not null;
create trigger payments_updated_at before update on public.payments
  for each row execute function public.tg_set_updated_at();

create table public.payment_events (
  id                 uuid primary key default gen_random_uuid(),
  provider           public.payment_provider not null,
  provider_event_id  text not null,
  payment_id         uuid references public.payments (id),
  payload            jsonb not null,
  received_at        timestamptz not null default now(),
  unique (provider, provider_event_id)       -- base de l'idempotence des webhooks
);

create table public.entitlements (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  product_id   uuid not null references public.products (id),
  feature      public.feature not null,
  resource_id  uuid,                           -- null = toute la fonction
  starts_at    timestamptz not null default now(),
  expires_at   timestamptz,                    -- null = permanent
  source       public.entitlement_source not null,
  payment_id   uuid unique references public.payments (id),
  granted_by   uuid references auth.users (id),
  revoked_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (expires_at is null or expires_at > starts_at)
);
create index entitlements_user_idx on public.entitlements (user_id, feature);
create trigger entitlements_updated_at before update on public.entitlements
  for each row execute function public.tg_set_updated_at();

create table public.commissions (
  id              uuid primary key default gen_random_uuid(),
  ambassador_id   uuid not null references public.ambassadors (id),
  payment_id      uuid not null unique references public.payments (id),
  currency        public.currency not null,
  amount_minor    bigint not null check (amount_minor >= 0),
  status          public.commission_status not null default 'due',
  paid_at         timestamptz,
  paid_reference  text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index commissions_ambassador_idx on public.commissions (ambassador_id, status);
create trigger commissions_updated_at before update on public.commissions
  for each row execute function public.tg_set_updated_at();
