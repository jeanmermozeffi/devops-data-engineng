# Architecture du Système DevOps

**Date:** 13 janvier 2026
**Version:** 2.0 - Système Centralisé avec Scripts

---

## 🎯 Vue d'Ensemble

Le système DevOps est conçu pour **centraliser** tous les scripts de déploiement dans un seul endroit (`devops-enginering/`) tout en permettant le déploiement de **n'importe quel projet** via un simple fichier `.devops.yml`.

### Philosophie

```
UN seul système de scripts centralisé
    ↓
Déploie TOUS les projets
    ↓
Via configuration .devops.yml
```

---

## 📁 Structure du Système

```
devops-enginering/                    # Système central (UN seul endroit)
├── devops                            # ✅ CLI principal
├── install.sh                        # ✅ Installation globale
├── deployment/
│   ├── scripts/                      # ✅ Scripts centralisés
│   │   ├── deploy.sh                 # Déploiement principal
│   │   ├── registry.sh               # Gestion Docker Hub
│   │   ├── deploy-registry.sh        # Déploiement depuis registry
│   │   ├── create-deployment-package.sh  # Création de packages
│   │   ├── env-encrypt.py            # Chiffrement .env
│   │   ├── audit-security.sh         # Audit de sécurité
│   │   └── .registry-profiles/       # Profils registry multiples
│   └── templates/                    # ✅ Templates réutilisables
│       ├── fastapi-redis/
│       └── fastapi-postgres-redis/
└── docs/                             # Documentation

votre-projet/                         # N'importe quel projet
├── .devops.yml                       # ✅ Configuration (seul fichier nécessaire)
├── deployment/                       # ✅ Docker-compose du projet
│   ├── docker/                       # Dockerfiles
│   │   ├── Dockerfile.dev
│   │   ├── Dockerfile.staging
│   │   └── Dockerfile.prod
│   ├── docker-compose.yml            # Base
│   ├── docker-compose.dev.yml        # Dev overrides
│   ├── docker-compose.staging.yml    # Staging overrides
│   ├── docker-compose.prod.yml       # Prod overrides
│   ├── docker-compose.registry.yml   # Registry base
│   ├── docker-compose.dev-registry.yml
│   ├── docker-compose.staging-registry.yml
│   └── docker-compose.prod-registry.yml
├── .env.dev
├── .env.staging
├── .env.prod
└── src/                              # Code source
```

---

## 🔄 Flux d'Exécution

### Commande: `devops deploy dev`

```
1. Utilisateur exécute:
   $ cd /path/to/mon-projet
   $ devops deploy dev

2. CLI devops (dans ~/.local/bin/devops):
   ├── Lit .devops.yml du projet actuel
   ├── Exporte toutes les variables:
   │   - PROJECT_NAME=mon-projet
   │   - COMPOSE_PROJECT_NAME=mon-projet
   │   - IMAGE_NAME=mon-projet
   │   - DEPLOYMENT_DIR=deployment
   │   - DOCKERFILE_DIR=docker
   │   - ENV=dev
   │   - ... toutes les autres variables
   ├── Définit PROJECT_ROOT=/path/to/mon-projet
   └── Appelle le script centralisé:
       bash /path/to/devops-enginering/deployment/scripts/deploy.sh deploy dev

3. Script deploy.sh:
   ├── Reçoit les variables d'environnement du CLI
   ├── cd $PROJECT_ROOT (navigue vers le projet)
   ├── Utilise $DEPLOYMENT_DIR au lieu de "deployment" hardcodé
   ├── Lit .env depuis $PROJECT_ROOT/$DEPLOYMENT_DIR/.env.dev
   ├── Build avec docker-compose:
   │   docker compose -f $DEPLOYMENT_DIR/docker-compose.yml \
   │                   -f $DEPLOYMENT_DIR/docker-compose.dev.yml \
   │                   build
   └── Déploie:
       docker compose -f $DEPLOYMENT_DIR/docker-compose.yml \
                      -f $DEPLOYMENT_DIR/docker-compose.dev.yml \
                      up -d

4. Résultat:
   ✅ Conteneurs déployés avec les bons noms du projet
```

---

## 🔧 Scripts Centralisés

### deployment/scripts/deploy.sh

**Rôle:** Déploiement principal (build local ou depuis Git)

**Variables acceptées du CLI:**
- `PROJECT_ROOT` - Chemin vers le projet
- `COMPOSE_PROJECT_NAME` - Nom du projet Docker Compose
- `PROJECT_NAME` - Nom du projet
- `IMAGE_NAME` - Nom de l'image Docker
- `DEPLOYMENT_DIR` - Dossier de déploiement (défaut: deployment)
- `DOCKERFILE_DIR` - Dossier des Dockerfiles (défaut: docker)
- `ENV` - Environnement (dev/staging/prod)
- Toutes les autres variables de .devops.yml

**Commandes disponibles:**
```bash
deploy.sh deploy dev            # Déployer en dev
deploy.sh stop dev              # Arrêter les conteneurs
deploy.sh restart dev           # Redémarrer
deploy.sh logs dev              # Afficher les logs
deploy.sh status dev            # Statut des conteneurs
```

**Rétrocompatibilité:**
- Si appelé directement (sans CLI), utilise les valeurs par défaut
- `COMPOSE_PROJECT_NAME` par défaut: cicbi-api-backend
- `DEPLOYMENT_DIR` par défaut: deployment

### deployment/scripts/registry.sh

**Rôle:** Gestion du Docker Registry (push/pull images)

**Variables acceptées:**
- `PROJECT_ROOT` - Chemin vers le projet
- `REGISTRY_URL` - URL du registry (docker.io, gcr.io, etc.)
- `REGISTRY_USERNAME` - Nom d'utilisateur
- `IMAGE_NAME` - Nom de l'image
- `GIT_REPO` - Repository Git
- `GITHUB_TOKEN` - Token GitHub (pour repos privés)

**Commandes disponibles:**
```bash
registry.sh release dev v1.0.0      # Créer une release
registry.sh push dev                # Push vers registry
registry.sh pull dev v1.0.0         # Pull depuis registry
registry.sh profile create prod     # Créer un profil registry
registry.sh profile list            # Lister les profils
```

**Profils Registry:**
- Stockés dans `deployment/scripts/.registry-profiles/`
- Support multi-registry (Docker Hub, GCR, ECR, etc.)
- Un profil par environnement/registry

### deployment/scripts/create-deployment-package.sh

**Rôle:** Créer un package de déploiement pour serveur distant

**Variables acceptées:**
- `PROJECT_ROOT` - Chemin vers le projet
- `PROJECT_NAME` - Nom du projet
- `COMPOSE_PROJECT_NAME` - Nom Docker Compose

**Fonctionnalité:**
- Crée un archive .tar.gz avec tout le nécessaire
- Inclut docker-compose, .env chiffrés, scripts
- Prêt à déployer sur serveur distant

### deployment/scripts/env-encrypt.py

**Rôle:** Chiffrement/déchiffrement des fichiers .env

**Sécurité:**
- Algorithme: Fernet (AES-128)
- Génère une clé unique par projet
- Clé stockée dans .env.key (à ne PAS commiter)

---

## 🔑 Fichier .devops.yml

**Rôle:** Configuration par projet (seul fichier nécessaire)

**Exemple complet:**
```yaml
# Nom du projet
project_name: mon-saas-app
compose_project_name: mon-saas-app

# Registry Docker
registry_username: monuser
registry_url: docker.io
image_name: mon-saas-backend

# Git
git_repo: https://github.com/org/mon-saas.git
dev_branch: dev
staging_branch: staging
prod_branch: main

# Structure du projet
deployment_dir: deployment
dockerfile_dir: docker

# Ports
dev_port: 8001
staging_port: 8002
prod_port: 8000
redis_dev_port: 6379
redis_staging_port: 6381
redis_prod_port: 6380

# PostgreSQL (si utilisé)
postgres_user: myapp
postgres_password: secretpassword
postgres_db: myapp_db
postgres_dev_port: 5432
postgres_staging_port: 5433
postgres_prod_port: 5434

# Fichiers docker-compose (build local)
compose_files:
  dev: docker-compose.yml:docker-compose.dev.yml
  staging: docker-compose.yml:docker-compose.staging.yml
  prod: docker-compose.yml:docker-compose.prod.yml

# Fichiers docker-compose (déploiement registry)
compose_files_registry:
  dev: docker-compose.registry.yml:docker-compose.dev-registry.yml
  staging: docker-compose.registry.yml:docker-compose.staging-registry.yml
  prod: docker-compose.registry.yml:docker-compose.prod-registry.yml

# Variables personnalisées (automatiquement exportées en MAJUSCULES)
mongodb_port: 27017
rabbitmq_port: 5672
custom_api_key: xxx
```

**Toutes les variables sont automatiquement:**
1. Exportées en MAJUSCULES (mongodb_port → MONGODB_PORT)
2. Disponibles dans les scripts
3. Injectées dans docker-compose via ${VARIABLE}

---

## 🚀 Commandes CLI

### Initialisation

```bash
# Initialiser un nouveau projet
cd /path/to/mon-projet
devops init

# Initialiser avec template
devops init --template fastapi-redis
```

### Déploiement

```bash
# Déploiement local (build depuis code)
devops deploy dev
devops deploy staging
devops deploy prod

# Déploiement depuis registry (sur serveur distant)
devops deploy prod --from-registry v1.0.0
```

### Registry

```bash
# Créer une release et push vers Docker Hub
devops registry release prod v1.0.0

# Gérer les profils registry
devops registry profile create staging
devops registry profile list
devops registry profile select staging
```

### Package

```bash
# Créer un package pour déploiement distant
devops package
```

---

## 🔐 Sécurité

### Secrets Management

1. **Fichiers .env chiffrés:**
   ```bash
   # Chiffrer automatiquement
   devops deploy prod --encrypt-env

   # Ou manuellement
   python deployment/scripts/env-encrypt.py encrypt .env.prod
   ```

2. **Clé de chiffrement:**
   - Stockée dans `.env.key` (à ne PAS commiter)
   - Générée automatiquement par projet
   - Partagée manuellement avec l'équipe

3. **Variables sensibles:**
   - Définies dans `deployment/scripts/sensitive-vars.yml`
   - Jamais commitées en clair
   - Injectées via volumes Docker

### Docker Security

1. **Utilisateur non-root:**
   - Dockerfiles production utilisent `appuser` (UID 1000)
   - Jamais d'exécution en tant que root

2. **Multi-stage builds:**
   - Phase builder (avec gcc, make, etc.)
   - Phase runtime (minimale)
   - Réduction de la surface d'attaque

3. **Health checks:**
   - Tous les services ont des health checks
   - Détection automatique des problèmes

---

## 📊 Avantages de l'Architecture

### 1. Centralisation

✅ **UN seul endroit** pour tous les scripts
✅ Mises à jour centralisées (un seul `git pull`)
✅ Pas de duplication de code entre projets

### 2. Flexibilité

✅ Fonctionne avec **n'importe quelle stack**
✅ Variables personnalisées supportées
✅ Chemins configurables (`deployment_dir`, `dockerfile_dir`)

### 3. Maintenabilité

✅ Fix un bug = tous les projets en bénéficient
✅ Nouvelle fonctionnalité = disponible partout
✅ Documentation centralisée

### 4. Rétrocompatibilité

✅ Scripts fonctionnent toujours en direct
✅ Valeurs par défaut pour anciens projets
✅ Migration progressive possible

---

## 🔄 Migration d'un Projet Existant

```bash
# 1. Naviguer vers le projet
cd /path/to/projet-existant

# 2. Initialiser le système DevOps
devops init

# 3. Créer la structure deployment/
mkdir -p deployment/docker

# 4. Copier les templates
cp ~/devops-enginering/deployment/templates/fastapi-redis/* deployment/

# 5. Adapter .devops.yml
nano .devops.yml

# 6. Tester
devops deploy dev
```

---

## 🛠️ Développement et Contribution

### Ajouter une Nouvelle Fonctionnalité

1. **Modifier le script centralisé:**
   ```bash
   nano ~/devops-enginering/deployment/scripts/deploy.sh
   ```

2. **Tester sur un projet:**
   ```bash
   cd /path/to/test-projet
   devops deploy dev
   ```

3. **Commit et push:**
   ```bash
   cd ~/devops-enginering
   git add deployment/scripts/deploy.sh
   git commit -m "feat: nouvelle fonctionnalité X"
   git push
   ```

4. **Tous les autres projets en bénéficient:**
   ```bash
   cd ~/devops-enginering
   git pull  # Une seule fois, pas dans chaque projet!
   ```

---

## 📚 Documentation

- **README.md** - Vue d'ensemble et installation
- **QUICKSTART.md** - Guide démarrage rapide
- **GUIDE-FINAL.md** - Guide complet avec exemples
- **FIXES-APPLIED.md** - Historique des corrections
- **Ce fichier (ARCHITECTURE.md)** - Architecture détaillée
- **CHEATSHEET.md** - Commandes essentielles

---

**Maintenu par:** Jean Mermoze Effi
**Dernière mise à jour:** 13 janvier 2026
**Version:** 2.0 - Scripts Centralisés
