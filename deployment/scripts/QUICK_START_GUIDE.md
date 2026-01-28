# 🚀 Guide de démarrage rapide - deploy-registry.sh

## ⚡ Commandes essentielles

### 🎯 Utilisation normale
```bash
# Lancer le menu interactif
./deployment/scripts/deploy-registry.sh

# Déployer directement (mode CLI)
./deployment/scripts/deploy-registry.sh deploy dev dev-latest
./deployment/scripts/deploy-registry.sh deploy staging staging-v1.0.0
./deployment/scripts/deploy-registry.sh deploy prod prod-v2.1.0

# Lister les tags disponibles
./deployment/scripts/deploy-registry.sh list-tags dev

# Voir les logs
./deployment/scripts/deploy-registry.sh logs dev cicbi-api
./deployment/scripts/deploy-registry.sh logs prod redis

# Statut des conteneurs
./deployment/scripts/deploy-registry.sh status dev
```

---

## 🔧 Gestion des profils

### Créer un nouveau profil
```bash
./deployment/scripts/deploy-registry.sh
# → Option 9 (Créer un nouveau profil)
```

### Éditer un profil existant
```bash
./deployment/scripts/deploy-registry.sh
# → Option 13 (Éditer un profil) ⭐ NOUVEAU
```

### Lister les profils
```bash
./deployment/scripts/deploy-registry.sh
# → Option 11 (Lister les profils)
```

### Charger un profil
```bash
./deployment/scripts/deploy-registry.sh
# → Option 10 (Charger un profil existant)
```

### Supprimer un profil
```bash
./deployment/scripts/deploy-registry.sh
# → Option 14 (Supprimer un profil)
```

---

## 🔒 Sécurité des profils

### Chiffrer un profil
```bash
# Via le menu
./deployment/scripts/deploy-registry.sh
# → Option 15 (Chiffrer un profil existant)

# Via la ligne de commande
python3 deployment/scripts/env-encrypt.py encrypt \
  deployment/scripts/.registry-profiles/dockerhub-dev.env
```

### Déchiffrer un profil (temporaire)
```bash
python3 deployment/scripts/env-encrypt.py decrypt \
  deployment/scripts/.registry-profiles/dockerhub-dev.env.encrypted
```

### Vérifier un profil chiffré
```bash
# Afficher le profil actuel (déchiffré temporairement)
./deployment/scripts/deploy-registry.sh
# → Option 12 (Afficher le profil actuel)
```

---

## 🧪 Tests et diagnostic

### Tester le script
```bash
# Vérifier la syntaxe
bash -n deployment/scripts/deploy-registry.sh

# Tests automatisés
./deployment/scripts/test-deploy-registry.sh
```

### Migrer les anciens profils
```bash
./deployment/scripts/migrate-profiles.sh
```

---

## 📋 Structure des profils

### Format standardisé
```bash
# Profil Registry: dockerhub-dev
# Type: Docker Hub (docker.io)
# Créé le: [date]

REGISTRY_TYPE=dockerhub
REGISTRY_URL=docker.io
REGISTRY_USERNAME=effijeanmermoz
REGISTRY_TOKEN=dckr_pat_xxxxx          # Chiffré dans .env.encrypted
REGISTRY_PASSWORD=                      # Optionnel
IMAGE_NAME=cicbi-api-backend
GIT_REPO=git@github.com:user/repo.git
GITHUB_TOKEN=ghp_xxxxx                  # Chiffré dans .env.encrypted
DEV_BRANCH=dev
STAGING_BRANCH=staging
PROD_BRANCH=prod
```

### Profil chiffré
```bash
# Les secrets sont chiffrés avec Fernet
REGISTRY_TOKEN=ENC[gAAAAABpQ_vBWQ-ltVe...]
GITHUB_TOKEN=ENC[gAAAAABpQ_vBNX-PD0hw...]
```

---

## 🗂️ Organisation des fichiers

```
deployment/scripts/
├── deploy-registry.sh              # Script principal ⭐
├── registry.sh                     # Build et push des images
├── env-encrypt.py                  # Chiffrement/déchiffrement
├── test-deploy-registry.sh         # Tests automatisés
├── migrate-profiles.sh             # Migration des profils
│
├── .registry-profiles/             # Profils de registry
│   ├── .gitignore                 # Protection Git
│   ├── .current                   # Profil actif (local)
│   └── dockerhub-dev.env.encrypted # Profil chiffré
│
└── docs/
    ├── DEPLOY_REGISTRY_IMPROVEMENTS.md
    └── CORRECTIONS_COMPLETEES.md
```

---

## 🎨 Menu principal

```
╔════════════════════════════════════════════════════╗
║  CICBI API - Déploiement Registry (Mode Interactif)║
╚════════════════════════════════════════════════════╝

Configuration actuelle:
  Registry: dockerhub (docker.io)
  Image: effijeanmermoz/cicbi-api-backend

----------------------------------------
DÉPLOIEMENT
  1) Déployer une image existante
  2) Lister les tags disponibles

GESTION
  3) Voir le statut des conteneurs
  4) Voir les logs
  5) Redémarrer les services
  6) Arrêter les services

AVANCÉ
  7) Télécharger une image (sans déployer)
  8) Créer et déployer une nouvelle release

GESTION DES PROFILS
  9)  Créer un nouveau profil
  10) Charger un profil existant
  11) Lister les profils
  12) Afficher le profil actuel
  13) Éditer un profil ⭐ NOUVEAU
  14) Supprimer un profil
  15) Chiffrer un profil existant

  0) Quitter
----------------------------------------

Votre choix:
```

---

## 📝 Workflows courants

### 1️⃣ Première utilisation (aucun profil)
```bash
./deployment/scripts/deploy-registry.sh

→ [WARN] Aucun profil registry trouvé!
→ Voulez-vous créer un nouveau profil maintenant? (y/N): y

# Suivre les instructions :
Nom du profil: dockerhub-dev
Type de registry: dockerhub
URL: docker.io
Username: effijeanmermoz
Token: dckr_pat_xxxxx
Image: cicbi-api-backend

→ ✅ Profil créé et chiffré automatiquement
```

### 2️⃣ Modifier un token expiré
```bash
./deployment/scripts/deploy-registry.sh

→ Option 13 (Éditer un profil)
→ Sélectionner: 1 (dockerhub-dev)
→ Option 4 (REGISTRY_TOKEN)
→ Entrer le nouveau token
→ Option s (Sauvegarder)

→ ✅ Profil sauvegardé et rechiffré automatiquement
```

### 3️⃣ Déployer une nouvelle version
```bash
./deployment/scripts/deploy-registry.sh

→ Option 1 (Déployer)
→ Environnement: 1 (dev)
→ Tag: dev-latest

→ ✅ Image déployée avec succès
```

### 4️⃣ Créer un profil pour staging
```bash
./deployment/scripts/deploy-registry.sh

→ Option 9 (Créer un nouveau profil)
→ Nom: dockerhub-staging
→ Remplir les informations
→ Chiffrer: y

→ ✅ Profil staging créé
```

---

## 🔐 Bonnes pratiques de sécurité

### ✅ À FAIRE
- ✅ Chiffrer tous les profils contenant des secrets
- ✅ Garder `.env.key` en sécurité (ne pas committer)
- ✅ Utiliser `.gitignore` pour les profils
- ✅ Utiliser des tokens avec permissions minimales
- ✅ Régénérer les tokens régulièrement

### ❌ À NE PAS FAIRE
- ❌ Committer des profils non chiffrés
- ❌ Committer des profils chiffrés (la clé est locale)
- ❌ Partager `.env.key` via Git
- ❌ Utiliser le même token pour dev/staging/prod
- ❌ Laisser des profils non chiffrés sur le serveur

---

## 🆘 Dépannage

### Problème : Profil non trouvé au démarrage
```bash
# Le script propose automatiquement de créer un profil
→ Répondre 'y' et suivre les instructions
```

### Problème : Erreur de déchiffrement
```bash
# Vérifier que .env.key existe
ls -la .env.key

# Recréer le profil si nécessaire
./deployment/scripts/deploy-registry.sh
→ Option 9 (Créer un nouveau profil)
```

### Problème : Image non trouvée dans le registry
```bash
# Lister les tags disponibles
./deployment/scripts/deploy-registry.sh list-tags dev

# Vérifier que l'image a bien été pushée
docker pull effijeanmermoz/cicbi-api-backend:dev-latest
```

### Problème : Profil au mauvais format
```bash
# Migrer automatiquement
./deployment/scripts/migrate-profiles.sh
```

---

## 📚 Documentation complète

- `DEPLOY_REGISTRY_IMPROVEMENTS.md` - Améliorations détaillées
- `CORRECTIONS_COMPLETEES.md` - Résumé des corrections
- `deployment/docs/DEPLOYMENT_REGISTRY.md` - Documentation technique

---

## ✨ Résumé

**Le script est maintenant :**
- ✅ Sécurisé (chiffrement automatique)
- ✅ Interactif (menu complet avec édition)
- ✅ Robuste (gestion d'erreurs, validation)
- ✅ Documenté (guides, exemples)
- ✅ Testé (tests automatisés)

**Prêt pour la production ! 🚀**

