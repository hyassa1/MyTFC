-- =============================================================================
-- MonTFC — Migration 3 : sécurité (RLS et droits d'exécution)
-- -----------------------------------------------------------------------------
-- Principe : RLS activée partout. service_role (Edge Functions) contourne la
-- RLS ; anon et authenticated ne voient que ce que les politiques autorisent.
-- Les droits d'accès (entitlements), paiements et commissions ne sont JAMAIS
-- modifiables depuis l'application.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Activation de la RLS
-- -----------------------------------------------------------------------------
alter table public.institutions                  enable row level security;
alter table public.app_settings                  enable row level security;
alter table public.app_admins                    enable row level security;
alter table public.profiles                      enable row level security;
alter table public.user_devices                  enable row level security;
alter table public.guide_chapters                enable row level security;
alter table public.cover_templates               enable row level security;
alter table public.cover_template_bodies         enable row level security;
alter table public.document_templates            enable row level security;
alter table public.document_template_bodies      enable row level security;
alter table public.questionnaire_templates       enable row level security;
alter table public.questionnaire_template_bodies enable row level security;
alter table public.student_works                 enable row level security;
alter table public.bibliography_entries          enable row level security;
alter table public.products                      enable row level security;
alter table public.product_prices                enable row level security;
alter table public.ambassadors                   enable row level security;
alter table public.promo_codes                   enable row level security;
alter table public.payments                      enable row level security;
alter table public.payment_events                enable row level security;
alter table public.entitlements                  enable row level security;
alter table public.commissions                   enable row level security;

-- -----------------------------------------------------------------------------
-- Contenu public (catalogue, guide) : lecture pour tous, écriture admin.
-- Les métadonnées des brouillons restent lisibles (titre, description) ;
-- l'application n'affiche que is_published et deleted_at null. Les corps
-- payants, eux, sont protégés par les politiques *_bodies ci-dessous.
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'institutions', 'guide_chapters', 'cover_templates', 'document_templates',
    'questionnaire_templates', 'products', 'product_prices'
  ] loop
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)',
                   t || '_read_all', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())',
                   t || '_admin_write', t);
  end loop;
end;
$$;

create policy app_settings_read_public on public.app_settings
  for select to anon, authenticated using (is_public or public.is_admin());
create policy app_settings_admin_write on public.app_settings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- -----------------------------------------------------------------------------
-- Corps des modèles payants : uniquement les ayants droit (ou admin)
-- -----------------------------------------------------------------------------
create policy cover_template_bodies_read on public.cover_template_bodies
  for select to authenticated
  using (public.is_admin() or public.has_access('cover_page', template_id));
create policy cover_template_bodies_admin_write on public.cover_template_bodies
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy document_template_bodies_read on public.document_template_bodies
  for select to authenticated
  using (public.is_admin() or public.has_access('doc_template', template_id));
create policy document_template_bodies_admin_write on public.document_template_bodies
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy questionnaire_template_bodies_read on public.questionnaire_template_bodies
  for select to authenticated
  using (public.is_admin() or public.has_access('questionnaire', template_id));
create policy questionnaire_template_bodies_admin_write on public.questionnaire_template_bodies
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- -----------------------------------------------------------------------------
-- Admins
-- -----------------------------------------------------------------------------
create policy app_admins_read_self on public.app_admins
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
-- Pas de politique d'écriture : on ajoute un admin depuis le SQL Editor de
-- Supabase (voir README), jamais depuis l'application.

-- -----------------------------------------------------------------------------
-- Profil et appareils
-- -----------------------------------------------------------------------------
create policy profiles_read_own on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());
-- Mise à jour par le propriétaire ; téléphone et appareil actif protégés par
-- le déclencheur profiles_protect_columns.
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy user_devices_read_own on public.user_devices
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- -----------------------------------------------------------------------------
-- Travail de l'étudiant : propriétaire uniquement
-- -----------------------------------------------------------------------------
create policy student_works_owner on public.student_works
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy bibliography_entries_owner on public.bibliography_entries
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- Commerce : lecture seule pour le propriétaire, aucune écriture côté app
-- -----------------------------------------------------------------------------
create policy payments_read_own on public.payments
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

create policy entitlements_read_own on public.entitlements
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

create policy payment_events_admin_read on public.payment_events
  for select to authenticated using (public.is_admin());

create policy ambassadors_admin on public.ambassadors
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Les codes promo ne sont pas listables par l'application : la validation
-- passe par quote_price().
create policy promo_codes_admin on public.promo_codes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy commissions_admin_read on public.commissions
  for select to authenticated using (public.is_admin());
create policy commissions_admin_update on public.commissions
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- -----------------------------------------------------------------------------
-- Droits d'exécution des fonctions
-- Supabase accorde par défaut EXECUTE à anon et authenticated sur les fonctions
-- de public : on retire ce droit aux fonctions réservées au serveur.
-- -----------------------------------------------------------------------------
revoke execute on function public.claim_device(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.create_payment(uuid, uuid, uuid, public.currency, public.payment_channel, public.payment_provider, text, public.mm_operator, text, text, int) from public, anon, authenticated;
revoke execute on function public.mark_payment_processing(uuid, text) from public, anon, authenticated;
revoke execute on function public.record_payment_event(public.payment_provider, text, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public._grant_entitlement_for_payment(public.payments) from public, anon, authenticated;
revoke execute on function public.confirm_payment(uuid, text) from public, anon, authenticated;
revoke execute on function public.fail_payment(uuid, public.payment_status, text) from public, anon, authenticated;
revoke execute on function public.expire_stale_payments() from public, anon, authenticated;
revoke execute on function public.grant_store_purchase(uuid, uuid, uuid, public.payment_provider, text, public.currency, bigint) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

grant execute on function public.claim_device(uuid, text, text, text, text, text) to service_role;
grant execute on function public.create_payment(uuid, uuid, uuid, public.currency, public.payment_channel, public.payment_provider, text, public.mm_operator, text, text, int) to service_role;
grant execute on function public.mark_payment_processing(uuid, text) to service_role;
grant execute on function public.record_payment_event(public.payment_provider, text, uuid, jsonb) to service_role;
grant execute on function public._grant_entitlement_for_payment(public.payments) to service_role;
grant execute on function public.confirm_payment(uuid, text) to service_role;
grant execute on function public.fail_payment(uuid, public.payment_status, text) to service_role;
grant execute on function public.expire_stale_payments() to service_role;
grant execute on function public.grant_store_purchase(uuid, uuid, uuid, public.payment_provider, text, public.currency, bigint) to service_role;

-- quote_price : utilisateurs connectés uniquement (évite le test de codes
-- promo par des visiteurs anonymes).
revoke execute on function public.quote_price(uuid, public.currency, text) from public, anon;
grant execute on function public.quote_price(uuid, public.currency, text) to authenticated, service_role;

-- Fonctions admin : elles vérifient is_admin() elles-mêmes ; anon n'en a pas besoin.
revoke execute on function public.admin_grant_entitlement(uuid, uuid, uuid, text) from public, anon;
revoke execute on function public.admin_dashboard_summary() from public, anon;
revoke execute on function public.admin_signups_daily(date, date) from public, anon;
revoke execute on function public.admin_sales_daily(date, date) from public, anon;
revoke execute on function public.admin_revenue_by_institution(date, date) from public, anon;
revoke execute on function public.admin_commissions_due() from public, anon;
revoke execute on function public.admin_mark_commissions_paid(uuid, public.currency, text) from public, anon;
grant execute on function public.admin_grant_entitlement(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.admin_dashboard_summary() to authenticated;
grant execute on function public.admin_signups_daily(date, date) to authenticated;
grant execute on function public.admin_sales_daily(date, date) to authenticated;
grant execute on function public.admin_revenue_by_institution(date, date) to authenticated;
grant execute on function public.admin_commissions_due() to authenticated;
grant execute on function public.admin_mark_commissions_paid(uuid, public.currency, text) to authenticated;

-- Synchro : utilisateurs connectés.
revoke execute on function public.push_changes(jsonb, jsonb) from public, anon;
grant execute on function public.push_changes(jsonb, jsonb) to authenticated;
