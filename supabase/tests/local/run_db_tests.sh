#!/usr/bin/env bash
# =============================================================================
# Lance les tests de la base sur un PostgreSQL local jetable, sans Docker.
#   - crée un cluster temporaire (initdb) et le détruit à la fin ;
#   - charge l'imitation Supabase, les migrations 1 à 3 et les données de démo ;
#   - exécute tests/database_test.sql.
# La migration 4 (pg_cron) n'est pas chargée : pg_cron n'existe que sur Supabase.
#
# Usage : ./supabase/tests/local/run_db_tests.sh
#         ./supabase/tests/local/run_db_tests.sh --export-seed <fichier.json>
#         ./supabase/tests/local/run_db_tests.sh --exec <commande...>
#   --export-seed régénère le contenu gratuit embarqué dans l'app
#   (montfc_app/assets/seed/content.json) à partir de seed.sql.
#   --exec lance une commande avec TEST_DATABASE_URL pointant vers la base
#   prête (utilisé par les tests Deno du flux de paiement).
# Prérequis : PostgreSQL 15 ou plus (initdb, pg_ctl, psql).
# Avec la CLI Supabase, on peut aussi faire : supabase db reset puis
#   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" -f supabase/tests/database_test.sql
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPABASE_DIR="$(cd "$HERE/../.." && pwd)"

PG_BIN="${PG_BIN:-$(dirname "$(command -v initdb 2>/dev/null || ls /usr/lib/postgresql/*/bin/initdb | tail -1)")}"
WORK="$(mktemp -d)"
PORT="${PGPORT_TEST:-54329}"

# initdb refuse de tourner en root : on utilise l'utilisateur postgres si besoin.
RUN=()
if [ "$(id -u)" = "0" ]; then
  chown -R postgres "$WORK"
  RUN=(runuser -u postgres --)
fi

cleanup() {
  "${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"${RUN[@]}" "$PG_BIN/initdb" -D "$WORK/data" -U postgres -A trust --locale=C.UTF-8 -E UTF8 >/dev/null
"${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=127.0.0.1" -l "$WORK/log" -w start >/dev/null

PSQL=("${RUN[@]}" "$PG_BIN/psql" -h "$WORK" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" -f "$HERE/supabase_stubs.sql"
for f in "$SUPABASE_DIR"/migrations/*_schema.sql "$SUPABASE_DIR"/migrations/*_functions.sql "$SUPABASE_DIR"/migrations/*_rls.sql; do
  "${PSQL[@]}" -f "$f"
done
"${PSQL[@]}" -f "$SUPABASE_DIR/seed.sql"

if [ "${1:-}" = "--exec" ]; then
  shift
  export TEST_DATABASE_URL="postgres://postgres@127.0.0.1:$PORT/postgres"
  status=0
  "$@" || status=$?
  exit $status
fi

if [ "${1:-}" = "--export-seed" ]; then
  # Réponse de sync_changes pour un visiteur anonyme : uniquement le contenu
  # public (guide, catalogue, métadonnées), jamais les corps payants.
  "${PSQL[@]}" -At -c "set role anon; select (public.sync_changes(null) - 'server_time' - 'profile' - 'entitlements' - 'student_works' - 'bibliography_entries')::text;" > "$WORK/seed.json"
  cp "$WORK/seed.json" "$2"
  echo "Contenu embarqué écrit dans $2"
  exit 0
fi

"${PSQL[@]}" -f "$SUPABASE_DIR/tests/database_test.sql" 2>&1 | sed 's/^psql:[^ ]* NOTICE:  /  /'
