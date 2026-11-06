#!/usr/bin/env bash
# Corre todas las migraciones y pruebas contra un Postgres LOCAL descartable.
# Uso:  PSQL="psql -h localhost -U postgres" ./correr_pruebas.sh
set -euo pipefail
cd "$(dirname "$0")"
PSQL="${PSQL:-psql}"
DB="${DB:-erp_test}"
$PSQL -d postgres -q -c "drop database if exists $DB" -c "create database $DB"
P="$PSQL -d $DB -v ON_ERROR_STOP=1 -q"
$P -f 00_stub_supabase.sql
for f in ../migraciones/*.sql; do echo ">> aplicando $(basename "$f")"; $P -f "$f"; done
for t in [1-9]*_test_*.sql; do echo ">> prueba $t"; $P -f "$t"; done
echo ">> verificando que una migración no corre dos veces"
for f in ../migraciones/*.sql; do if $P -f "$f" >/dev/null 2>&1; then echo "ERROR: $(basename "$f") se aplicó dos veces"; exit 1; fi; done
echo "TODO OK"
