# 🚀 Déploiement depuis Docker Registry

Ce guide explique comment déployer l'application CICBI API depuis un registry Docker (Docker Hub, GitHub Container Registry, GitLab Container Registry, etc.).

## 📋 Table des matières

- [Vue d'ensemble](#vue-densemble)
- [Configuration initiale](#configuration-initiale)
- [Déploiement rapide](#déploiement-rapide)
- [Commandes disponibles](#commandes-disponibles)
- [Exemples d'utilisation](#exemples-dutilisation)
- [Gestion des versions](#gestion-des-versions)

---

## 🎯 Vue d'ensemble

### Différence entre build local et registry

| Aspect | Build Local | Registry |
|--------|-------------|----------|
| Fichiers | `docker-compose.dev.yml` | `docker-compose.registry.yml` + `docker-compose.dev-registry.yml` |
| Source | Code local ou Git clone | Image pré-construite sur Docker Hub |
| Vitesse | Lent (build complet) | Rapide (pull uniquement) |
| Usage | Développement, CI/CD | Production, déploiement |

### Architecture des fichiers

```
deployment/
├── docker-compose.registry.yml           # Configuration de base
├── docker-compose.dev-registry.yml       # Surcharge dev (ports, env)
├── docker-compose.prod-registry.yml      # Surcharge prod (ports, env, limites)
├── .env.registry                         # Configuration du registry
├── .env.registry.example                 # Exemple de configuration
└── scripts/
    └── deploy-registry.sh                # Script de déploiement
```

---

## ⚙️ Configuration initiale

### 1. Créer le fichier de configuration

```bash
cd deployment
cp .env.registry.example .env.registry
```

### 2. Éditer la configuration

```bash
nano .env.registry
```

**Exemple pour Docker Hub :**
```bash
REGISTRY_TYPE=dockerhub
REGISTRY_URL=docker.io
REGISTRY_USERNAME=effijeanmermoz
IMAGE_NAME=cicbi-api-backend
ENVIRONMENT=dev
IMAGE_TAG=dev-latest
```

**Exemple pour GitHub Container Registry :**
```bash
REGISTRY_TYPE=github
REGISTRY_URL=ghcr.io
REGISTRY_USERNAME=cicbi
IMAGE_NAME=cicbi-api-backend
ENVIRONMENT=prod
IMAGE_TAG=prod-latest
```

### 3. Vérifier les fichiers d'environnement

Assurez-vous que les fichiers `.env.dev` et `.env.prod` existent :

```bash
ls -la deployment/.env.*
```

---

## 🚀 Déploiement rapide

### Déployer en dev (dernière version)

```bash
cd deployment
./scripts/deploy-registry.sh deploy dev
```

### Déployer en prod (dernière version)

```bash
cd deployment
./scripts/deploy-registry.sh deploy prod
```

### Déployer une version spécifique

```bash
# Lister les versions disponibles
./scripts/deploy-registry.sh list-tags dev

# Déployer une version précise
./scripts/deploy-registry.sh deploy dev dev-v20251216-163525-3be7822
```

---

## 📚 Commandes disponibles

### Déploiement

```bash
# Déployer avec le tag par défaut (dev-latest ou prod-latest)
./scripts/deploy-registry.sh deploy <env>

# Déployer avec un tag spécifique
./scripts/deploy-registry.sh deploy <env> <tag>

# Exemples
./scripts/deploy-registry.sh deploy dev
./scripts/deploy-registry.sh deploy dev dev-v20251216-163525-3be7822
./scripts/deploy-registry.sh deploy prod prod-v1.2.3
```

### Gestion des tags

```bash
# Lister tous les tags disponibles pour un environnement
./scripts/deploy-registry.sh list-tags <env>

# Exemples
./scripts/deploy-registry.sh list-tags dev
./scripts/deploy-registry.sh list-tags prod
```

### Téléchargement

```bash
# Télécharger une image sans la déployer
./scripts/deploy-registry.sh pull <env> [tag]

# Exemples
./scripts/deploy-registry.sh pull dev
./scripts/deploy-registry.sh pull prod prod-v1.2.3
```

### Gestion des services

```bash
# Voir le statut des conteneurs
./scripts/deploy-registry.sh status <env>

# Voir les logs
./scripts/deploy-registry.sh logs <env> [service]

# Arrêter les services
./scripts/deploy-registry.sh stop <env>

# Redémarrer les services
./scripts/deploy-registry.sh restart <env>

# Exemples
./scripts/deploy-registry.sh status dev
./scripts/deploy-registry.sh logs dev cicbi-api
./scripts/deploy-registry.sh logs prod redis
./scripts/deploy-registry.sh stop dev
./scripts/deploy-registry.sh restart prod
```

---

## 💡 Exemples d'utilisation

### Scénario 1 : Déploiement initial en dev

```bash
cd deployment

# 1. Configurer le registry
cp .env.registry.example .env.registry
nano .env.registry  # Ajuster REGISTRY_USERNAME, etc.

# 2. Voir les versions disponibles
./scripts/deploy-registry.sh list-tags dev

# 3. Déployer la dernière version
./scripts/deploy-registry.sh deploy dev

# 4. Vérifier le déploiement
./scripts/deploy-registry.sh status dev
./scripts/deploy-registry.sh logs dev
```

### Scénario 2 : Mise à jour en production

```bash
cd deployment

# 1. Lister les tags disponibles
./scripts/deploy-registry.sh list-tags prod

# Sortie exemple:
# Tags disponibles pour prod:
#   1) prod-latest (recommandé)
#   2) prod-v1.2.3
#   3) prod-v1.2.2
#   4) prod-v20251216-163525-3be7822

# 2. Déployer une version spécifique
./scripts/deploy-registry.sh deploy prod prod-v1.2.3

# 3. Vérifier que tout fonctionne
./scripts/deploy-registry.sh status prod
curl http://localhost:8002/health

# 4. Voir les logs
./scripts/deploy-registry.sh logs prod
```

### Scénario 3 : Rollback en production

```bash
# En cas de problème avec la version actuelle

# 1. Voir les versions précédentes
./scripts/deploy-registry.sh list-tags prod

# 2. Revenir à une version stable
./scripts/deploy-registry.sh deploy prod prod-v1.2.2

# 3. Vérifier
./scripts/deploy-registry.sh status prod
```

### Scénario 4 : Utilisation manuelle avec docker-compose

```bash
cd deployment

# Exporter les variables
export ENVIRONMENT=dev
export IMAGE_TAG=dev-latest
export IMAGE_FULL=effijeanmermoz/cicbi-api-backend:dev-latest

# Déployer
docker-compose -f docker-compose.registry.yml -f docker-compose.dev-registry.yml up -d

# Voir les logs
docker-compose -f docker-compose.registry.yml -f docker-compose.dev-registry.yml logs -f

# Arrêter
docker-compose -f docker-compose.registry.yml -f docker-compose.dev-registry.yml down
```

---

## 📦 Gestion des versions

### Convention de nommage des tags

#### Tags automatiques (générés par registry.sh)
```
<env>-v<date>-<time>-<git-hash>

Exemples:
- dev-v20251216-163525-3be7822
- prod-v20251216-163525-3be7822
```

#### Tags latest
```
<env>-latest

Exemples:
- dev-latest   (toujours la dernière version dev)
- prod-latest  (toujours la dernière version prod)
```

#### Tags manuels (versions sémantiques)
```
<env>-v<major>.<minor>.<patch>

Exemples:
- prod-v1.2.3
- prod-v2.0.0
```

### Workflow recommandé

#### Développement
```bash
# 1. Build et push avec registry.sh
./deployment/scripts/registry.sh release dev

# 2. Déployer sur serveur dev
./deployment/scripts/deploy-registry.sh deploy dev
```

#### Production
```bash
# 1. Build et tag avec version sémantique
./deployment/scripts/registry.sh release prod v1.2.3

# 2. Lister les versions
./deployment/scripts/deploy-registry.sh list-tags prod

# 3. Déployer la version vérifiée
./deployment/scripts/deploy-registry.sh deploy prod prod-v1.2.3

# 4. Mettre à jour le tag latest
docker pull effijeanmermoz/cicbi-api-backend:prod-v1.2.3
docker tag effijeanmermoz/cicbi-api-backend:prod-v1.2.3 effijeanmermoz/cicbi-api-backend:prod-latest
docker push effijeanmermoz/cicbi-api-backend:prod-latest
```

---

## 🔧 Dépannage

### L'image n'est pas trouvée

```bash
# Vérifier que l'image existe dans le registry
./scripts/deploy-registry.sh list-tags dev

# Vérifier la connexion au registry
docker login docker.io
```

### Les conteneurs ne démarrent pas

```bash
# Voir les logs
./scripts/deploy-registry.sh logs dev

# Vérifier le fichier .env.dev
cat .env.dev

# Vérifier les variables
docker-compose -f docker-compose.registry.yml -f docker-compose.dev-registry.yml config
```

### Port déjà utilisé

```bash
# Arrêter les anciens conteneurs
./scripts/deploy-registry.sh stop dev

# Vérifier qu'aucun conteneur n'utilise le port
docker ps -a | grep 8001
```

---

## 📝 Notes importantes

1. **Fichiers .env séparés** : Les fichiers `.env.dev` et `.env.prod` contiennent les variables spécifiques à l'application (DB, secrets, etc.)

2. **Fichier .env.registry** : Contient uniquement la configuration du registry (URL, username, image, tag)

3. **Sécurité** : Ne commitez JAMAIS les fichiers `.env.*` dans Git

4. **Tags latest** : Utiliser avec prudence en production, préférer les versions spécifiques

5. **Limites de ressources** : Configurées dans `docker-compose.prod-registry.yml`

---

## 🔗 Ressources

- [Script registry.sh](../scripts/registry.sh) - Build et push des images
- [Script deploy-registry.sh](../scripts/deploy-registry.sh) - Déploiement depuis registry
- [Docker Compose Registry](../compose/docker-compose.registry.yml) - Configuration de base
- [Exemples .env](../.env.registry.example) - Configuration du registry

---

## ✅ Checklist de déploiement

### Première fois
- [ ] Copier `.env.registry.example` vers `.env.registry`
- [ ] Configurer `REGISTRY_USERNAME` et `IMAGE_NAME`
- [ ] Vérifier que `.env.dev` et `.env.prod` existent
- [ ] Tester le listing des tags : `./scripts/deploy-registry.sh list-tags dev`
- [ ] Déployer en dev : `./scripts/deploy-registry.sh deploy dev`

### Déploiement en production
- [ ] Build et push : `./deployment/scripts/registry.sh release prod v1.2.3`
- [ ] Lister les tags : `./scripts/deploy-registry.sh list-tags prod`
- [ ] Déployer : `./scripts/deploy-registry.sh deploy prod prod-v1.2.3`
- [ ] Vérifier le statut : `./scripts/deploy-registry.sh status prod`
- [ ] Tester l'application : `curl http://localhost:8002/health`
- [ ] Surveiller les logs : `./scripts/deploy-registry.sh logs prod`

Bon déploiement ! 🚀

