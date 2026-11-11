#!/bin/sh
# ================================================================
#  Aplica las migraciones posteriores al esquema base (01_schema.sql).
#  Se ejecuta automáticamente desde /docker-entrypoint-initdb.d/
#  cuando el volumen de Postgres está vacío. Las migraciones se
#  montan en /migrations (ver docker-compose.yml).
# ================================================================
set -e
for f in /migrations/2026_05_21_folios_mensuales.sql; do
  echo "[initdb] aplicando $f"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
done
