# Guide d'Implémentation - Système Flexible de Déploiement

## 🎯 Objectif

Créer un système DevOps centralisé qui supporte **n'importe quelle stack de services** (API + Redis, API + PostgreSQL + Redis, API + MongoDB + RabbitMQ, etc.) sans dupliquer les scripts.

## ✅ Ce qui a été implémenté

### 1. Système de Templates (✅ Terminé)

**Localisation :** `/Users/jeanmermozeffi/PycharmProjects/devops-enginering/deployment/templates/`

**Templates disponibles :**

#### A. `fastapi-redis/`
- **Services :** API + Redis
- **Fichiers :**
  - `docker-compose.yml` (base)
  - `docker-compose.dev.yml` (dev overrides)
  - `docker-compose.staging.yml` (staging overrides)
  - `docker-compose.prod.yml` (prod overrides)

#### B. `fastapi-postgres-redis/`
- **Services :** API + PostgreSQL + Redis
- **Fichiers :** Mêmes que fastapi-redis
- **Variables supplémentaires :**
  - `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
  - `POSTGRES_DEV_PORT`, `POSTGRES_STAGING_PORT`, `POSTGRES_PROD_PORT`

### 2. Configuration `.devops.yml` Améliorée (✅ Terminé)

**Nouvelles sections ajoutées :**

```yaml
# Variables PostgreSQL (si utilisées)
postgres_user: postgres
postgres_password: secretpassword
postgres_db: myapp
postgres_dev_port: 5432
postgres_staging_port: 5433
postgres_prod_port: 5434

# Fichiers Docker Compose personnalisés
compose_files:
  dev: docker-compose.yml:docker-compose.dev.yml
  staging: docker-compose.yml:docker-compose.staging.yml
  prod: docker-compose.yml:docker-compose.prod.yml

# Variables personnalisées (exportées automatiquement)
# Toute variable ajoutée ici sera exportée en MAJUSCULES
my_custom_var: some_value     # → MY_CUSTOM_VAR=some_value
rabbitmq_port: 5672           # → RABBITMQ_PORT=5672
```

### 3. CLI `devops` Amélioré (✅ En cours)

**Améliorations apportées :**

1. **Support des variables personnalisées** :
   - Toute variable dans `.devops.yml` est automatiquement exportée
   - Conversion automatique en MAJUSCULES
   - Variables PostgreSQL ajoutées

2. **Fonctions helper** :
   - `get_compose_files(env)` : Récupère les fichiers compose pour un environnement
   - `has_project_compose()` : Vérifie si le projet a ses propres compose files

## 📋 Architecture Finale

```
Système DevOps Centralisé
========================

devops-enginering/
├── devops                     # CLI principal
├── install.sh                 # Installation
├── deployment/
│   ├── scripts/               # ✅ Scripts centralisés (réutilisables)
│   │   ├── deploy.sh
│   │   ├── registry.sh
│   │   └── ...
│   └── templates/             # 🆕 Templates par stack
│       ├── README.md
│       ├── fastapi-redis/
│       └── fastapi-postgres-redis/

Projet Utilisateur
==================

mon-projet/
├── .devops.yml                # Configuration (nom, ports, variables)
├── docker-compose.yml         # 🆕 Compose de base (services)
├── docker-compose.dev.yml     # 🆕 Overrides dev
├── docker-compose.staging.yml # 🆕 Overrides staging
├── docker-compose.prod.yml    # 🆕 Overrides prod
├── .env.dev                   # Variables dev
├── .env.staging               # Variables staging
├── .env.prod                  # Variables prod
└── src/
```

## 🔄 Flux de Déploiement

### Méthode 1 : Avec Template (Nouveau)

```bash
# 1. Initialiser depuis un template
cd /path/to/mon-projet
devops init --template fastapi-postgres-redis

# Crée :
# - .devops.yml (avec variables PostgreSQL)
# - docker-compose.yml
# - docker-compose.dev.yml
# - docker-compose.staging.yml
# - docker-compose.prod.yml

# 2. Personnaliser .devops.yml
nano .devops.yml
# Modifier: project_name, registry_username, postgres_user, etc.

# 3. Déployer
devops deploy dev
```

**Ce qui se passe :**
1. CLI charge `.devops.yml`
2. Exporte toutes les variables (PROJECT_NAME, IMAGE_NAME, POSTGRES_USER, etc.)
3. Détecte `docker-compose.yml` dans le projet
4. Lance : `docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d`
5. Les variables sont injectées automatiquement

### Méthode 2 : Personnalisé (Avancé)

```bash
# 1. Initialiser sans template
cd /path/to/mon-projet
devops init

# 2. Créer votre propre docker-compose.yml
cat > docker-compose.yml <<EOF
services:
  api:
    build: .
    image: \${IMAGE_NAME}:\${ENV}-latest
    container_name: \${PROJECT_NAME}-api-\${ENV}

  mongodb:
    image: mongo:6
    container_name: \${PROJECT_NAME}-mongo-\${ENV}

  rabbitmq:
    image: rabbitmq:3-management
    container_name: \${PROJECT_NAME}-rabbitmq-\${ENV}
    ports:
      - "\${RABBITMQ_PORT}:5672"
EOF

# 3. Ajouter variables dans .devops.yml
cat >> .devops.yml <<EOF

# Variables personnalisées
rabbitmq_port: 5672
mongodb_port: 27017
EOF

# 4. Déployer
devops deploy dev
```

## 🎨 Exemples d'Utilisation

### Exemple 1 : API FastAPI + Redis

```bash
cd ~/Projects/my-api
devops init --template fastapi-redis

# .devops.yml créé avec :
project_name: my-api
image_name: my-api
dev_port: 8001
redis_dev_port: 6379

# Déployer
devops deploy dev

# Résultat :
# ✅ Conteneur: my-api-api-dev (port 8001)
# ✅ Conteneur: my-api-redis-dev (port 6379)
```

### Exemple 2 : API FastAPI + PostgreSQL + Redis

```bash
cd ~/Projects/my-saas
devops init --template fastapi-postgres-redis

# .devops.yml créé avec :
project_name: my-saas
image_name: my-saas
postgres_user: myapp
postgres_password: secretpassword
postgres_db: myapp_db

# Déployer
devops deploy dev

# Résultat :
# ✅ Conteneur: my-saas-api-dev
# ✅ Conteneur: my-saas-postgres-dev
# ✅ Conteneur: my-saas-redis-dev
```

### Exemple 3 : Stack Custom (MongoDB + RabbitMQ + Redis)

```bash
cd ~/Projects/microservice
devops init

# Créer docker-compose.yml personnalisé
nano docker-compose.yml

# Ajouter variables dans .devops.yml
nano .devops.yml
# Ajouter :
# mongodb_port: 27017
# rabbitmq_port: 5672
# rabbitmq_mgmt_port: 15672

# Déployer
devops deploy dev
```

## 📝 Prochaines Étapes

### À Terminer

1. **Commande `devops init --template <name>`** (⏳ À faire)
   - Copier les fichiers du template vers le projet
   - Générer .devops.yml adapté au template

2. **Modifier `cmd_deploy()`** (⏳ À faire)
   - Détecter si le projet a docker-compose.yml
   - Utiliser les compose du projet au lieu de ceux centralisés
   - Construire la commande docker compose avec les bons fichiers

3. **Documentation** (⏳ À faire)
   - Guide de migration
   - Exemples par stack
   - Troubleshooting

### Code à Ajouter

#### Dans `devops` (fonction cmd_init)

```bash
cmd_init() {
    log_header "INITIALISATION DU PROJET"

    local template=""
    local project_name=$(basename "$CURRENT_PROJECT_DIR")

    # Parser les options
    while [ $# -gt 0 ]; do
        case "$1" in
            --template)
                template="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Si template spécifié, copier les fichiers
    if [ -n "$template" ]; then
        local template_dir="$DEVOPS_ROOT/deployment/templates/$template"

        if [ ! -d "$template_dir" ]; then
            log_error "Template '$template' introuvable"
            log_info "Templates disponibles:"
            ls -1 "$DEVOPS_ROOT/deployment/templates/" | grep -v README
            exit 1
        fi

        log_info "Copie des fichiers depuis le template: $template"

        # Copier les docker-compose
        cp "$template_dir"/docker-compose*.yml "$CURRENT_PROJECT_DIR/"

        log_success "Fichiers docker-compose copiés"
    fi

    # ... reste du code d'init ...
}
```

#### Dans `devops` (fonction cmd_deploy)

```bash
cmd_deploy() {
    load_project_config

    local env=$1
    shift

    log_header "DÉPLOIEMENT - $PROJECT_NAME ($env)"

    # Export de l'environnement
    export ENV=$env

    # Vérifier si le projet a ses propres compose files
    if has_project_compose; then
        log_info "Utilisation des docker-compose du projet"

        # Obtenir les fichiers compose pour cet environnement
        local compose_files=$(get_compose_files "$env")

        # Construire la commande docker compose
        local compose_cmd="docker compose"

        # Ajouter chaque fichier avec -f
        IFS=':' read -ra FILES <<< "$compose_files"
        for file in "${FILES[@]}"; do
            if [ -f "$CURRENT_PROJECT_DIR/$file" ]; then
                compose_cmd="$compose_cmd -f $file"
            else
                log_warn "Fichier $file introuvable, ignoré"
            fi
        done

        log_info "Commande: $compose_cmd"

        # Lancer docker compose
        cd "$CURRENT_PROJECT_DIR"
        eval "$compose_cmd up -d --build"

        log_success "Déploiement terminé !"
    else
        log_info "Pas de docker-compose.yml trouvé, utilisation des scripts centralisés"

        # Ancien comportement (fallback)
        # ... code existant ...
    fi
}
```

## 🔒 Variables Injectées Automatiquement

| Variable | Source | Exemple |
|----------|--------|---------|
| `PROJECT_NAME` | .devops.yml | `my-app` |
| `IMAGE_NAME` | .devops.yml | `my-app` |
| `ENV` | Argument CLI | `dev`, `staging`, `prod` |
| `DEV_PORT` | .devops.yml | `8001` |
| `STAGING_PORT` | .devops.yml | `8002` |
| `PROD_PORT` | .devops.yml | `8000` |
| `REDIS_DEV_PORT` | .devops.yml | `6379` |
| `POSTGRES_USER` | .devops.yml | `postgres` |
| `POSTGRES_PASSWORD` | .devops.yml | `secretpassword` |
| `POSTGRES_DB` | .devops.yml | `myapp` |
| `MY_CUSTOM_VAR` | .devops.yml | Toute variable personnalisée |

## 🎯 Avantages de Cette Architecture

1. **Flexibilité Totale**
   - Chaque projet peut avoir ses propres services
   - Pas de limitation à API + Redis

2. **Scripts Centralisés**
   - Une seule copie de `deploy.sh`, `registry.sh`, etc.
   - Mises à jour dans un seul endroit

3. **Configuration Minimale**
   - Juste `.devops.yml` (10-20 lignes)
   - Variables exportées automatiquement

4. **Templates Réutilisables**
   - Démarrage rapide avec `--template`
   - Personnalisables à volonté

5. **Rétrocompatibilité**
   - Si pas de docker-compose.yml, utilise l'ancien système
   - Migration progressive possible

## 📚 Documentation

- **README.md** : Vue d'ensemble du système
- **QUICKSTART.md** : Guide 5 minutes
- **CHEATSHEET.md** : Commandes essentielles
- **MIGRATION.md** : Guide de migration
- **deployment/templates/README.md** : Guide des templates
- **Ce fichier** : Détails d'implémentation

---

**Status :** ⏳ En cours de finalisation

**Prochaine étape :** Implémenter les modifications de cmd_init et cmd_deploy

**Date :** 12 janvier 2026
