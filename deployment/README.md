# DevOps Engineering - CLI Centralisé de Déploiement

Un système de déploiement centralisé qui vous permet de déployer n'importe quel projet depuis un seul endroit, sans dupliquer les scripts de déploiement.

## 🎯 Problème Résolu

**Avant** :
- Dupliquer le dossier `deployment/` dans chaque projet
- Adapter les scripts pour chaque projet
- Maintenir plusieurs copies des mêmes scripts

**Après** :
- Un seul dossier `devop-enginering` central
- Chaque projet a juste un petit fichier `.devops.yml`
- Commandes `devops` disponibles globalement

## 🚀 Installation

### 1. Installer le CLI globalement

```bash
cd /Users/jeanmermozeffi/PycharmProjects/devops-enginering
./install.sh
```

### 2. Ajouter au PATH (si nécessaire)

Si le script d'installation vous le demande, ajoutez à votre `~/.zshrc` ou `~/.bashrc` :

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Puis rechargez :

```bash
source ~/.zshrc  # ou source ~/.bashrc
```

### 3. Vérifier l'installation

```bash
devops help
```

## 📦 Utilisation

### Initialiser un nouveau projet

Allez dans n'importe quel projet et initialisez-le :

```bash
cd /Users/jeanmermozeffi/PycharmProjects/akiliya-vision-core-backend
devops init
```

Cela crée :
- `.devops.yml` : Configuration du projet (à personnaliser)
- `.devops.yml.example` : Template à versionner
- `.env.dev`, `.env.staging`, `.env.prod` : Fichiers d'environnement

### Configurer le projet

Éditez `.devops.yml` créé :

```yaml
project_name: akiliya-vision-core-backend
compose_project_name: akiliya-backend

registry_username: effijeanmermoz
registry_url: docker.io
image_name: akiliya-backend

git_repo: https://github.com/votre-org/akiliya-vision-core-backend.git
github_token: # Optionnel

dev_branch: dev
staging_branch: staging
prod_branch: main
```

### Déployer

Une fois configuré, déployez depuis n'importe où dans votre projet :

```bash
# Déployer en dev
devops deploy dev

# Déployer en staging
devops deploy staging

# Déployer en prod
devops deploy prod

# Options avancées (identiques à deploy.sh)
devops deploy dev --no-cache
devops deploy dev --use-local
devops deploy prod --branch release/v1.0.0
```

### Créer un package de déploiement

Pour transférer vers un serveur :

```bash
devops package
```

### Gérer le registry Docker

```bash
# Créer une release
devops registry release prod v1.0.0

# Push vers le registry
devops registry push dev

# Pull depuis le registry
devops registry pull prod v1.0.0
```

## 📁 Structure

```
devop-enginering/
├── devops                          # CLI principal
├── install.sh                      # Script d'installation
├── .devops.yml.template            # Template de configuration
├── deployment/                     # Scripts de déploiement centralisés
│   ├── scripts/
│   │   ├── deploy.sh               # Script de déploiement
│   │   ├── registry.sh             # Gestion du registry
│   │   ├── create-deployment-package.sh
│   │   └── ...
│   ├── docker-compose.*.yml        # Templates Docker Compose
│   └── docker/                     # Dockerfiles
└── README.md                       # Cette documentation
```

Chaque projet a juste :
```
my-project/
├── .devops.yml                     # Configuration (non versionné)
├── .devops.yml.example             # Template (versionné)
├── .env.dev                        # Variables d'environnement dev
├── .env.staging                    # Variables d'environnement staging
├── .env.prod                       # Variables d'environnement prod
└── ... (votre code)
```

## 🔧 Commandes Disponibles

### `devops init`
Initialise un nouveau projet avec la configuration DevOps.

```bash
cd /path/to/my-project
devops init
```

### `devops deploy <env> [options]`
Déploie le projet dans l'environnement spécifié.

```bash
# Déploiement standard
devops deploy dev
devops deploy staging
devops deploy prod

# Avec options
devops deploy dev --no-cache           # Sans cache Docker
devops deploy dev --use-local          # Build depuis fichiers locaux
devops deploy dev --use-git            # Clone Git dans Docker
devops deploy prod --branch main       # Branche spécifique
```

### `devops package`
Crée un package de déploiement pour transfert vers un serveur.

```bash
devops package
```

Le package est créé dans `~/cicbi-deployment-package.tar.gz`.

### `devops registry <action> [options]`
Gère le registry Docker (push, pull, release, etc.).

```bash
# Créer une release versionnée
devops registry release prod v1.0.0

# Push une image
devops registry push dev

# Pull une image
devops registry pull prod v1.0.0

# Lister les tags
devops registry list-tags prod

# Gérer les profils
devops registry profile create dockerhub
devops registry profile list
```

## 🎨 Exemples Complets

### Exemple 1 : Nouveau projet API

```bash
# 1. Créer/aller dans votre projet
cd ~/Projects/my-new-api

# 2. Initialiser DevOps
devops init

# 3. Éditer la configuration
nano .devops.yml
# Configurez: project_name, registry_username, git_repo, etc.

# 4. Configurer les environnements
nano .env.dev
nano .env.staging
nano .env.prod

# 5. Déployer
devops deploy dev

# 6. Vérifier
docker ps
```

### Exemple 2 : Déployer akiliya-vision-core-backend

```bash
# 1. Aller dans le projet
cd /Users/jeanmermozeffi/PycharmProjects/akiliya-vision-core-backend

# 2. Initialiser (si pas déjà fait)
devops init

# 3. Configurer .devops.yml
nano .devops.yml

# Exemple de configuration:
# project_name: akiliya-vision-core-backend
# compose_project_name: akiliya-backend
# registry_username: effijeanmermoz
# image_name: akiliya-backend
# git_repo: https://github.com/your-org/akiliya-vision-core-backend.git
# dev_branch: dev
# prod_branch: main

# 4. Déployer
devops deploy dev

# 5. Créer une release pour prod
devops registry release prod v1.0.0

# 6. Déployer en prod depuis le registry
devops deploy prod --from-registry v1.0.0
```

### Exemple 3 : Workflow CI/CD

```bash
# Sur votre machine de dev
cd ~/Projects/my-api

# Développement quotidien
devops deploy dev --use-local   # Test rapide fichiers locaux

# Prêt pour staging
git push origin staging
devops deploy staging

# Release vers prod
devops registry release prod v1.2.0

# Sur le serveur de prod (via SSH)
ssh user@prod-server
cd /srv/my-api
devops deploy prod --from-registry v1.2.0
```

## 🔐 Sécurité

### Fichiers à ne PAS versionner

Ajoutez à `.gitignore` :

```gitignore
# DevOps configuration (peut contenir des tokens)
.devops.yml

# Fichiers d'environnement
.env.dev
.env.staging
.env.prod
.env.*
!.env.example

# Fichiers chiffrés
*.encrypted
.env.key
```

### Fichiers à versionner

- `.devops.yml.example` : Template sans secrets
- `.env.example` : Variables d'environnement template
- `.gitignore` : Ignorer les fichiers sensibles

### Bonnes pratiques

1. **Ne jamais commiter** `.devops.yml` s'il contient des tokens
2. **Toujours versionner** `.devops.yml.example` (sans secrets)
3. **Chiffrer les .env** en production (utilisez `devops package` qui chiffre automatiquement)
4. **Utiliser des tokens** avec permissions minimales
5. **Rotation régulière** des secrets et tokens

## 🔄 Migration depuis l'ancien système

Si vous avez déjà un projet avec `deployment/` :

```bash
# 1. Aller dans votre projet
cd /path/to/existing-project

# 2. Initialiser DevOps
devops init

# 3. Le script détecte automatiquement votre config existante
# et migre les paramètres vers .devops.yml

# 4. Supprimer l'ancien dossier deployment
rm -rf deployment/

# 5. Versionner les changements
git add .devops.yml.example .gitignore
git commit -m "Migration vers DevOps CLI centralisé"
```

## 🆘 Dépannage

### Commande `devops` introuvable

Vérifiez que `~/.local/bin` est dans votre PATH :

```bash
echo $PATH | grep ".local/bin"
```

Si absent, ajoutez à `~/.zshrc` :

```bash
export PATH="$HOME/.local/bin:$PATH"
source ~/.zshrc
```

### Erreur "Fichier .devops.yml introuvable"

Vous devez être dans un projet initialisé :

```bash
devops init
```

### Erreur de permissions Docker

```bash
# Ajouter votre utilisateur au groupe docker
sudo usermod -aG docker $USER

# Redémarrer la session
newgrp docker
```

### Les variables ne sont pas chargées

Vérifiez que vos fichiers `.env.{env}` existent et sont bien formatés :

```bash
ls -la .env.*
cat .env.dev
```

## 📚 Documentation Complète

Pour plus de détails sur les scripts sous-jacents :

- **[deployment/README.md](deployment/README.md)** : Guide des scripts de déploiement
- **[deployment/WORKFLOW.md](WORKFLOW.md)** : Workflows de déploiement
- **[deployment/GUIDE_CREATE_PACKAGE.md](GUIDE_CREATE_PACKAGE.md)** : Création de packages

## 🤝 Contribution

Pour améliorer le système DevOps :

1. Fork le projet `devop-enginering`
2. Créez une branche : `git checkout -b feature/ma-fonctionnalite`
3. Commitez : `git commit -m "Ajout de ma fonctionnalité"`
4. Push : `git push origin feature/ma-fonctionnalite`
5. Créez une Pull Request

## 📝 Changelog

### v1.0.0 (2026-01-12)
- ✨ Création du CLI centralisé `devops`
- ✨ Support multi-projets avec `.devops.yml`
- ✨ Installation globale avec `install.sh`
- ✨ Commandes : init, deploy, package, registry
- 📚 Documentation complète

## 📄 License

MIT License - Voir LICENSE pour plus de détails

---

**Version:** 1.0.0
**Date:** 12 janvier 2026
**Auteur:** Jean Mermoz Effi
