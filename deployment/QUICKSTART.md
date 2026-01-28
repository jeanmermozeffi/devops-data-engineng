# 🚀 Guide de Démarrage Rapide - DevOps CLI

Ce guide vous permet de déployer votre premier projet en **5 minutes**.

## Étape 1 : Installation (1 minute)

```bash
cd /Users/jeanmermozeffi/PycharmProjects/devops-enginering
./install.sh
```

Si nécessaire, ajoutez à votre `~/.zshrc` :
```bash
export PATH="$HOME/.local/bin:$PATH"
source ~/.zshrc
```

Testez :
```bash
devops help
```

## Étape 2 : Initialiser votre projet (2 minutes)

Allez dans votre projet et initialisez-le :

```bash
cd /Users/jeanmermozeffi/PycharmProjects/akiliya-vision-core-backend
devops init
```

Cela crée :
- ✅ `.devops.yml` (votre configuration)
- ✅ `.devops.yml.example` (template à versionner)
- ✅ `.env.dev`, `.env.staging`, `.env.prod` (si inexistants)

## Étape 3 : Configurer (1 minute)

Éditez `.devops.yml` :

```bash
nano .devops.yml
```

Configuration minimale :

```yaml
project_name: akiliya-vision-core-backend
compose_project_name: akiliya-backend

registry_username: effijeanmermoz  # Votre username Docker Hub
registry_url: docker.io
image_name: akiliya-backend

git_repo: https://github.com/votre-org/akiliya-vision-core-backend.git

dev_branch: dev
staging_branch: staging
prod_branch: main
```

## Étape 4 : Déployer (1 minute)

C'est tout ! Déployez maintenant :

```bash
devops deploy dev
```

Vérifiez :
```bash
docker ps
```

## 🎉 C'est fini !

Vous pouvez maintenant :

### Déployer en staging ou prod
```bash
devops deploy staging
devops deploy prod
```

### Créer une release
```bash
devops registry release prod v1.0.0
```

### Créer un package pour serveur
```bash
devops package
```

### Déployer depuis le registry
```bash
devops deploy prod --from-registry v1.0.0
```

## 📖 Prochaines étapes

- **Configurez vos .env** : Éditez `.env.dev`, `.env.staging`, `.env.prod`
- **Lisez le README** : `cat README.md` pour la documentation complète
- **Explorez les options** : `devops help`

## 🔥 Commandes les plus utilisées

```bash
# Développement quotidien
devops deploy dev --use-local    # Build rapide depuis fichiers locaux

# Release vers staging
devops deploy staging

# Release vers prod
devops registry release prod v1.2.0
devops deploy prod --from-registry v1.2.0

# Package pour transfert serveur
devops package
```

## ❓ Besoin d'aide ?

```bash
devops help                    # Aide générale
cat README.md                  # Documentation complète
cat deployment/WORKFLOW.md     # Workflows détaillés
```

---

**Astuce** : Une fois configuré, vous pouvez déployer **n'importe quel projet** de la même façon. Plus besoin de dupliquer les scripts !
