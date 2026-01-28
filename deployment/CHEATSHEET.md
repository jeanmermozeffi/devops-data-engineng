# 📋 DevOps CLI - Cheat Sheet

Aide-mémoire des commandes essentielles pour le DevOps CLI.

## 🚀 Installation (une seule fois)

```bash
cd /Users/jeanmermozeffi/PycharmProjects/devops-enginering
./install.sh

# Ajouter au PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## 🎯 Initialisation d'un Projet

```bash
cd /path/to/your-project
devops init                    # Créer .devops.yml
nano .devops.yml               # Configurer le projet
```

## 🔧 Déploiement

### Déploiement Standard

```bash
devops deploy dev              # Développement
devops deploy staging          # Staging
devops deploy prod             # Production
```

### Options de Déploiement

```bash
# Build sans cache Docker
devops deploy dev --no-cache

# Build depuis fichiers locaux (rapide pour tests)
devops deploy dev --use-local

# Clone Git dans le build Docker
devops deploy dev --use-git

# Déployer une branche spécifique
devops deploy dev --branch feature/my-feature

# Déployer depuis le registry
devops deploy prod --from-registry v1.0.0
```

## 📦 Gestion des Packages

```bash
# Créer un package de déploiement
devops package

# Le package est créé dans ~/cicbi-deployment-package.tar.gz
```

## 🐳 Gestion du Registry Docker

### Profils Registry

```bash
# Lister les profils
devops registry profile list

# Créer un nouveau profil
devops registry profile create dockerhub

# Charger un profil
devops registry profile load dockerhub

# Supprimer un profil
devops registry profile delete old-profile
```

### Push/Pull d'Images

```bash
# Push une image vers le registry
devops registry push dev
devops registry push prod

# Pull une image depuis le registry
devops registry pull dev
devops registry pull prod v1.0.0
```

### Releases et Versions

```bash
# Créer une release versionnée
devops registry release prod v1.0.0
devops registry release prod v1.2.3

# Lister les tags disponibles
devops registry list-tags prod
```

## 📊 Monitoring et Debug

### Avec DevOps CLI

```bash
# Statut des conteneurs
docker ps | grep <project-name>

# Logs en temps réel
docker logs -f <container-name>

# Dernières 100 lignes de logs
docker logs --tail 100 <container-name>

# Statistiques des conteneurs
docker stats
```

### Commandes Docker Utiles

```bash
# Arrêter tous les conteneurs d'un projet
docker stop $(docker ps -q --filter "name=<project-name>")

# Supprimer tous les conteneurs arrêtés
docker rm $(docker ps -a -q --filter "status=exited")

# Nettoyer les images inutilisées
docker image prune -f

# Nettoyer complètement Docker
docker system prune -a -f --volumes
```

## 🔐 Fichiers de Configuration

### Structure .devops.yml

```yaml
project_name: my-project
compose_project_name: my-project-backend
registry_username: your-username
registry_url: docker.io
image_name: my-project-backend
git_repo: https://github.com/org/repo.git
github_token: # optionnel
dev_branch: dev
staging_branch: staging
prod_branch: main
```

### Fichiers .env

```bash
# Fichiers à créer/éditer
.env.dev        # Variables développement
.env.staging    # Variables staging
.env.prod       # Variables production

# Fichiers à versionner
.env.example           # Template des variables
.devops.yml.example    # Template de configuration
```

## 🔄 Workflows Courants

### Développement Quotidien

```bash
# Tests rapides locaux
devops deploy dev --use-local

# Après commit
git push
devops deploy dev
```

### Release vers Staging

```bash
# Merge vers staging
git checkout staging
git merge dev
git push

# Déployer
devops deploy staging
```

### Release vers Production

```bash
# 1. Créer une release versionnée
devops registry release prod v1.2.0

# 2. Sur le serveur de prod
ssh user@prod-server
cd /srv/my-project
devops deploy prod --from-registry v1.2.0

# 3. Vérifier
docker ps
docker logs <container-name>
```

### Package pour Transfert Serveur

```bash
# 1. Créer le package
devops package

# 2. Transférer vers serveur
scp ~/cicbi-deployment-package.tar.gz user@server:/srv/

# 3. Sur le serveur
ssh user@server
cd /srv
tar -xzf cicbi-deployment-package.tar.gz
cd cicbi-deployment-package
./install.sh
devops deploy prod
```

## 🐛 Dépannage Rapide

### CLI non trouvé

```bash
# Vérifier PATH
echo $PATH | grep ".local/bin"

# Réinstaller
cd /Users/jeanmermozeffi/PycharmProjects/devops-enginering
./install.sh
```

### Erreur ".devops.yml introuvable"

```bash
# Vérifier que vous êtes dans le bon dossier
pwd

# Initialiser si nécessaire
devops init
```

### Conteneurs qui ne démarrent pas

```bash
# Vérifier les logs
docker logs <container-name>

# Vérifier les ports
netstat -an | grep LISTEN

# Arrêter et nettoyer
docker stop $(docker ps -q --filter "name=<project>")
docker system prune -f
devops deploy dev --no-cache
```

### Conflit de ports

```bash
# Trouver ce qui utilise le port
lsof -i :8000

# Tuer le processus
kill -9 <PID>

# Redéployer
devops deploy dev
```

### Variables d'environnement non chargées

```bash
# Vérifier que les .env sont à la racine
ls -la .env.*

# Vérifier le contenu
cat .env.dev

# Format attendu:
# KEY=value (pas d'espaces autour du =)
```

## 🎓 Commandes Essentielles par Fréquence

### Quotidiennes

```bash
devops deploy dev --use-local
docker logs -f <container>
docker ps
```

### Hebdomadaires

```bash
devops deploy staging
devops registry push staging
docker system prune -f
```

### Mensuelles

```bash
devops registry release prod v1.x.x
devops deploy prod --from-registry v1.x.x
devops package
```

## 📝 Configuration Git (Bonnes Pratiques)

### Fichiers à versionner

```bash
.devops.yml.example
.env.example
.gitignore
README.md
```

### Fichiers à NE PAS versionner

```bash
.devops.yml       # Peut contenir des tokens
.env.dev
.env.staging
.env.prod
.env.*
*.key
*.encrypted
```

### .gitignore Recommandé

```gitignore
# DevOps
.devops.yml
.env.*
!.env.example
*.key
*.encrypted

# Docker
.env

# Temporaires
.tmp-deployments/
*.backup
*.tar.gz
```

## 🔗 Ressources

```bash
devops help                # Aide du CLI
cat README.md              # Documentation complète
cat QUICKSTART.md          # Guide 5 minutes
cat MIGRATION.md           # Guide de migration
cat CHEATSHEET.md          # Ce fichier
```

## 🆘 Support Rapide

**Problème commun** → **Solution rapide**

| Problème | Solution |
|----------|----------|
| CLI non trouvé | `./install.sh` puis ajouter au PATH |
| .devops.yml manquant | `devops init` |
| Conteneur ne démarre pas | Vérifier logs : `docker logs <name>` |
| Port déjà utilisé | `lsof -i :<port>` puis `kill -9 <PID>` |
| Variables non chargées | Vérifier `.env.dev` existe et format correct |
| Build échoue | `devops deploy dev --no-cache` |
| Registry échoue | Vérifier profil : `devops registry profile list` |

---

**Version:** 1.0.0
**Mise à jour:** 12 janvier 2026

💡 **Astuce** : Marquez cette page pour un accès rapide !
