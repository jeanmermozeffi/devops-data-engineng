# Templates Docker Compose

Ce dossier contient des templates de docker-compose pour différentes stacks d'applications.

## 📦 Templates Disponibles

### 1. `fastapi-redis/`
Stack simple avec FastAPI et Redis.

**Services :**
- API FastAPI (Uvicorn)
- Redis (cache/queue)

**Utilisé pour :**
- APIs simples avec cache
- Microservices légers
- Applications sans base de données relationnelle

### 2. `fastapi-postgres-redis/`
Stack complète avec FastAPI, PostgreSQL et Redis.

**Services :**
- API FastAPI (Uvicorn)
- PostgreSQL 15 (base de données)
- Redis (cache/queue/sessions)

**Utilisé pour :**
- APIs complètes avec base de données
- Applications web
- SaaS

### 3. `minimal/` (à venir)
Stack minimale avec uniquement l'API.

**Services :**
- API FastAPI uniquement

**Utilisé pour :**
- Microservices très légers
- Fonctions serverless
- APIs stateless

## 🚀 Utilisation

### Initialiser un projet avec un template

```bash
cd /path/to/your-project
devops init --template fastapi-postgres-redis
```

Cela copiera tous les fichiers docker-compose du template dans votre projet.

### Structure créée

```
your-project/
├── .devops.yml                    # Configuration DevOps
├── docker-compose.yml             # Configuration de base
├── docker-compose.dev.yml         # Overrides développement
├── docker-compose.staging.yml     # Overrides staging
├── docker-compose.prod.yml        # Overrides production
├── .env.dev                       # Variables dev
├── .env.staging                   # Variables staging
├── .env.prod                      # Variables prod
└── Dockerfile                     # À créer selon votre app
```

### Déployer

```bash
# Développement
devops deploy dev

# Staging
devops deploy staging

# Production
devops deploy prod
```

## ⚙️ Variables Disponibles

Toutes les variables sont définies dans `.devops.yml` et injectées automatiquement :

### Variables Globales
- `PROJECT_NAME` : Nom du projet (préfixe des conteneurs)
- `IMAGE_NAME` : Nom de l'image Docker
- `ENV` : Environnement (dev/staging/prod)

### Variables Ports
- `DEV_PORT` : Port API dev (défaut: 8001)
- `STAGING_PORT` : Port API staging (défaut: 8002)
- `PROD_PORT` : Port API prod (défaut: 8000)
- `REDIS_DEV_PORT` : Port Redis dev (défaut: 6379)
- `POSTGRES_DEV_PORT` : Port PostgreSQL dev (défaut: 5432)

### Variables Base de Données
- `POSTGRES_USER` : Utilisateur PostgreSQL
- `POSTGRES_PASSWORD` : Mot de passe PostgreSQL
- `POSTGRES_DB` : Nom de la base de données

## 🛠️ Personnalisation

### Ajouter un service

Éditez `docker-compose.yml` :

```yaml
services:
  # ... services existants

  rabbitmq:
    image: rabbitmq:3-management
    container_name: ${PROJECT_NAME}-rabbitmq-${ENV}
    ports:
      - "${RABBITMQ_PORT:-5672}:5672"
      - "${RABBITMQ_MGMT_PORT:-15672}:15672"
    networks:
      - app-network
    labels:
      - "project=${PROJECT_NAME}"
      - "environment=${ENV}"
```

### Modifier les ressources

Éditez `docker-compose.prod.yml` :

```yaml
services:
  api:
    deploy:
      resources:
        limits:
          cpus: '4.0'      # 4 CPUs
          memory: 4G       # 4 GB RAM
        reservations:
          cpus: '2.0'
          memory: 2G
```

## 📖 Structure des Templates

Chaque template contient :

1. **docker-compose.yml** : Configuration de base
   - Définition des services
   - Réseaux
   - Volumes
   - Variables

2. **docker-compose.dev.yml** : Overrides développement
   - Ports exposés pour debug
   - Hot reload activé
   - Logs DEBUG
   - Pas de limites de ressources

3. **docker-compose.staging.yml** : Overrides staging
   - Ports exposés
   - 4 workers
   - Limites de ressources modérées
   - Traefik/SSL optionnel

4. **docker-compose.prod.yml** : Overrides production
   - Ports internes uniquement (sécurité)
   - 4 workers
   - Limites de ressources strictes
   - Traefik/SSL activé
   - Optimisations

## 🔒 Sécurité

### Secrets Chiffrés

Tous les templates supportent les secrets chiffrés :

```yaml
volumes:
  - ./.env.key:/app/.env.key:ro
  - ./.env.${ENV}.encrypted:/app/.env.${ENV}.encrypted:ro
```

Pour chiffrer vos secrets :

```bash
# Chiffrer un fichier .env
python3 scripts/env-encrypt.py encrypt .env.prod

# Résultat: .env.prod.encrypted + .env.key
```

### Production

En production, les templates :
- N'exposent PAS les ports des bases de données
- Utilisent des utilisateurs non-root
- Ont des limites de ressources
- Activent les health checks
- Utilisent des réseaux isolés

## 🆕 Créer Votre Propre Template

1. Créer un dossier dans `templates/` :

```bash
mkdir deployment/templates/my-stack
```

2. Créer les fichiers :

```bash
cd deployment/templates/my-stack
touch docker-compose.yml
touch docker-compose.dev.yml
touch docker-compose.staging.yml
touch docker-compose.prod.yml
touch README.md
```

3. Définir vos services dans `docker-compose.yml`

4. Ajouter les overrides par environnement

5. Utiliser :

```bash
devops init --template my-stack
```

## 📝 Bonnes Pratiques

1. **Variables** : Toujours utiliser `${VAR:-default}` avec des valeurs par défaut
2. **Secrets** : Utiliser les fichiers chiffrés pour les données sensibles
3. **Health Checks** : Ajouter des health checks sur tous les services
4. **Labels** : Étiqueter tous les conteneurs (project, environment, service)
5. **Ressources** : Définir des limites en staging/prod
6. **Réseaux** : Isoler par environnement
7. **Volumes** : Nommer explicitement les volumes

## 🤝 Contribution

Pour ajouter un nouveau template :

1. Créer le dossier et les fichiers
2. Tester avec un projet exemple
3. Documenter dans un README.md
4. Mettre à jour ce fichier

---

**Note** : Les templates sont des points de départ. Adaptez-les à vos besoins !
