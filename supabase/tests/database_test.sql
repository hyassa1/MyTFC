-- =============================================================================
-- MonTFC — Tests de la base (RLS, droits d'accès, paiements, synchro)
-- -----------------------------------------------------------------------------
-- Exécution locale : ./tests/local/run_db_tests.sh (PostgreSQL 15+ requis).
-- Chaque test lève une exception en cas d'échec ; le script s'arrête alors.
-- Les tests tournent dans une transaction annulée à la fin (base inchangée).
-- =============================================================================
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

begin;

-- Utilisateurs de test (A, B et un admin).
insert into auth.users (id, phone) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '243810000001'),
  ('bbbbbbbb-0000-4000-8000-000000000002', '243840000002'),
  ('cccccccc-0000-4000-8000-000000000003', '243970000003');
insert into public.app_admins (user_id, role) values ('cccccccc-0000-4000-8000-000000000003', 'admin');

-- Raccourcis pour se mettre dans la peau d'un utilisateur.
create or replace function pg_temp.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end; $$;
create or replace function pg_temp.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end; $$;
create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('role', 'service_role', true);
end; $$;
create or replace function pg_temp.check(p_ok boolean, p_name text) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then
    raise exception 'ÉCHEC : %', p_name;
  end if;
  raise notice 'ok - %', p_name;
end; $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
\echo '# Profil créé automatiquement'
-- -----------------------------------------------------------------------------
select pg_temp.check((select count(*) from public.profiles) = 3, 'un profil par utilisateur');
select pg_temp.check((select phone from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000001') = '243810000001',
                     'le téléphone est recopié dans le profil');

-- -----------------------------------------------------------------------------
\echo '# Visiteur anonyme'
-- -----------------------------------------------------------------------------
select pg_temp.as_anon();
select pg_temp.check((select count(*) from public.guide_chapters where is_published) = 3, 'anon lit le guide');
select pg_temp.check((select count(*) from public.products) = 4, 'anon lit le catalogue');
select pg_temp.check((select count(*) from public.cover_template_bodies) = 0, 'anon ne lit aucun corps de modèle');
select pg_temp.check((select count(*) from public.promo_codes) = 0, 'anon ne liste pas les codes promo');
select pg_temp.check(jsonb_array_length(public.sync_changes(null)->'guide_chapters') = 3, 'anon synchronise le guide');
do $$ begin
  perform public.quote_price('00000000-0000-4000-8000-000000000504', 'USD', null);
  raise exception 'ÉCHEC : anon ne doit pas pouvoir appeler quote_price';
exception when insufficient_privilege then raise notice 'ok - anon ne peut pas appeler quote_price';
end $$;
reset role;

-- -----------------------------------------------------------------------------
\echo '# Étudiant A sans achat'
-- -----------------------------------------------------------------------------
select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
select pg_temp.check((select count(*) from public.cover_templates) = 3, 'A voit les 3 modèles de page de garde (métadonnées)');
select pg_temp.check((select count(*) from public.cover_template_bodies) = 0, 'A ne lit pas la mise en page sans achat');
select pg_temp.check((select count(*) from public.document_template_bodies) = 0, 'A ne lit pas le modèle de mémoire sans achat');
select pg_temp.check(not public.has_access('cover_page', '00000000-0000-4000-8000-000000000301'), 'has_access faux sans achat');
select pg_temp.check((select count(*) from public.profiles) = 1, 'A ne voit que son propre profil');

update public.profiles set full_name = 'Étudiant A', phone = '000', active_device_id = 'pirate'
 where id = 'aaaaaaaa-0000-4000-8000-000000000001';
select pg_temp.check((select full_name = 'Étudiant A' and phone = '243810000001' and active_device_id is null
                        from public.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
                     'A modifie son nom mais pas son téléphone ni son appareil actif');

do $$ begin
  insert into public.entitlements (user_id, product_id, feature, source)
  values ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000504', 'all', 'payment');
  raise exception 'ÉCHEC : A ne doit pas pouvoir s''accorder un droit';
exception when insufficient_privilege then raise notice 'ok - A ne peut pas s''accorder un droit (RLS)';
end $$;

do $$ begin
  perform public.confirm_payment(gen_random_uuid(), null);
  raise exception 'ÉCHEC : A ne doit pas pouvoir confirmer un paiement';
exception when insufficient_privilege then raise notice 'ok - A ne peut pas appeler confirm_payment';
end $$;

do $$ begin
  insert into public.payments (user_id, product_id, channel, provider, currency, amount_gross_minor,
                               amount_net_minor, status, idempotency_key)
  values ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000504',
          'mobile_money_app', 'mock', 'USD', 1, 1, 'succeeded', 'triche');
  raise exception 'ÉCHEC : A ne doit pas pouvoir créer un paiement';
exception when insufficient_privilege then raise notice 'ok - A ne peut pas écrire dans payments';
end $$;

-- Prix calculé côté serveur.
select pg_temp.check(
  (select q->>'amount_gross_minor' = '1000' and q->>'discount_minor' = '100' and q->>'amount_net_minor' = '900'
     from public.quote_price('00000000-0000-4000-8000-000000000504', 'USD', ' demo10 ') q),
  'quote_price applique le code promo (10 %), insensible à la casse et aux espaces');
select pg_temp.check(
  (select q->>'promo_error' = 'promo_invalid' and q->>'amount_net_minor' = '1000'
     from public.quote_price('00000000-0000-4000-8000-000000000504', 'USD', 'INCONNU') q),
  'code promo inconnu : prix plein et erreur explicite');
reset role;

-- -----------------------------------------------------------------------------
\echo '# Paiement mobile money de A (Pack Finaliste, code DEMO10)'
-- -----------------------------------------------------------------------------
select pg_temp.as_service();
create temporary table t_pay as
  select * from public.create_payment('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000504',
    null, 'USD', 'mobile_money_app', 'mock', '243810000001', 'vodacom', 'DEMO10', 'cle-a-1');
grant all on t_pay to anon, authenticated, service_role;

select pg_temp.check((select status = 'pending' and amount_net_minor = 900 from t_pay), 'paiement créé en attente, montant net 9,00 USD');
select pg_temp.check(
  (select id from public.create_payment('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000504',
    null, 'USD', 'mobile_money_app', 'mock', '243810000001', 'vodacom', 'DEMO10', 'cle-a-1')) = (select id from t_pay),
  'même clé d''idempotence = même paiement (double clic)');

select pg_temp.check((select status = 'processing' and provider_reference = 'REF-A-1'
                        from public.mark_payment_processing((select id from t_pay), 'REF-A-1')),
                     'paiement en cours avec la référence de l''agrégateur');

select pg_temp.check(public.record_payment_event('mock', 'EVT-1', (select id from t_pay), '{"ok":true}'), 'premier webhook enregistré');
select pg_temp.check(not public.record_payment_event('mock', 'EVT-1', (select id from t_pay), '{"ok":true}'), 'webhook en double détecté');

select pg_temp.check((public.confirm_payment((select id from t_pay), 'REF-A-1')->>'already_processed')::boolean = false,
                     'première confirmation : déblocage');
select pg_temp.check((public.confirm_payment((select id from t_pay), 'REF-A-1')->>'already_processed')::boolean = true,
                     'deuxième confirmation : rien de plus (idempotence)');
select pg_temp.check((select count(*) from public.entitlements where user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 1,
                     'un seul droit créé');
select pg_temp.check((select count(*) = 1 and sum(amount_minor) = 180 from public.commissions),
                     'une seule commission de 20 % sur 9,00 USD = 1,80 USD');
select pg_temp.check((select uses_count from public.promo_codes where code = 'DEMO10') = 1, 'utilisation du code comptée une fois');
select pg_temp.check((public.fail_payment((select id from t_pay), 'failed', 'tardif')->>'status') = 'succeeded',
                     'un échec tardif ne remet pas en cause un paiement réussi');
select pg_temp.check(
  (select expires_at between now() + interval '364 days' and now() + interval '366 days'
     from public.entitlements where payment_id = (select id from t_pay)),
  'Pack Finaliste valable 12 mois');
reset role;

-- -----------------------------------------------------------------------------
\echo '# A a maintenant accès à tout'
-- -----------------------------------------------------------------------------
select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
select pg_temp.check(public.has_access('cover_page', '00000000-0000-4000-8000-000000000301'), 'A : accès page de garde');
select pg_temp.check(public.has_access('doc_template', '00000000-0000-4000-8000-000000000401'), 'A : accès modèle de mémoire');
select pg_temp.check((select count(*) from public.cover_template_bodies) = 3, 'A lit les 3 mises en page');
select pg_temp.check((select count(*) from public.payments) = 1, 'A voit son historique d''achats');
select pg_temp.check(jsonb_array_length(public.sync_changes(null)->'cover_template_bodies') = 3, 'la synchro de A contient les corps débloqués');
reset role;

-- -----------------------------------------------------------------------------
\echo '# Étudiant B : isolement et paiement expiré puis confirmé'
-- -----------------------------------------------------------------------------
select pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
select pg_temp.check((select count(*) from public.payments) = 0, 'B ne voit pas les paiements de A');
select pg_temp.check((select count(*) from public.entitlements) = 0, 'B ne voit pas les droits de A');
select pg_temp.check((select count(*) from public.commissions) = 0, 'B ne voit pas les commissions');
select pg_temp.check(not public.has_access('cover_page', '00000000-0000-4000-8000-000000000301'), 'B n''a aucun accès');
reset role;

select pg_temp.as_service();
create temporary table t_pay_b as
  select * from public.create_payment('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000501',
    null, 'CDF', 'mobile_money_web', 'mock', '243840000002', 'orange', null, 'cle-b-1');
grant all on t_pay_b to anon, authenticated, service_role;
reset role;
update public.payments set expires_at = now() - interval '1 minute' where id = (select id from t_pay_b);
select pg_temp.as_service();
select pg_temp.check(public.expire_stale_payments() = 1, 'le délai dépassé passe le paiement en expiré');
select pg_temp.check((select status from public.payments where id = (select id from t_pay_b)) = 'expired', 'statut expiré');
select pg_temp.check((public.confirm_payment((select id from t_pay_b), 'REF-B-1')->>'status') = 'succeeded',
                     'confirmation tardive de l''opérateur : l''étudiant qui a payé est débloqué');
reset role;

select pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
select pg_temp.check(public.has_access('cover_page', '00000000-0000-4000-8000-000000000302'), 'B : accès page de garde');
select pg_temp.check(not public.has_access('doc_template', '00000000-0000-4000-8000-000000000401'), 'B : pas d''accès aux modèles de document');
select pg_temp.check((select count(*) from public.document_template_bodies) = 0, 'B ne lit pas le modèle de mémoire');
reset role;

-- -----------------------------------------------------------------------------
\echo '# Paiement échoué, contrôles de saisie'
-- -----------------------------------------------------------------------------
select pg_temp.as_service();
create temporary table t_pay_fail as
  select * from public.create_payment('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000504',
    null, 'USD', 'mobile_money_app', 'mock', '243840000002', 'orange', null, 'cle-b-2');
grant all on t_pay_fail to anon, authenticated, service_role;
select pg_temp.check((public.fail_payment((select id from t_pay_fail), 'failed', 'solde insuffisant')->>'status') = 'failed', 'échec enregistré');
select pg_temp.check((public.confirm_payment((select id from t_pay_fail))->>'already_processed')::boolean,
                     'un paiement échoué n''est jamais débloqué');

do $$ begin
  perform public.create_payment('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000502',
    null, 'USD', 'mobile_money_app', 'mock', '243840000002', 'orange', null, 'cle-b-3');
  raise exception 'ÉCHEC : un modèle à l''unité exige un modèle précis';
exception when invalid_parameter_value then raise notice 'ok - achat d''un modèle sans modèle précis refusé';
end $$;

do $$ begin
  perform public.create_payment('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000504',
    null, 'USD', 'mobile_money_app', 'mock', '243840000002', 'orange', 'INCONNU', 'cle-b-4');
  raise exception 'ÉCHEC : code promo invalide accepté';
exception when invalid_parameter_value then raise notice 'ok - code promo invalide refusé à la création';
end $$;

do $$ begin
  perform public.create_payment('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000504',
    null, 'USD', 'mobile_money_app', 'mock', '243810000001', 'vodacom', null, 'cle-b-2');
  raise exception 'ÉCHEC : clé d''idempotence d''un autre utilisateur réutilisée';
exception when unique_violation then raise notice 'ok - clé d''idempotence d''un autre utilisateur refusée';
end $$;

-- Achat à l'unité d'un modèle précis.
create temporary table t_pay_doc as
  select * from public.create_payment('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000502',
    '00000000-0000-4000-8000-000000000401', 'USD', 'mobile_money_app', 'mock', '243840000002', 'orange', null, 'cle-b-5');
grant all on t_pay_doc to anon, authenticated, service_role;
select public.confirm_payment((select id from t_pay_doc));
reset role;
select pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
select pg_temp.check(public.has_access('doc_template', '00000000-0000-4000-8000-000000000401'), 'B : accès au modèle acheté');
select pg_temp.check(not public.has_access('doc_template', gen_random_uuid()), 'B : pas d''accès aux autres modèles');
select pg_temp.check((select count(*) from public.document_template_bodies) = 1, 'B lit le modèle acheté');
reset role;

-- -----------------------------------------------------------------------------
\echo '# Renouvellement du Pack Finaliste'
-- -----------------------------------------------------------------------------
select pg_temp.as_service();
create temporary table t_pay_renew as
  select * from public.create_payment('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000504',
    null, 'CDF', 'mobile_money_app', 'mock', '243810000001', 'vodacom', null, 'cle-a-2');
grant all on t_pay_renew to anon, authenticated, service_role;
select public.confirm_payment((select id from t_pay_renew));
select pg_temp.check(
  (select e2.starts_at = e1.expires_at
     from public.entitlements e1, public.entitlements e2
    where e1.payment_id = (select id from t_pay) and e2.payment_id = (select id from t_pay_renew)),
  'le renouvellement prolonge à partir de la fin du pack en cours');

-- -----------------------------------------------------------------------------
\echo '# Achats Google Play / App Store'
-- -----------------------------------------------------------------------------
do $$ begin
  perform public.grant_store_purchase('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000501',
    null, 'google', 'GPA.1234', 'USD', 200);
  if (public.grant_store_purchase('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000501',
        null, 'google', 'GPA.1234', 'USD', 200)->>'already_processed')::boolean is not true then
    raise exception 'ÉCHEC : achat Play rejoué non détecté';
  end if;
  if (select count(*) from public.payments where provider = 'google') <> 1 then
    raise exception 'ÉCHEC : achat Play enregistré plusieurs fois';
  end if;
  raise notice 'ok - achat Play idempotent (jeton rejoué sans effet)';
end $$;
do $$ begin
  perform public.grant_store_purchase('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000501',
    null, 'google', 'GPA.1234', 'USD', 200);
  raise exception 'ÉCHEC : jeton Play d''un autre compte accepté';
exception when insufficient_privilege then raise notice 'ok - jeton Play d''un autre compte refusé';
end $$;
reset role;

-- -----------------------------------------------------------------------------
\echo '# Appareil unique'
-- -----------------------------------------------------------------------------
select pg_temp.as_service();
select pg_temp.check((public.claim_device('aaaaaaaa-0000-4000-8000-000000000001', 'appareil-telephone-1', 'android')
                       ->>'other_devices_revoked')::boolean, 'premier appareil enregistré');
select pg_temp.check((public.claim_device('aaaaaaaa-0000-4000-8000-000000000001', 'appareil-telephone-2', 'android')
                       ->>'previous_device_id') = 'appareil-telephone-1', 'nouvel appareil : l''ancien est signalé');
select pg_temp.check((select revoked_at is not null from public.user_devices where device_id = 'appareil-telephone-1'),
                     'l''ancien appareil est révoqué');
reset role;
select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
select pg_temp.check(public.is_active_device('appareil-telephone-2'), 'le nouvel appareil est actif');
select pg_temp.check(not public.is_active_device('appareil-telephone-1'), 'l''ancien appareil ne l''est plus');
do $$ begin
  perform public.claim_device('aaaaaaaa-0000-4000-8000-000000000001', 'appareil-pirate-9', 'android');
  raise exception 'ÉCHEC : l''app ne doit pas appeler claim_device directement';
exception when insufficient_privilege then raise notice 'ok - claim_device réservé au serveur';
end $$;
reset role;

-- -----------------------------------------------------------------------------
\echo '# Synchronisation hors ligne (la dernière modification gagne)'
-- -----------------------------------------------------------------------------
select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
select pg_temp.check((public.push_changes(
  '[{"id":"dddddddd-0000-4000-8000-000000000001","title":"Version 1","work_type":"tfc","updated_at":"2026-10-18T10:00:00Z"}]',
  '[{"id":"eeeeeeee-0000-4000-8000-000000000001","work_id":"dddddddd-0000-4000-8000-000000000001","kind":"book",
     "data":{"title":"Ouvrage"},"updated_at":"2026-10-18T10:00:00Z"}]')->>'works_applied')::int = 1, 'création hors ligne envoyée');
select pg_temp.check((public.push_changes(
  '[{"id":"dddddddd-0000-4000-8000-000000000001","title":"Ancienne version","updated_at":"2026-10-18T09:00:00Z"}]')
  ->>'works_applied')::int = 0, 'une modification plus ancienne est ignorée');
select pg_temp.check((public.push_changes(
  '[{"id":"dddddddd-0000-4000-8000-000000000001","title":"Version 2","work_type":"tfc","updated_at":"2026-10-18T11:00:00Z"}]')
  ->>'works_applied')::int = 1, 'une modification plus récente est appliquée');
select pg_temp.check((select title from public.student_works) = 'Version 2', 'le titre final est la version la plus récente');
select pg_temp.check(jsonb_array_length(public.sync_changes(null)->'bibliography_entries') = 1, 'la bibliographie revient à la synchro');
reset role;

select pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
select pg_temp.check((select count(*) from public.student_works) = 0, 'B ne voit pas le travail de A');
select pg_temp.check(jsonb_array_length(public.sync_changes(null)->'student_works') = 0, 'la synchro de B ne contient pas le travail de A');
do $$ begin
  insert into public.student_works (id, user_id, title)
  values (gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-000000000001', 'injection');
  raise exception 'ÉCHEC : B écrit dans le travail de A';
exception when insufficient_privilege then raise notice 'ok - B ne peut pas écrire pour A';
end $$;
reset role;

-- -----------------------------------------------------------------------------
\echo '# Tableau de bord d''administration'
-- -----------------------------------------------------------------------------
select pg_temp.as_user('cccccccc-0000-4000-8000-000000000003');
select pg_temp.check((public.admin_dashboard_summary()->>'users_total')::int = 3, 'l''admin voit le nombre d''inscrits');
select pg_temp.check((public.admin_dashboard_summary()->'commissions_due'->>'USD')::int = 180, 'l''admin voit les commissions dues');
select pg_temp.check((select count(*) from public.admin_sales_daily(current_date - 1, current_date + 1)) >= 1, 'ventes par jour');
select pg_temp.check((select count(*) from public.admin_revenue_by_institution(current_date - 1, current_date + 1)) >= 1, 'revenus par université');
select pg_temp.check((select amount_minor from public.admin_commissions_due() where currency = 'USD') = 180, 'commissions dues par ambassadeur');
select pg_temp.check((select count(*) from public.promo_codes) = 1, 'l''admin gère les codes promo');
select pg_temp.check((select count(*) from public.cover_template_bodies) = 3, 'l''admin lit les modèles');
select pg_temp.check(public.admin_mark_commissions_paid('00000000-0000-4000-8000-000000000601', 'USD', 'VIR-1') = 1,
                     'commissions marquées payées');
reset role;

select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
do $$ begin
  perform public.admin_dashboard_summary();
  raise exception 'ÉCHEC : un étudiant voit le tableau de bord';
exception when insufficient_privilege then raise notice 'ok - un étudiant n''accède pas au tableau de bord';
end $$;
do $$ begin
  update public.guide_chapters set title = 'piraté';
  if exists (select 1 from public.guide_chapters where title = 'piraté') then
    raise exception 'ÉCHEC : un étudiant modifie le guide';
  end if;
  raise notice 'ok - un étudiant ne modifie pas le guide';
end $$;
reset role;

\echo '# Tous les tests de la base sont passés'
rollback;
