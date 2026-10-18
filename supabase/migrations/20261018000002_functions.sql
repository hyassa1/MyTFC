-- =============================================================================
-- MonTFC — Migration 2 : fonctions SQL
-- -----------------------------------------------------------------------------
-- Toutes les fonctions SECURITY DEFINER fixent search_path pour éviter les
-- détournements. Les fonctions « serveur » (paiement, appareils) ne sont
-- exécutables que par service_role (voir migration 3, section GRANT).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Création automatique du profil à l'inscription (OTP par téléphone)
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, phone)
  values (new.id, new.phone)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- L'étudiant peut modifier son profil, sauf le téléphone et l'appareil actif,
-- qui ne changent que par le serveur.
create or replace function public.tg_protect_profile_columns()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.phone := old.phone;
    new.active_device_id := old.active_device_id;
    new.id := old.id;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_columns before update on public.profiles
  for each row execute function public.tg_protect_profile_columns();

-- -----------------------------------------------------------------------------
-- Rôles et droits d'accès
-- -----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.app_admins where user_id = auth.uid());
$$;

-- Vrai si l'utilisateur connecté a un droit actif sur la fonction demandée
-- (et, le cas échéant, sur le modèle précis). Le Pack Finaliste (feature 'all')
-- ouvre tout.
create or replace function public.has_access(p_feature public.feature, p_resource uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.entitlements e
    where e.user_id = auth.uid()
      and e.revoked_at is null
      and e.starts_at <= now()
      and (e.expires_at is null or e.expires_at > now())
      and (
        e.feature = 'all'
        or (e.feature = p_feature and (e.resource_id is null or e.resource_id = p_resource))
      )
  );
$$;

-- -----------------------------------------------------------------------------
-- Appareil unique : appelé par l'Edge Function claim-device après la connexion.
-- Révoque les autres appareils ; l'Edge Function ferme ensuite leurs sessions.
-- -----------------------------------------------------------------------------
create or replace function public.claim_device(
  p_user_id     uuid,
  p_device_id   text,
  p_platform    text,
  p_model       text default null,
  p_app_version text default null,
  p_app_flavor  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_previous text;
begin
  select active_device_id into v_previous from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  insert into public.user_devices (user_id, device_id, platform, model, app_version, app_flavor)
  values (p_user_id, p_device_id, p_platform, p_model, p_app_version, p_app_flavor)
  on conflict (user_id, device_id) do update
    set last_seen_at = now(),
        revoked_at   = null,
        platform     = excluded.platform,
        model        = coalesce(excluded.model, user_devices.model),
        app_version  = coalesce(excluded.app_version, user_devices.app_version),
        app_flavor   = coalesce(excluded.app_flavor, user_devices.app_flavor);

  update public.user_devices
     set revoked_at = now()
   where user_id = p_user_id and device_id <> p_device_id and revoked_at is null;

  update public.profiles set active_device_id = p_device_id where id = p_user_id;

  return jsonb_build_object(
    'device_id', p_device_id,
    'previous_device_id', v_previous,
    'other_devices_revoked', v_previous is distinct from p_device_id
  );
end;
$$;

-- L'application vérifie à chaque reprise qu'elle est toujours l'appareil actif.
create or replace function public.is_active_device(p_device_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select active_device_id = p_device_id from public.profiles where id = auth.uid()),
    false
  );
$$;

-- -----------------------------------------------------------------------------
-- Prix : calculé uniquement côté serveur (l'application n'envoie jamais de montant)
-- -----------------------------------------------------------------------------
create or replace function public.quote_price(
  p_product_id  uuid,
  p_currency    public.currency,
  p_promo_code  text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_product   public.products;
  v_gross     bigint;
  v_promo     public.promo_codes;
  v_discount  bigint := 0;
  v_net       bigint;
  v_promo_err text;
begin
  select * into v_product from public.products where id = p_product_id and is_active;
  if not found then
    raise exception 'product_not_found' using errcode = 'P0002';
  end if;

  select amount_minor into v_gross
    from public.product_prices where product_id = p_product_id and currency = p_currency;
  if v_gross is null then
    raise exception 'price_not_found' using errcode = 'P0002';
  end if;

  if p_promo_code is not null and btrim(p_promo_code) <> '' then
    select * into v_promo from public.promo_codes where code = upper(btrim(p_promo_code));
    if not found or not v_promo.is_active then
      v_promo_err := 'promo_invalid';
    elsif v_promo.valid_from is not null and now() < v_promo.valid_from then
      v_promo_err := 'promo_not_started';
    elsif v_promo.valid_to is not null and now() > v_promo.valid_to then
      v_promo_err := 'promo_expired';
    elsif v_promo.max_uses is not null and v_promo.uses_count >= v_promo.max_uses then
      v_promo_err := 'promo_exhausted';
    elsif v_promo.applies_to is not null and not (p_product_id = any (v_promo.applies_to)) then
      v_promo_err := 'promo_not_applicable';
    else
      v_discount := round(v_gross * v_promo.discount_percent / 100.0);
    end if;
  end if;

  v_net := v_gross - v_discount;

  return jsonb_build_object(
    'product_id', p_product_id,
    'currency', p_currency,
    'amount_gross_minor', v_gross,
    'discount_minor', v_discount,
    'amount_net_minor', v_net,
    'promo_code_id', case when v_promo_err is null then v_promo.id end,
    'promo_error', v_promo_err
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Paiement : création (appelée par payment-init avec service_role)
-- -----------------------------------------------------------------------------
create or replace function public.create_payment(
  p_user_id          uuid,
  p_product_id       uuid,
  p_resource_id      uuid,
  p_currency         public.currency,
  p_channel          public.payment_channel,
  p_provider         public.payment_provider,
  p_msisdn           text,
  p_operator         public.mm_operator,
  p_promo_code       text,
  p_idempotency_key  text,
  p_ttl_minutes      int default 10
)
returns public.payments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing public.payments;
  v_product  public.products;
  v_quote    jsonb;
  v_payment  public.payments;
begin
  -- Même clé d'idempotence = même paiement (double clic, nouvelle tentative réseau).
  select * into v_existing from public.payments where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.user_id <> p_user_id then
      raise exception 'idempotency_key_conflict' using errcode = '23505';
    end if;
    return v_existing;
  end if;

  select * into v_product from public.products where id = p_product_id and is_active;
  if not found then
    raise exception 'product_not_found' using errcode = 'P0002';
  end if;

  if v_product.requires_resource and p_resource_id is null then
    raise exception 'resource_required' using errcode = '22023';
  end if;
  if not v_product.requires_resource and p_resource_id is not null then
    raise exception 'resource_not_allowed' using errcode = '22023';
  end if;
  if v_product.requires_resource then
    if (v_product.feature = 'doc_template'
          and not exists (select 1 from public.document_templates
                           where id = p_resource_id and is_published and deleted_at is null))
       or (v_product.feature = 'questionnaire'
          and not exists (select 1 from public.questionnaire_templates
                           where id = p_resource_id and is_published and deleted_at is null))
       or (v_product.feature = 'cover_page'
          and not exists (select 1 from public.cover_templates
                           where id = p_resource_id and is_published and deleted_at is null)) then
      raise exception 'resource_not_found' using errcode = 'P0002';
    end if;
  end if;

  -- quote_price ne dépend pas de auth.uid() : appel sûr depuis service_role.
  v_quote := public.quote_price(p_product_id, p_currency, p_promo_code);
  if v_quote->>'promo_error' is not null then
    raise exception '%', v_quote->>'promo_error' using errcode = '22023';
  end if;

  insert into public.payments (
    user_id, product_id, resource_id, channel, provider, currency,
    amount_gross_minor, discount_minor, amount_net_minor, promo_code_id,
    msisdn, operator, status, idempotency_key, expires_at
  ) values (
    p_user_id, p_product_id, p_resource_id, p_channel, p_provider, p_currency,
    (v_quote->>'amount_gross_minor')::bigint,
    (v_quote->>'discount_minor')::bigint,
    (v_quote->>'amount_net_minor')::bigint,
    (v_quote->>'promo_code_id')::uuid,
    p_msisdn, p_operator, 'pending', p_idempotency_key,
    now() + make_interval(mins => p_ttl_minutes)
  )
  returning * into v_payment;

  return v_payment;
end;
$$;

-- Enregistre la référence de l'agrégateur après l'appel initiate().
create or replace function public.mark_payment_processing(
  p_payment_id uuid,
  p_provider_reference text
)
returns public.payments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment public.payments;
begin
  update public.payments
     set status = 'processing',
         provider_reference = coalesce(provider_reference, p_provider_reference)
   where id = p_payment_id and status = 'pending'
  returning * into v_payment;

  if not found then
    select * into v_payment from public.payments where id = p_payment_id;
  end if;
  return v_payment;
end;
$$;

-- Journal des webhooks : renvoie false si l'événement a déjà été reçu.
create or replace function public.record_payment_event(
  p_provider          public.payment_provider,
  p_provider_event_id text,
  p_payment_id        uuid,
  p_payload           jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.payment_events (provider, provider_event_id, payment_id, payload)
  values (p_provider, p_provider_event_id, p_payment_id, p_payload)
  on conflict (provider, provider_event_id) do nothing;
  return found;
end;
$$;

-- Accorde le droit d'accès correspondant à un paiement réussi.
-- Pour une offre à durée (Pack Finaliste), un renouvellement prolonge à partir
-- de la fin du droit en cours au lieu de la perdre.
create or replace function public._grant_entitlement_for_payment(p_payment public.payments)
returns public.entitlements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_product  public.products;
  v_start    timestamptz := now();
  v_ent      public.entitlements;
begin
  select * into v_product from public.products where id = p_payment.product_id;

  if v_product.duration_days is not null then
    select greatest(now(), coalesce(max(expires_at), now())) into v_start
      from public.entitlements
     where user_id = p_payment.user_id
       and feature = v_product.feature
       and resource_id is not distinct from p_payment.resource_id
       and revoked_at is null
       and expires_at > now();
  end if;

  insert into public.entitlements (
    user_id, product_id, feature, resource_id, starts_at, expires_at, source, payment_id
  ) values (
    p_payment.user_id, v_product.id, v_product.feature, p_payment.resource_id, v_start,
    case when v_product.duration_days is null then null
         else v_start + make_interval(days => v_product.duration_days) end,
    case when p_payment.channel in ('google_play', 'app_store') then 'store'::public.entitlement_source
         when p_payment.channel = 'admin' then 'admin_grant'::public.entitlement_source
         else 'payment'::public.entitlement_source end,
    p_payment.id
  )
  on conflict (payment_id) do nothing
  returning * into v_ent;

  return v_ent;
end;
$$;

-- -----------------------------------------------------------------------------
-- Confirmation d'un paiement : UNE transaction, idempotente.
--   * Une double notification ne crée ni deux droits ni deux commissions.
--   * Un paiement passé en « expired » (délai dépassé) mais finalement débité
--     chez l'opérateur est quand même débloqué : l'étudiant a payé.
--   * Un paiement « failed » ou « cancelled » n'est jamais débloqué ici.
-- -----------------------------------------------------------------------------
create or replace function public.confirm_payment(
  p_payment_id          uuid,
  p_provider_reference  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment     public.payments;
  v_promo       public.promo_codes;
  v_ent         public.entitlements;
  v_commission  bigint;
begin
  update public.payments
     set status = 'succeeded',
         confirmed_at = now(),
         failure_reason = null,
         provider_reference = coalesce(provider_reference, p_provider_reference)
   where id = p_payment_id
     and status in ('pending', 'processing', 'expired')
  returning * into v_payment;

  if not found then
    select * into v_payment from public.payments where id = p_payment_id;
    if not found then
      raise exception 'payment_not_found' using errcode = 'P0002';
    end if;
    return jsonb_build_object(
      'payment_id', v_payment.id,
      'status', v_payment.status,
      'already_processed', true
    );
  end if;

  v_ent := public._grant_entitlement_for_payment(v_payment);

  if v_payment.promo_code_id is not null then
    update public.promo_codes set uses_count = uses_count + 1
     where id = v_payment.promo_code_id
    returning * into v_promo;

    if v_promo.ambassador_id is not null and v_promo.commission_percent > 0 then
      v_commission := round(v_payment.amount_net_minor * v_promo.commission_percent / 100.0);
      insert into public.commissions (ambassador_id, payment_id, currency, amount_minor)
      values (v_promo.ambassador_id, v_payment.id, v_payment.currency, v_commission)
      on conflict (payment_id) do nothing;
    end if;
  end if;

  return jsonb_build_object(
    'payment_id', v_payment.id,
    'status', v_payment.status,
    'already_processed', false,
    'entitlement_id', v_ent.id
  );
end;
$$;

-- Échec, annulation ou expiration (idempotent ; ne touche jamais un paiement réussi).
create or replace function public.fail_payment(
  p_payment_id  uuid,
  p_status      public.payment_status,
  p_reason      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment public.payments;
begin
  if p_status not in ('failed', 'expired', 'cancelled') then
    raise exception 'invalid_failure_status' using errcode = '22023';
  end if;

  update public.payments
     set status = p_status, failure_reason = p_reason
   where id = p_payment_id and status in ('pending', 'processing')
  returning * into v_payment;

  if not found then
    select * into v_payment from public.payments where id = p_payment_id;
    if not found then
      raise exception 'payment_not_found' using errcode = 'P0002';
    end if;
    return jsonb_build_object('payment_id', v_payment.id, 'status', v_payment.status, 'already_processed', true);
  end if;

  return jsonb_build_object('payment_id', v_payment.id, 'status', v_payment.status, 'already_processed', false);
end;
$$;

-- Appelée par pg_cron : passe en « expired » les paiements restés en attente.
create or replace function public.expire_stale_payments()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
begin
  update public.payments
     set status = 'expired', failure_reason = 'timeout'
   where status in ('pending', 'processing') and expires_at < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Achat Google Play / App Store déjà vérifié par l'Edge Function
-- verify-store-purchase. Idempotent sur (provider, provider_reference).
create or replace function public.grant_store_purchase(
  p_user_id             uuid,
  p_product_id          uuid,
  p_resource_id         uuid,
  p_provider            public.payment_provider,
  p_provider_reference  text,
  p_currency            public.currency,
  p_amount_minor        bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment public.payments;
begin
  if p_provider not in ('google', 'apple') then
    raise exception 'invalid_store_provider' using errcode = '22023';
  end if;

  select * into v_payment from public.payments
   where provider = p_provider and provider_reference = p_provider_reference;

  if not found then
    insert into public.payments (
      user_id, product_id, resource_id, channel, provider, currency,
      amount_gross_minor, discount_minor, amount_net_minor,
      status, provider_reference, idempotency_key
    ) values (
      p_user_id, p_product_id, p_resource_id,
      case when p_provider = 'google' then 'google_play'::public.payment_channel
           else 'app_store'::public.payment_channel end,
      p_provider, p_currency, p_amount_minor, 0, p_amount_minor,
      'pending', p_provider_reference, p_provider::text || ':' || p_provider_reference
    )
    returning * into v_payment;
  elsif v_payment.user_id <> p_user_id then
    raise exception 'store_purchase_owned_by_other_user' using errcode = '42501';
  end if;

  return public.confirm_payment(v_payment.id, p_provider_reference);
end;
$$;

-- Attribution manuelle d'un droit depuis l'admin (geste commercial, litige).
create or replace function public.admin_grant_entitlement(
  p_user_id      uuid,
  p_product_id   uuid,
  p_resource_id  uuid default null,
  p_reason       text default null
)
returns public.entitlements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment public.payments;
  v_ent     public.entitlements;
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  insert into public.payments (
    user_id, product_id, resource_id, channel, provider, currency,
    amount_gross_minor, discount_minor, amount_net_minor, status,
    failure_reason, idempotency_key, confirmed_at
  ) values (
    p_user_id, p_product_id, p_resource_id, 'admin', 'admin', 'USD', 0, 0, 0, 'succeeded',
    p_reason, 'admin:' || gen_random_uuid()::text, now()
  )
  returning * into v_payment;

  v_ent := public._grant_entitlement_for_payment(v_payment);
  update public.entitlements set granted_by = auth.uid() where id = v_ent.id
  returning * into v_ent;
  return v_ent;
end;
$$;

-- -----------------------------------------------------------------------------
-- Synchronisation hors ligne
-- -----------------------------------------------------------------------------

-- Renvoie en un seul appel tout ce qui a changé depuis p_since (null = tout).
-- SECURITY INVOKER : la RLS s'applique, les corps des modèles payants ne
-- sortent que pour les ayants droit.
create or replace function public.sync_changes(p_since timestamptz default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_now        timestamptz := now();
  v_since      timestamptz := coalesce(p_since, '-infinity'::timestamptz);
  v_body_since timestamptz;
  v_uid        uuid := auth.uid();
begin
  -- Si les droits de l'utilisateur ont changé (achat, expiration, révocation),
  -- on renvoie tous les corps accessibles : un modèle débloqué aujourd'hui
  -- peut ne pas avoir été modifié depuis longtemps.
  if v_uid is not null and exists (
      select 1 from public.entitlements
       where user_id = v_uid
         and (updated_at > v_since
              or (expires_at is not null and expires_at between v_since and v_now))
  ) then
    v_body_since := '-infinity'::timestamptz;
  else
    v_body_since := v_since;
  end if;

  return jsonb_build_object(
    'server_time', v_now,
    'institutions', coalesce((select jsonb_agg(to_jsonb(t)) from public.institutions t
                               where t.updated_at > v_since), '[]'::jsonb),
    'settings', coalesce((select jsonb_object_agg(t.key, t.value) from public.app_settings t
                           where t.is_public and t.updated_at > v_since), '{}'::jsonb),
    'guide_chapters', coalesce((select jsonb_agg(to_jsonb(t)) from public.guide_chapters t
                                 where t.updated_at > v_since), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(t)) from public.products t
                           where t.updated_at > v_since), '[]'::jsonb),
    'product_prices', coalesce((select jsonb_agg(to_jsonb(t)) from public.product_prices t
                                 where t.updated_at > v_since), '[]'::jsonb),
    'cover_templates', coalesce((select jsonb_agg(to_jsonb(t)) from public.cover_templates t
                                  where t.updated_at > v_since), '[]'::jsonb),
    'document_templates', coalesce((select jsonb_agg(to_jsonb(t)) from public.document_templates t
                                     where t.updated_at > v_since), '[]'::jsonb),
    'questionnaire_templates', coalesce((select jsonb_agg(to_jsonb(t)) from public.questionnaire_templates t
                                          where t.updated_at > v_since), '[]'::jsonb),
    -- Corps payants : filtrés par la RLS (has_access).
    'cover_template_bodies', coalesce((select jsonb_agg(to_jsonb(t)) from public.cover_template_bodies t
                                        where t.updated_at > v_body_since), '[]'::jsonb),
    'document_template_bodies', coalesce((select jsonb_agg(to_jsonb(t)) from public.document_template_bodies t
                                           where t.updated_at > v_body_since), '[]'::jsonb),
    'questionnaire_template_bodies', coalesce((select jsonb_agg(to_jsonb(t)) from public.questionnaire_template_bodies t
                                                where t.updated_at > v_body_since), '[]'::jsonb),
    -- Données de l'utilisateur (filtrées par la RLS).
    'profile', (select to_jsonb(t) from public.profiles t where t.id = v_uid),
    'entitlements', coalesce((select jsonb_agg(to_jsonb(t)) from public.entitlements t
                               where t.user_id = v_uid), '[]'::jsonb),
    'student_works', coalesce((select jsonb_agg(to_jsonb(t)) from public.student_works t
                                where t.user_id = v_uid and t.server_updated_at > v_since), '[]'::jsonb),
    'bibliography_entries', coalesce((select jsonb_agg(to_jsonb(t)) from public.bibliography_entries t
                                       where t.user_id = v_uid and t.server_updated_at > v_since), '[]'::jsonb)
  );
end;
$$;

-- Envoi des modifications faites hors ligne. Règle : la dernière modification
-- (updated_at du téléphone) gagne. SECURITY INVOKER : la RLS garantit que
-- l'étudiant n'écrit que ses propres lignes.
create or replace function public.push_changes(
  p_works    jsonb default '[]'::jsonb,
  p_entries  jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_works    int := 0;
  v_entries  int := 0;
  v_n        int;
  v_item     jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_works, '[]'::jsonb)) loop
    insert into public.student_works as w (
      id, user_id, title, work_type, director, supervisor, cover_template_id,
      cover_data, plan, document_template_id, updated_at, deleted_at
    ) values (
      (v_item->>'id')::uuid, v_uid,
      v_item->>'title',
      (v_item->>'work_type')::public.work_type,
      v_item->>'director',
      v_item->>'supervisor',
      (v_item->>'cover_template_id')::uuid,
      coalesce(v_item->'cover_data', '{}'::jsonb),
      coalesce(v_item->'plan', '[]'::jsonb),
      (v_item->>'document_template_id')::uuid,
      coalesce((v_item->>'updated_at')::timestamptz, now()),
      (v_item->>'deleted_at')::timestamptz
    )
    on conflict (id) do update set
      title = excluded.title,
      work_type = excluded.work_type,
      director = excluded.director,
      supervisor = excluded.supervisor,
      cover_template_id = excluded.cover_template_id,
      cover_data = excluded.cover_data,
      plan = excluded.plan,
      document_template_id = excluded.document_template_id,
      updated_at = excluded.updated_at,
      deleted_at = excluded.deleted_at
    where w.user_id = v_uid and excluded.updated_at > w.updated_at;
    get diagnostics v_n = row_count;
    v_works := v_works + v_n;
  end loop;

  for v_item in select * from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) loop
    insert into public.bibliography_entries as b (
      id, user_id, work_id, kind, data, updated_at, deleted_at
    ) values (
      (v_item->>'id')::uuid, v_uid,
      (v_item->>'work_id')::uuid,
      (v_item->>'kind')::public.source_kind,
      coalesce(v_item->'data', '{}'::jsonb),
      coalesce((v_item->>'updated_at')::timestamptz, now()),
      (v_item->>'deleted_at')::timestamptz
    )
    on conflict (id) do update set
      work_id = excluded.work_id,
      kind = excluded.kind,
      data = excluded.data,
      updated_at = excluded.updated_at,
      deleted_at = excluded.deleted_at
    where b.user_id = v_uid and excluded.updated_at > b.updated_at;
    get diagnostics v_n = row_count;
    v_entries := v_entries + v_n;
  end loop;

  return jsonb_build_object('works_applied', v_works, 'entries_applied', v_entries, 'server_time', now());
end;
$$;

-- -----------------------------------------------------------------------------
-- Tableau de bord d'administration (admins uniquement)
-- -----------------------------------------------------------------------------
create or replace function public._require_admin()
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.admin_dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require_admin();
  return jsonb_build_object(
    'users_total', (select count(*) from public.profiles),
    'users_last_7_days', (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'payments_today', (select count(*) from public.payments
                        where status = 'succeeded' and channel <> 'admin'
                          and confirmed_at >= date_trunc('day', now())),
    'revenue_last_30_days', coalesce((
        select jsonb_object_agg(currency, total) from (
          select currency, sum(amount_net_minor) as total from public.payments
           where status = 'succeeded' and channel <> 'admin'
             and confirmed_at > now() - interval '30 days'
           group by currency) s), '{}'::jsonb),
    'commissions_due', coalesce((
        select jsonb_object_agg(currency, total) from (
          select currency, sum(amount_minor) as total from public.commissions
           where status = 'due' group by currency) s), '{}'::jsonb),
    'active_packs', (select count(distinct user_id) from public.entitlements
                      where feature = 'all' and revoked_at is null
                        and starts_at <= now() and (expires_at is null or expires_at > now()))
  );
end;
$$;

create or replace function public.admin_signups_daily(p_from date, p_to date)
returns table (day date, signups bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require_admin();
  return query
    select d::date, count(p.id)
      from generate_series(p_from, p_to, interval '1 day') d
      left join public.profiles p on p.created_at >= d and p.created_at < d + interval '1 day'
     group by d order by d;
end;
$$;

create or replace function public.admin_sales_daily(p_from date, p_to date)
returns table (day date, currency public.currency, purchases bigint, revenue_minor bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require_admin();
  return query
    select (p.confirmed_at at time zone 'Africa/Kinshasa')::date, p.currency,
           count(*), sum(p.amount_net_minor)::bigint
      from public.payments p
     where p.status = 'succeeded' and p.channel <> 'admin'
       and (p.confirmed_at at time zone 'Africa/Kinshasa')::date between p_from and p_to
     group by 1, 2 order by 1, 2;
end;
$$;

create or replace function public.admin_revenue_by_institution(p_from date, p_to date)
returns table (institution_code text, institution_name text, currency public.currency,
               purchases bigint, revenue_minor bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require_admin();
  return query
    select coalesce(i.code, 'AUTRE'), coalesce(i.name, 'Autre / non renseigné'), p.currency,
           count(*), sum(p.amount_net_minor)::bigint
      from public.payments p
      join public.profiles pr on pr.id = p.user_id
      left join public.institutions i on i.id = pr.institution_id
     where p.status = 'succeeded' and p.channel <> 'admin'
       and (p.confirmed_at at time zone 'Africa/Kinshasa')::date between p_from and p_to
     group by 1, 2, 3 order by 5 desc;
end;
$$;

create or replace function public.admin_commissions_due()
returns table (ambassador_id uuid, full_name text, payout_msisdn text,
               currency public.currency, sales bigint, amount_minor bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require_admin();
  return query
    select a.id, a.full_name, a.payout_msisdn, c.currency, count(*), sum(c.amount_minor)::bigint
      from public.commissions c
      join public.ambassadors a on a.id = c.ambassador_id
     where c.status = 'due'
     group by 1, 2, 3, 4 order by 6 desc;
end;
$$;

-- Marque comme payées les commissions dues d'un ambassadeur (après virement).
create or replace function public.admin_mark_commissions_paid(
  p_ambassador_id uuid,
  p_currency      public.currency,
  p_reference     text
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
begin
  perform public._require_admin();
  update public.commissions
     set status = 'paid', paid_at = now(), paid_reference = p_reference
   where ambassador_id = p_ambassador_id and currency = p_currency and status = 'due';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
