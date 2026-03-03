# Monitoring agent - template projet

Ce dossier contient le template standard pour **agent monitoring uniquement**.

## Portee

- A deployer sur chaque serveur projet/applicatif
- Collecte locale: host + containers + logs + exporters optionnels
- Envoi des logs vers le central (Loki)
- Le central monitoring n'est pas embarque ici

## Contenu

- `agents/docker-compose.yml`
- `agents/.env.example`
- `agents/promtail/promtail.yml`
- `agents/postgres-exporter/queries_airflow.yml`
- `compose-labels-snippet.yml`

## Demarrage rapide

```bash
cd deployment/monitoring/agents
cp .env.example .env
# adapter .env

docker compose --env-file .env up -d
```

Profils optionnels:

```bash
docker compose --profile airflow --env-file .env up -d
docker compose --profile postgres --env-file .env up -d
docker compose --profile redis --env-file .env up -d
```
