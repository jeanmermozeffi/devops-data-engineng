# AKILIYA — Stratégie Infrastructure & CI/CD Multi-SaaS
**Version :** 1.0 · **Date :** Juin 2026 · **Contexte :** Startup, budget contraint, VPS unique

---

## Table des matières

1. [Contexte & Diagnostic](#1-contexte--diagnostic)
2. [Principes directeurs](#2-principes-directeurs)
3. [Architecture Infrastructure](#3-architecture-infrastructure)
4. [Organisation des dépôts Git](#4-organisation-des-dépôts-git)
5. [Services partagés — PostgreSQL & Redis](#5-services-partagés--postgresql--redis)
6. [Templates de déploiement](#6-templates-de-déploiement)
7. [CI/CD GitLab — Pipeline complet](#7-cicd-gitlab--pipeline-complet)
8. [Sécurité](#8-sécurité)
9. [Provisioning serveur avec Ansible](#9-provisioning-serveur-avec-ansible)
10. [Monitoring & Observabilité](#10-monitoring--observabilité)
11. [Roadmap progressive](#11-roadmap-progressive)
12. [Cheat-sheet — Commandes clés](#12-cheat-sheet--commandes-clés)

---

## 1. Contexte & Diagnostic

### Ce que vous avez

| Élément | État actuel |
|---|---|
| Projets actifs | `akitext-plateforme-core` (Next.js), `akitext-plateforme` (FastAPI) |
| Ecosystem | Groupe AKILIYA — plusieurs SaaS à venir |
| Infrastructure | 1 VPS (45.67.217.48), Docker, Docker Hub |
| Outil DevOps | `devops-enginering/` centralisé — `.devops.yml` par projet |
| Git | GitLab (`gitlab.com/akiliya/`) |
| Budget | Contraint — startup |

### Ce qui manque (et coûte cher si ignoré)

```
✗ Pas de CI/CD automatisé → déploiement manuel, risque d'erreur humaine
✗ Pas de services partagés organisés → chaque SaaS repart from scratch
✗ Pas de provisioning reproductible → "ça marche sur mon VPS" syndrom
✗ Pas de templates CI → chaque nouveau projet réinvente la roue
✗ Pas de gestion des secrets centralisée → tokens dispersés
✗ Pas de réseau isolé entre SaaS → risque de fuite inter-projet
```

### Contrainte startup : faire beaucoup avec peu

La règle d'or : **chaque outil doit être justifié par de la valeur immédiate**. On n'installe pas Kubernetes pour 2 SaaS sur 1 VPS. On construit une fondation solide qui scale naturellement quand les revenus arrivent.

---

## 2. Principes directeurs

```
1. UN seul VPS bien configuré > plusieurs mal gérés
2. Services partagés (DB, cache, reverse proxy) > un stack par SaaS
3. Templates réutilisables > copier-coller modifié
4. Secrets jamais dans Git, jamais dans les images
5. Chaque SaaS = réseau Docker isolé
6. CI/CD = le seul chemin vers la production
7. Documenter ce qui est non-évident, pas ce qui l'est
```

---

## 3. Architecture Infrastructure

### Vue d'ensemble du VPS

```
VPS (45.67.217.48)
│
├── Layer 0 — Système (Ansible provisionné)
│   ├── Ubuntu 22.04 LTS + updates automatiques (unattended-upgrades)
│   ├── UFW : ports 22, 80, 443 seulement ouverts
│   ├── fail2ban : protection SSH brute-force
│   ├── Docker 29+ + Docker Compose v2
│   └── Utilisateur deploy (non-root, groupe docker)
│
├── Layer 1 — Infrastructure partagée (toujours up)
│   ├── Traefik 3 ← reverse proxy + SSL Let's Encrypt automatique
│   ├── PostgreSQL 16 ← 1 instance, N databases (une par SaaS)
│   ├── Redis 7 ← 1 instance, N databases (0-15 par SaaS)
│   └── Réseau Docker : infra-network (privé, non exposé)
│
├── Layer 2 — SaaS AkiText (prod)
│   ├── akitext-web (Next.js) → app.akitext.com
│   ├── akitext-api (FastAPI) → api.akitext.com
│   └── Réseau Docker : akitext-prod-network (isolé)
│
├── Layer 3 — SaaS AkiText (staging)
│   ├── akitext-web → staging-app.akitext.com
│   ├── akitext-api → staging-api.akitext.com
│   └── Réseau Docker : akitext-staging-network (isolé)
│
└── Layer 4 — Monitoring (partagé)
    ├── Grafana → monitor.akiliya.com
    ├── Prometheus + exporters
    └── Loki + Promtail (logs centralisés)
```

### Règle d'isolation réseau

Chaque SaaS **prod** et **staging** vit dans son propre réseau Docker.
Les services partagés (Traefik, PostgreSQL, Redis) sont dans `infra-network`.
Un service SaaS accède à la DB via ce réseau partagé — jamais exposé publiquement.

```
┌─────────────────────────────────────────────────────┐
│                    INTERNET                         │
└──────────────────────┬──────────────────────────────┘
                       │ :443 / :80
              ┌────────▼────────┐
              │    Traefik      │  (infra-network)
              └─┬──────────────┘
                │
      ┌─────────┼──────────┐
      ▼         ▼          ▼
 akitext-web  akitext-api  [futur-saas-web]
 (akitext-    (akitext-    (futur-network)
  prod-net)    prod-net)
      │         │
      └────┬────┘
           ▼
      PostgreSQL / Redis
      (infra-network)
```

---

## 4. Organisation des dépôts Git

### Structure GitLab AKILIYA

```
gitlab.com/akiliya/
│
├── infra/                          ← Groupe infrastructure
│   ├── devops-enginering           ← Votre outil centralisé (déjà fait)
│   ├── ansible-playbooks           ← Provisioning serveurs ← À CRÉER
│   └── gitlab-ci-templates         ← Templates CI réutilisables ← À CRÉER
│
├── akitext/                        ← Groupe SaaS AkiText
│   ├── akitext-plateforme-core     ← Front Next.js (déjà fait)
│   └── akitext-plateforme          ← Backend FastAPI (déjà fait)
│
├── [futur-saas]/
│   ├── [futur-saas]-frontend
│   └── [futur-saas]-backend
│
└── shared/                         ← Groupe packages partagés
    ├── ui-components               ← Design system commun (optionnel)
    └── api-client-ts               ← Client TypeScript partagé (optionnel)
```

### Convention de nommage obligatoire

```
Projet :  {groupe}-{service}-{type}
           akitext  -plateforme-core    (Next.js frontend)
           akitext  -plateforme         (FastAPI backend)
           [saas2]  -web                (Next.js)
           [saas2]  -api                (FastAPI)

Image Docker Hub :
           effijeanmermoz/{projet}:{env}-{version}
           effijeanmermoz/akiliya-text-platform-core:prod-1.2.3
           effijeanmermoz/akitext-api:prod-1.2.3

Réseau Docker :
           {projet}-{env}-network
           akitext-prod-network
           akitext-staging-network

Container :
           {projet}-{service}-{env}
           akiliya-text-platform-core-web-prod
           akitext-plateforme-api-prod
```

---

## 5. Services partagés — PostgreSQL & Redis

### Stratégie : 1 instance, N bases/databases

**Pourquoi pas une instance par SaaS ?**
Sur un seul VPS avec budget contraint, chaque instance PostgreSQL consomme ~50-100 Mo RAM au minimum. Avec 3 SaaS × 3 envs = 9 instances = ~900 Mo juste pour les DB. Intenable.

**Solution : 1 instance bien configurée + isolation par base de données**

```
PostgreSQL 16 (1 instance)
├── akitext_prod          ← SaaS AkiText production
├── akitext_staging       ← SaaS AkiText staging
├── akitext_dev           ← SaaS AkiText dev
├── [saas2]_prod          ← Futur SaaS production
└── [saas2]_staging       ← Futur SaaS staging

Redis 7 (1 instance)
├── DB 0  → akitext prod
├── DB 1  → akitext staging
├── DB 2  → akitext dev
├── DB 3  → [saas2] prod
└── ...   (16 databases disponibles)
```

### `docker-compose.shared.yml` — Services partagés

```yaml
# /home/deploy/infra/docker-compose.shared.yml
# Lancé UNE SEULE FOIS sur le VPS, toujours actif

name: akiliya-infra

services:

  traefik:
    image: traefik:v3
    container_name: akiliya-traefik
    restart: always
    ports:
      - "80:80"
      - "443:443"
    command:
      - "--api.dashboard=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedByDefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.email=devops@akiliya.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik-letsencrypt:/letsencrypt
    networks:
      - infra-network
    labels:
      - "cic.service=traefik"

  postgres:
    image: postgres:16-alpine
    container_name: akiliya-postgres
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_SUPERUSER}
      POSTGRES_PASSWORD: ${POSTGRES_SUPERPASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./scripts/postgres-init:/docker-entrypoint-initdb.d:ro
    networks:
      - infra-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_SUPERUSER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "cic.service=postgres"

  redis:
    image: redis:7-alpine
    container_name: akiliya-redis
    restart: always
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - redis-data:/data
    networks:
      - infra-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "cic.service=redis"

networks:
  infra-network:
    name: akiliya-infra-network
    driver: bridge

volumes:
  postgres-data:
    name: akiliya-postgres-data
  redis-data:
    name: akiliya-redis-data
  traefik-letsencrypt:
    name: akiliya-traefik-letsencrypt
```

### Script d'initialisation PostgreSQL par SaaS

```bash
# /home/deploy/infra/scripts/postgres-init/01-create-databases.sh
# Exécuté automatiquement au premier démarrage PostgreSQL

#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    -- AkiText
    CREATE USER akitext WITH PASSWORD '${AKITEXT_DB_PASSWORD}';
    CREATE DATABASE akitext_prod OWNER akitext;
    CREATE DATABASE akitext_staging OWNER akitext;
    CREATE DATABASE akitext_dev OWNER akitext;
    GRANT ALL PRIVILEGES ON DATABASE akitext_prod TO akitext;
    GRANT ALL PRIVILEGES ON DATABASE akitext_staging TO akitext;
    GRANT ALL PRIVILEGES ON DATABASE akitext_dev TO akitext;

    -- Futur SaaS 2 (décommenter quand nécessaire)
    -- CREATE USER saas2 WITH PASSWORD '${SAAS2_DB_PASSWORD}';
    -- CREATE DATABASE saas2_prod OWNER saas2;
EOSQL
```

### Connexion SaaS → Services partagés

Les conteneurs SaaS rejoignent `akiliya-infra-network` en **réseau externe** :

```yaml
# Dans docker-compose.registry.yml de chaque SaaS
networks:
  app-network:
    name: akitext-prod-network
    driver: bridge
  infra-network:
    name: akiliya-infra-network
    external: true   # ← réseau Traefik/DB partagé
```

L'API backend utilise alors :
```
DATABASE_URL=postgresql://akitext:password@akiliya-postgres/akitext_prod
REDIS_URL=redis://:password@akiliya-redis/0
```

---

## 6. Templates de déploiement

### Structure `devops-enginering/templates/`

```
devops-enginering/deployment/templates/
├── nextjs/                     ← Template frontend Next.js
│   ├── Dockerfile.prod.tpl
│   ├── Dockerfile.prod.git.tpl
│   ├── docker-compose.registry.yml.tpl
│   ├── docker-compose.prod-registry.yml.tpl
│   └── .devops.yml.tpl
│
├── fastapi/                    ← Template backend FastAPI (déjà partiellement fait)
│   ├── Dockerfile.prod.tpl
│   ├── Dockerfile.prod.git.tpl
│   ├── docker-compose.registry.yml.tpl
│   └── .devops.yml.tpl
│
└── gitlab-ci/                  ← Templates CI GitLab
    ├── nextjs-pipeline.yml     ← CI complète pour Next.js
    ├── fastapi-pipeline.yml    ← CI complète pour FastAPI
    └── shared-jobs.yml         ← Jobs réutilisables (lint, security, notify)
```

### Commande de création d'un nouveau projet

```bash
# Exemple : créer un nouveau SaaS Next.js
devops init --template nextjs --name mon-nouveau-saas

# Ce que ça fait :
# 1. Copie deployment/ depuis templates/nextjs/
# 2. Génère .devops.yml pré-rempli
# 3. Génère .gitlab-ci.yml avec include vers template CI central
# 4. Génère .env.example
# 5. Affiche les étapes manuelles restantes
```

---

## 7. CI/CD GitLab — Pipeline complet

### Architecture CI recommandée

```
Push → GitLab CI → [lint → test → build → security → push → deploy]
                                                              ↓
                                                    VPS via SSH + devops
```

### `.gitlab-ci.yml` — Template pour un projet Next.js

```yaml
# akitext-plateforme-core/.gitlab-ci.yml

include:
  # Template central — maintenu dans gitlab-ci-templates
  - project: 'akiliya/infra/gitlab-ci-templates'
    ref: main
    file: '/nextjs-pipeline.yml'

# Variables spécifiques à ce projet
variables:
  PROJECT_IMAGE: "akiliya-text-platform-core"
  PROD_DOMAIN: "app.akitext.com"
  STAGING_DOMAIN: "staging-app.akitext.com"
  NODE_VERSION: "22"

# Surcharges optionnelles
stages:
  - lint
  - test
  - build
  - security
  - push
  - deploy

# Déclencheurs par branche
workflow:
  rules:
    - if: $CI_COMMIT_BRANCH == "dev"
      variables:
        DEPLOY_ENV: "dev"
    - if: $CI_COMMIT_BRANCH == "staging"
      variables:
        DEPLOY_ENV: "staging"
    - if: $CI_COMMIT_BRANCH == "main"
      variables:
        DEPLOY_ENV: "prod"
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      variables:
        DEPLOY_ENV: "none"   # Pas de deploy sur les MR, juste lint+test+build
```

### `gitlab-ci-templates/nextjs-pipeline.yml` — Le pipeline complet

```yaml
# gitlab.com/akiliya/infra/gitlab-ci-templates → nextjs-pipeline.yml
# Template CI complet pour projets Next.js AKILIYA

stages:
  - lint
  - test
  - build
  - security
  - push
  - deploy
  - notify

# ─────────────────────────────────────────────────────────────────────────────
# Variables globales (surchargeables dans le projet)
# ─────────────────────────────────────────────────────────────────────────────
variables:
  DOCKER_BUILDKIT: "1"
  REGISTRY: "docker.io"
  REGISTRY_USER: "effijeanmermoz"
  NODE_VERSION: "22"
  CACHE_KEY: "$CI_COMMIT_REF_SLUG-$CI_PROJECT_NAME"

# ─────────────────────────────────────────────────────────────────────────────
# STAGE : lint
# ─────────────────────────────────────────────────────────────────────────────
lint:eslint:
  stage: lint
  image: node:${NODE_VERSION}-alpine
  cache:
    key: $CACHE_KEY
    paths: [node_modules/]
  script:
    - npm ci --prefer-offline
    - npm run lint
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH

lint:types:
  stage: lint
  image: node:${NODE_VERSION}-alpine
  cache:
    key: $CACHE_KEY
    paths: [node_modules/]
  script:
    - npm ci --prefer-offline
    - npx tsc --noEmit
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH

# ─────────────────────────────────────────────────────────────────────────────
# STAGE : build (valide que le build Next.js passe)
# ─────────────────────────────────────────────────────────────────────────────
build:validate:
  stage: build
  image: node:${NODE_VERSION}-alpine
  cache:
    key: $CACHE_KEY
    paths: [node_modules/]
  script:
    - npm ci --prefer-offline
    - npm run build
  artifacts:
    paths: [.next/]
    expire_in: 1 hour
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH

# ─────────────────────────────────────────────────────────────────────────────
# STAGE : security
# ─────────────────────────────────────────────────────────────────────────────
security:deps:
  stage: security
  image: node:${NODE_VERSION}-alpine
  script:
    - npm audit --audit-level=high
  allow_failure: true   # Warn, ne bloque pas (startup pragmatique)
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_COMMIT_BRANCH == "staging"

security:secrets-scan:
  stage: security
  image: trufflesecurity/trufflehog:latest
  script:
    - trufflehog git file://. --since-commit HEAD~1 --fail
  allow_failure: true
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH

# ─────────────────────────────────────────────────────────────────────────────
# STAGE : push (build image Docker + push Docker Hub)
# ─────────────────────────────────────────────────────────────────────────────
push:image:
  stage: push
  image: docker:24
  services:
    - docker:24-dind
  variables:
    IMAGE_TAG: "${DEPLOY_ENV}-${CI_COMMIT_SHORT_SHA}"
    IMAGE_LATEST: "${DEPLOY_ENV}-latest"
    IMAGE_FULL: "${REGISTRY}/${REGISTRY_USER}/${PROJECT_IMAGE}"
  before_script:
    - echo "$DOCKER_TOKEN" | docker login $REGISTRY -u $REGISTRY_USER --password-stdin
  script:
    - |
      docker buildx create --use
      docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --build-arg GIT_BRANCH=$CI_COMMIT_BRANCH \
        --build-arg GIT_REPO=$CI_PROJECT_URL \
        -f deployment/docker/Dockerfile.${DEPLOY_ENV}.git \
        -t ${IMAGE_FULL}:${IMAGE_TAG} \
        -t ${IMAGE_FULL}:${IMAGE_LATEST} \
        --push \
        deployment/docker
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      variables:
        DEPLOY_ENV: "prod"
    - if: $CI_COMMIT_BRANCH == "staging"
      variables:
        DEPLOY_ENV: "staging"
    - if: $CI_COMMIT_BRANCH == "dev"
      variables:
        DEPLOY_ENV: "dev"

# ─────────────────────────────────────────────────────────────────────────────
# STAGE : deploy (SSH sur VPS + devops deploy-registry)
# ─────────────────────────────────────────────────────────────────────────────
deploy:vps:
  stage: deploy
  image: alpine:3.19
  before_script:
    - apk add --no-cache openssh-client bash
    - eval $(ssh-agent -s)
    - echo "$VPS_SSH_KEY" | tr -d '\r' | ssh-add -
    - mkdir -p ~/.ssh && chmod 700 ~/.ssh
    - ssh-keyscan -H $VPS_HOST >> ~/.ssh/known_hosts
  script:
    - |
      ssh -o StrictHostKeyChecking=no ${VPS_USER}@${VPS_HOST} bash -s << 'ENDSSH'
        set -e
        cd ${SERVER_DEPLOY_PATH}/${CI_PROJECT_NAME}

        # Pull la nouvelle image
        docker pull ${REGISTRY}/${REGISTRY_USER}/${PROJECT_IMAGE}:${DEPLOY_ENV}-latest

        # Relancer via devops (ou docker compose direct)
        ENV=${DEPLOY_ENV} docker compose \
          -f deployment/docker-compose.registry.yml \
          -f deployment/docker-compose.${DEPLOY_ENV}-registry.yml \
          up -d --no-build

        # Vérifier que le conteneur est healthy
        sleep 10
        docker inspect --format='{{.State.Health.Status}}' \
          ${CI_PROJECT_NAME}-web-${DEPLOY_ENV} | grep -q "healthy" \
          || (echo "DEPLOY FAILED: unhealthy container" && exit 1)
      ENDSSH
  environment:
    name: $DEPLOY_ENV
    url: https://${PROD_DOMAIN}
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      variables:
        DEPLOY_ENV: "prod"
    - if: $CI_COMMIT_BRANCH == "staging"
      variables:
        DEPLOY_ENV: "staging"
    - if: $CI_COMMIT_BRANCH == "dev"
      variables:
        DEPLOY_ENV: "dev"

# ─────────────────────────────────────────────────────────────────────────────
# STAGE : notify (Slack ou autre)
# ─────────────────────────────────────────────────────────────────────────────
notify:success:
  stage: notify
  image: curlimages/curl:latest
  script:
    - |
      curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-type: application/json' \
        --data "{
          \"text\": \"✅ *${CI_PROJECT_NAME}* déployé en *${DEPLOY_ENV}* par ${CI_COMMIT_AUTHOR}\n_${CI_COMMIT_MESSAGE}_\"
        }"
  when: on_success
  allow_failure: true
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_COMMIT_BRANCH == "staging"

notify:failure:
  stage: notify
  image: curlimages/curl:latest
  script:
    - |
      curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-type: application/json' \
        --data "{
          \"text\": \"❌ *${CI_PROJECT_NAME}* ÉCHEC pipeline *${DEPLOY_ENV}*\nCommit: ${CI_COMMIT_SHORT_SHA} par ${CI_COMMIT_AUTHOR}\"
        }"
  when: on_failure
  allow_failure: true
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_COMMIT_BRANCH == "staging"
```

### Variables CI à configurer dans GitLab (Settings → CI/CD → Variables)

```
# Niveau Groupe AKILIYA (hérités par tous les projets)
DOCKER_TOKEN          → Token Docker Hub (protected, masked)
VPS_SSH_KEY           → Clé privée SSH vers le VPS (protected, masked)
VPS_HOST              → 45.67.217.48 (protected)
VPS_USER              → akiliya (protected)
SLACK_WEBHOOK_URL     → Webhook Slack/Teams (masked)

# Niveau projet (spécifiques)
SERVER_DEPLOY_PATH    → /home/deploy/apps
PROJECT_IMAGE         → akiliya-text-platform-core
PROD_DOMAIN           → app.akitext.com
STAGING_DOMAIN        → staging-app.akitext.com
```

### Flux complet sur un `git push main`

```
dev tape : git push origin main
              ↓
    GitLab reçoit le push
              ↓
    Pipeline démarre automatiquement
              ↓
    ┌─────────┬─────────┬──────────┐
    │  lint   │ lint    │          │  ← Parallèle
    │ eslint  │ types   │          │
    └────┬────┴────┬────┘          │
         │         │               │
         └────┬────┘               │
              ▼                    │
    ┌─────────────────┐            │
    │  build:validate  │           │
    └────────┬────────┘           │
             ▼                    │
    ┌─────────────────┐           │
    │ security:deps   │           │
    │ security:secrets│           │
    └────────┬────────┘           │
             ▼                    │
    ┌─────────────────────────────┤
    │  push:image                 │
    │  docker buildx → Docker Hub │
    └────────────┬────────────────┘
                 ▼
    ┌─────────────────────────────┐
    │  deploy:vps                 │
    │  SSH → docker pull → up -d  │
    │  healthcheck verify         │
    └────────────┬────────────────┘
                 ▼
    ┌─────────────────────────────┐
    │  notify:success (Slack)     │
    └─────────────────────────────┘

Durée estimée : 4-8 min (build Next.js = ~2-3 min)
```

---

## 8. Sécurité

### Niveaux de sécurité par priorité (startup)

#### Niveau 1 — Obligatoire dès maintenant

```bash
# 1. Firewall VPS
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP (Traefik redirect)
ufw allow 443/tcp  # HTTPS
ufw enable

# 2. fail2ban SSH
apt install fail2ban
# Config : 5 échecs → ban 1h

# 3. Mises à jour auto
apt install unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades

# 4. Utilisateur non-root pour deploy
useradd -m -s /bin/bash deploy
usermod -aG docker deploy
# SSH uniquement par clé, pas de password

# 5. Secrets : jamais dans Git
# → Variables GitLab CI (protected + masked)
# → .env.* dans .gitignore
# → Flux devops encrypt pour les .env serveur
```

#### Niveau 2 — Dans le mois

```
- Chiffrement .env avec devops encrypt (déjà dans votre outil)
- Images Docker : utilisateur non-root (déjà dans vos Dockerfiles ✓)
- Scan de secrets dans la CI (trufflehog) ← déjà dans le pipeline
- npm audit dans la CI ← déjà dans le pipeline
- Docker socket non exposé aux conteneurs app (seulement Traefik)
- Rotation des tokens Docker Hub tous les 90 jours
```

#### Niveau 3 — Quand vous avez des clients payants

```
- Sauvegardes PostgreSQL chiffrées (pg_dump → S3/Backblaze B2)
- Audit logs (qui déploie quoi, quand)
- Dependency scanning GitLab (inclus dans la licence)
- Container scanning (Trivy dans la CI)
- WAF basique (Traefik middleware rate-limit)
```

### Secrets — Architecture recommandée

```
MAINTENANT (pragmatique) :
  GitLab CI Variables (protected) → injectées dans la CI
  devops encrypt → .env.*.encrypted sur le VPS
  SSH key → accès VPS depuis CI

PLUS TARD (si multi-dev, compliance) :
  HashiCorp Vault (self-hosted, gratuit)
  → Injection dynamique des secrets dans les conteneurs
  → Rotation automatique des credentials DB
```

### `.env.prod` sur le VPS — Ce que le conteneur voit

```bash
# /home/deploy/apps/akitext-plateforme-core/.env.prod
# Jamais dans Git. Chiffré avec devops encrypt.

# Variables runtime serveur uniquement
# Les NEXT_PUBLIC_* sont baked dans l'image — ne pas les dupliquer ici
JWT_SECRET=un-secret-de-32-chars-minimum-generé-aléatoirement
DATABASE_URL=postgresql://akitext:password@akiliya-postgres/akitext_prod
REDIS_URL=redis://:password@akiliya-redis/0
```

---

## 9. Provisioning serveur avec Ansible

### Structure `ansible-playbooks/`

```
ansible-playbooks/
├── inventory/
│   ├── hosts.yml              ← Inventaire des serveurs
│   └── group_vars/
│       └── all.yml            ← Variables communes
│
├── playbooks/
│   ├── 01-base-server.yml     ← Sécurité, Docker, utilisateurs
│   ├── 02-infra-shared.yml    ← Traefik + PostgreSQL + Redis
│   ├── 03-deploy-saas.yml     ← Déploiement d'un SaaS
│   └── 04-monitoring.yml      ← Grafana + Prometheus + Loki
│
└── roles/
    ├── common/                ← UFW, fail2ban, updates auto
    ├── docker/                ← Docker CE + Compose v2
    ├── traefik/               ← Traefik + SSL
    ├── postgres/              ← PostgreSQL partagé
    └── redis/                 ← Redis partagé
```

### `inventory/hosts.yml`

```yaml
all:
  children:
    production:
      hosts:
        vps-psm-sih:
          ansible_host: 45.67.217.48
          ansible_user: akiliya
          ansible_ssh_private_key_file: ~/.ssh/id_rsa_psm_sih
          ansible_python_interpreter: /usr/bin/python3
```

### `playbooks/01-base-server.yml` (aperçu)

```yaml
---
- name: Configuration de base du serveur
  hosts: production
  become: true

  roles:
    - common     # UFW, fail2ban, mises à jour auto, chrony NTP
    - docker     # Docker CE 29+, Compose v2, utilisateur deploy

  tasks:
    - name: Créer la structure de déploiement
      file:
        path: "{{ item }}"
        state: directory
        owner: deploy
        group: docker
        mode: '0750'
      loop:
        - /home/deploy/apps
        - /home/deploy/infra
        - /home/deploy/backups

    - name: Copier les scripts utilitaires
      copy:
        src: ../scripts/
        dest: /home/deploy/scripts/
        owner: deploy
        mode: '0755'
```

### `playbooks/02-infra-shared.yml` (aperçu)

```yaml
---
- name: Déploiement infrastructure partagée
  hosts: production
  become: false
  vars:
    infra_dir: /home/deploy/infra

  tasks:
    - name: Copier docker-compose.shared.yml
      copy:
        src: ../shared/docker-compose.shared.yml
        dest: "{{ infra_dir }}/docker-compose.shared.yml"

    - name: Copier les scripts init PostgreSQL
      copy:
        src: ../shared/scripts/
        dest: "{{ infra_dir }}/scripts/"

    - name: Démarrer l'infrastructure partagée
      community.docker.docker_compose_v2:
        project_src: "{{ infra_dir }}"
        files: [docker-compose.shared.yml]
        state: present
        env_files: ["{{ infra_dir }}/.env.infra"]
```

### Commandes Ansible

```bash
# Provisionner un nouveau VPS de A à Z
ansible-playbook playbooks/01-base-server.yml -i inventory/hosts.yml

# Déployer les services partagés
ansible-playbook playbooks/02-infra-shared.yml -i inventory/hosts.yml

# Déployer un SaaS spécifique
ansible-playbook playbooks/03-deploy-saas.yml \
  -i inventory/hosts.yml \
  -e "saas_name=akitext env=prod"

# Vérifier l'état sans appliquer (dry-run)
ansible-playbook playbooks/01-base-server.yml \
  -i inventory/hosts.yml --check --diff
```

---

## 10. Monitoring & Observabilité

### Stack (déjà partiellement en place dans votre devops)

```
Grafana          → Dashboards (monitor.akiliya.com)
Prometheus       → Métriques conteneurs + serveur
Loki + Promtail  → Logs centralisés de tous les SaaS
cAdvisor         → Métriques Docker par conteneur
node-exporter    → Métriques système VPS
```

### Ce qu'il faut surveiller par SaaS

```
Métriques système :
  - CPU / RAM / Disk par conteneur
  - Nombre de requêtes HTTP (via Traefik)
  - Latence P50/P95/P99

Alertes critiques (configurer dans Grafana) :
  - RAM > 80% → alerte Slack
  - Disque > 70% → alerte Slack
  - Conteneur down → alerte immédiate
  - Certificat SSL expiration < 30j → alerte

Logs :
  - Erreurs 5xx agrégées par SaaS
  - Temps de réponse lents (> 2s)
  - Tentatives d'auth échouées
```

### Dashboard Grafana — 1 dashboard par SaaS

Chaque SaaS a son dashboard avec labels `cic.project=akitext`, `cic.env=prod` — déjà en place dans vos `docker-compose` grâce aux labels `cic.*`.

---

## 11. Roadmap progressive

### Phase 1 — Maintenant (0-2 mois) — Fondation

```
✅ Déjà fait :
   - Dockerfiles Next.js + FastAPI multi-stage
   - docker-compose registry (dev/staging/prod)
   - .devops.yml par projet
   - Route /health

🔲 À faire immédiatement :
   - [ ] Ansible : 01-base-server.yml (sécurité VPS)
   - [ ] Ansible : 02-infra-shared.yml (Traefik + PG + Redis partagés)
   - [ ] GitLab CI : .gitlab-ci.yml sur akitext-plateforme-core
   - [ ] GitLab CI : .gitlab-ci.yml sur akitext-plateforme (backend)
   - [ ] Variables CI dans GitLab (groupe AKILIYA)
   - [ ] Créer le repo gitlab-ci-templates
   - [ ] .env.prod sur le VPS (chiffré)
   - [ ] Premier déploiement automatisé validé (staging d'abord)
```

### Phase 2 — 2-4 mois — Industrialisation

```
🔲 Quand Phase 1 est stable :
   - [ ] gitlab-ci-templates/ avec nextjs-pipeline.yml + fastapi-pipeline.yml
   - [ ] Templates devops pour créer un nouveau SaaS en < 30 min
   - [ ] Backups PostgreSQL automatiques (pg_dump → Backblaze B2, < 5€/mois)
   - [ ] Ansible : 04-monitoring.yml (Grafana/Prometheus centralisé)
   - [ ] Alertes Grafana → Slack
   - [ ] Procédure rollback documentée et testée
```

### Phase 3 — 4-12 mois — Scale

```
🔲 Quand vous avez des clients payants :
   - [ ] 2ème VPS : séparation prod/staging
   - [ ] Sauvegardes off-site testées (restauration mensuelle)
   - [ ] Trivy scan dans la CI (vulnérabilités images)
   - [ ] HashiCorp Vault pour les secrets (si multi-dev)
   - [ ] Staging automatique sur chaque MR (review apps GitLab)
```

### Phase 4 — 12+ mois — Maturité (si traction)

```
🔲 Si les revenus le justifient :
   - [ ] Kubernetes (K3s) si > 5 SaaS ou besoins HA
   - [ ] GitLab self-hosted (économie vs gitlab.com)
   - [ ] CDN (Cloudflare) devant Traefik
   - [ ] Base de données managed (Supabase, Neon) pour la DB critique
```

---

## 12. Cheat-sheet — Commandes clés

```bash
# ══════════════════════════════════════════════════════════════════
# DÉPLOIEMENT (depuis votre machine locale)
# ══════════════════════════════════════════════════════════════════

# Build + push image vers Docker Hub
devops registry build prod
devops registry push prod

# Déployer sur le VPS
devops deploy-registry prod

# Voir les logs du conteneur front
ssh akiliya@45.67.217.48 "docker logs -f akiliya-text-platform-core-web-prod"

# ══════════════════════════════════════════════════════════════════
# VPS — MAINTENANCE
# ══════════════════════════════════════════════════════════════════

# État de tous les conteneurs
ssh akiliya@45.67.217.48 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Espace disque (critique à surveiller)
ssh akiliya@45.67.217.48 "df -h && docker system df"

# Nettoyer les images inutilisées
ssh akiliya@45.67.217.48 "docker image prune -f"

# Redémarrer un service sans downtime
ssh akiliya@45.67.217.48 "docker compose -f ... up -d --no-deps web"

# ══════════════════════════════════════════════════════════════════
# ROLLBACK D'URGENCE
# ══════════════════════════════════════════════════════════════════

# Revenir à l'image précédente (tag avec SHA commit)
ssh akiliya@45.67.217.48 bash -s << 'EOF'
  docker pull docker.io/effijeanmermoz/akiliya-text-platform-core:prod-{SHA-PRECEDENT}
  docker tag docker.io/effijeanmermoz/akiliya-text-platform-core:prod-{SHA-PRECEDENT} \
             docker.io/effijeanmermoz/akiliya-text-platform-core:prod-latest
  ENV=prod docker compose \
    -f /home/deploy/apps/akitext-plateforme-core/deployment/docker-compose.registry.yml \
    -f /home/deploy/apps/akitext-plateforme-core/deployment/docker-compose.prod-registry.yml \
    up -d --no-build
EOF

# ══════════════════════════════════════════════════════════════════
# ANSIBLE
# ══════════════════════════════════════════════════════════════════

# Provisionner le VPS
ansible-playbook playbooks/01-base-server.yml -i inventory/hosts.yml -K

# Déployer infrastructure partagée
ansible-playbook playbooks/02-infra-shared.yml -i inventory/hosts.yml

# Vérifier la configuration (dry-run)
ansible-playbook playbooks/01-base-server.yml -i inventory/hosts.yml --check
```

---

## Résumé — Décisions clés pour une startup

| Décision | Choix | Pourquoi |
|---|---|---|
| Orchestration | Docker Compose | K8s = trop complexe pour 1-2 VPS |
| Reverse proxy | Traefik | SSL auto, intégration Docker native |
| DB | 1 PostgreSQL partagé, N databases | Budget RAM, isolation suffisante |
| Cache | 1 Redis, N databases | Idem |
| Registry | Docker Hub | Déjà en place, gratuit jusqu'à 1 image privée |
| CI/CD | GitLab CI intégré | Gratuit, dans votre workflow Git |
| Secrets CI | GitLab Variables | Simple, sécurisé, pas d'infra supplémentaire |
| Secrets runtime | devops encrypt | Déjà dans votre outil |
| Provisioning | Ansible | Simple, sans agent, reproductible |
| Monitoring | Grafana/Prometheus | Déjà partiellement en place |
| Backups | pg_dump + Backblaze B2 | < 5€/mois, suffisant pour démarrer |

**Priorité absolue** : automatiser le déploiement (CI/CD) avant d'ajouter de nouveaux SaaS. Chaque déploiement manuel est un risque et une perte de temps.

---

*Document vivant — à mettre à jour à chaque évolution de l'infrastructure.*
*Maintenu dans `devops-enginering/deployment/AKILIYA-INFRA-STRATEGY.md`*
