#!/usr/bin/env bash
# ============================================================================
# PostgreSQL — Initialisation des bases de données par SaaS
# Exécuté automatiquement au PREMIER démarrage du conteneur postgres
# ============================================================================
# Pour ajouter un nouveau SaaS : décommenter le bloc correspondant,
# redémarrer le conteneur postgres (les scripts ne s'exécutent qu'une fois).
# Pour forcer la ré-exécution : supprimer le volume postgres-data (⚠️ perte de données)
# ============================================================================

set -e

# Fonction utilitaire
create_saas_db() {
  local user="$1"
  local password="$2"
  local db_prod="$3"
  local db_staging="${db_prod/_prod/_staging}"
  local db_dev="${db_prod/_prod/_dev}"

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    -- Créer l'utilisateur s'il n'existe pas
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${user}') THEN
        CREATE USER ${user} WITH PASSWORD '${password}';
      END IF;
    END
    \$\$;

    -- Bases de données prod / staging / dev
    SELECT 'CREATE DATABASE ${db_prod} OWNER ${user}'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_prod}')\gexec
    SELECT 'CREATE DATABASE ${db_staging} OWNER ${user}'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_staging}')\gexec
    SELECT 'CREATE DATABASE ${db_dev} OWNER ${user}'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_dev}')\gexec

    GRANT ALL PRIVILEGES ON DATABASE ${db_prod} TO ${user};
    GRANT ALL PRIVILEGES ON DATABASE ${db_staging} TO ${user};
    GRANT ALL PRIVILEGES ON DATABASE ${db_dev} TO ${user};
EOSQL

  echo "[OK] Bases créées : ${db_prod}, ${db_staging}, ${db_dev} → user: ${user}"
}

# ── AkiText ──────────────────────────────────────────────────────────────────
create_saas_db \
  "akitext" \
  "${AKITEXT_DB_PASSWORD}" \
  "akitext_prod"

# ── Futur SaaS 2 (décommenter quand nécessaire) ──────────────────────────────
# create_saas_db \
#   "saas2" \
#   "${SAAS2_DB_PASSWORD}" \
#   "saas2_prod"

echo "==> Initialisation PostgreSQL AKILIYA terminée"
