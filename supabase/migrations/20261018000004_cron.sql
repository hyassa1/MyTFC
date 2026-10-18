-- =============================================================================
-- MonTFC — Migration 4 : tâches planifiées (pg_cron)
-- -----------------------------------------------------------------------------
-- Toutes les 5 minutes, les paiements restés en attente au-delà de leur délai
-- passent en « expired ». Si l'opérateur confirme quand même plus tard,
-- confirm_payment() débloque l'accès (un paiement expiré reste rattrapable).
-- =============================================================================

create extension if not exists pg_cron;

select cron.schedule(
  'montfc-expire-stale-payments',
  '*/5 * * * *',
  $$select public.expire_stale_payments();$$
);
