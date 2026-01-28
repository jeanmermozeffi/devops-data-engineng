# 📦 Guide - Création de package de déploiement

## 🎯 Script amélioré : create-deployment-package.sh

Le script a été complètement réécrit pour être **interactif** et permettre le **transfert SSH automatique**.

---

## ✅ Nouvelles fonctionnalités

### 1. 🎨 Interface interactive

Menu principal avec navigation claire :
```
╔════════════════════════════════════════════════════╗
║  Création du package de déploiement               ║
╚════════════════════════════════════════════════════╝

Options de création:

  1) Créer le package uniquement
  2) Créer et copier vers le serveur (SSH)
  3) Configuration avancée

  0) Quitter
```

### 2. 📤 Transfert SSH automatique

Le script peut maintenant :
- ✅ Se connecter au VPS via SSH
- ✅ Transférer le package
- ✅ Décompresser automatiquement
- ✅ Installer les permissions

**Deux méthodes d'authentification :**
- Clé SSH (recommandé)
- Mot de passe (nécessite `sshpass`)

### 3. ⚙️ Configuration personnalisable

- Chemin du package local
- Serveur SSH (IP/hostname)
- Utilisateur SSH
- Port SSH (défaut: 22)
- **Destination sur le serveur (défaut: /srv/home/cicbi-api-backend)**
- Création automatique du dossier de destination s'il n'existe pas

---

## 🚀 Utilisation

### Lancement

```bash
cd /Users/jeanmermozeffi/PycharmProjects/cicbi-api-backend
./deployment/scripts/create-deployment-package.sh
```

---

## 📋 Options disponibles

### Option 1 : Créer le package uniquement

**Utilisation :**
- Crée le package dans `~/cicbi-deployment-package`
- Génère l'archive `~/cicbi-deployment-package.tar.gz`
- Affiche les statistiques et la structure

**Résultat :**
```
✓ Archive créée: ~/cicbi-deployment-package.tar.gz
✓ Taille: 95K
✓ Fichiers: 15

Structure du package:
.
./.env.dev
./.env.prod
./.env.registry
./docker-compose.registry.yml
./docker-compose.dev-registry.yml
./install.sh
./README.md
./scripts/
./scripts/deploy-registry.sh
...
```

**Ensuite :**
- Transférez manuellement : `scp ~/cicbi-deployment-package.tar.gz user@vps:/srv/`

---

### Option 2 : Créer et copier vers le serveur (SSH)

**Workflow complet :**

#### Étape 1 : Configuration SSH

Le script vous demande :

```
Configuration SSH

Adresse IP ou hostname du serveur: 51.79.8.116
Nom d'utilisateur SSH [cicbi]: cicbi
Port SSH [22]: 22
Chemin de destination sur le serveur [/srv/home/cicbi-api-backend]: /srv/home/cicbi-api-backend

Méthode d'authentification:
  1) Clé SSH (recommandé)
  2) Mot de passe

Votre choix [1]: 1

────────────────────────────────────────────────────
Récapitulatif SSH:
  Serveur    : cicbi@51.79.8.116:22
  Destination: /srv/home/cicbi-api-backend
  Auth       : Clé SSH
────────────────────────────────────────────────────

Confirmer cette configuration (Y/n): y
```

#### Étape 2 : Création du package

Le script crée le package comme l'option 1.

#### Étape 3 : Transfert SSH

```
Transfert SSH

Test de connexion SSH...
✓ Connexion SSH réussie

Création du répertoire distant...
Transfert de l'archive (95K)...
✓ Archive transférée

Décompresser automatiquement sur le serveur (Y/n): y

Décompression sur le serveur...
✓ Package installé dans /srv/home/cicbi-api-backend

────────────────────────────────────────────────────
✓ Transfert terminé !

Sur le serveur, exécutez:
  cd /srv/home/cicbi-api-backend
  ./install.sh
  ./scripts/deploy-registry.sh deploy dev
────────────────────────────────────────────────────
```

---

### Option 3 : Configuration avancée

Permet de personnaliser :
- Chemin du package local
- Fichiers à inclure/exclure (à venir)

---

## 🔑 Authentification SSH

### Méthode 1 : Clé SSH (Recommandé)

**Prérequis :**
```bash
# Générer une clé SSH si nécessaire
ssh-keygen -t ed25519 -C "votre@email.com"

# Copier la clé sur le VPS
ssh-copy-id -p 22 cicbi@51.79.8.116
```

**Avantages :**
- ✅ Sécurisé
- ✅ Pas de mot de passe à saisir
- ✅ Standard

---

### Méthode 2 : Mot de passe

**Prérequis :**
```bash
# Installer sshpass
# macOS
brew install hudochenkov/sshpass/sshpass

# Linux
sudo apt-get install sshpass
```

**Utilisation :**
- Le script demande le mot de passe (caché)
- Moins sécurisé mais fonctionnel

---

## 📦 Contenu du package

Le package créé contient :

```
cicbi-deployment-package/
├── .env.dev                          # Variables dev
├── .env.staging                      # Variables staging
├── .env.prod                         # Variables prod
├── .env.registry                     # Config Docker Hub
├── .registry-profiles                # Profils registry
├── docker-compose.registry.yml       # Compose base
├── docker-compose.dev-registry.yml   # Surcharge dev
├── docker-compose.staging-registry.yml
├── docker-compose.prod-registry.yml
├── install.sh                        # Script d'installation
├── README.md                         # Documentation
├── .gitignore
└── scripts/
    ├── deploy-registry.sh            # Script de déploiement
    ├── diagnose-php-connection.sh    # Diagnostic
    └── fix-*.sh                      # Scripts de correction
```

**Taille :** ~100 KB (aucun code source)

---

## 🔧 Workflow complet

### Sur votre Mac

```bash
# 1. Lancer le script
./deployment/scripts/create-deployment-package.sh

# 2. Choisir l'option 2 (Créer et copier)

# 3. Configurer SSH :
#    - IP: 51.79.8.116
#    - User: cicbi
#    - Port: 22
#    - Auth: Clé SSH

# 4. Confirmer

# ✅ Le script fait tout automatiquement !
```

### Sur le VPS

```bash
# 1. Se connecter
ssh cicbi@51.79.8.116

# 2. Aller dans le dossier
cd /srv/home/cicbi-api-backend

# 3. Installer
./install.sh

# 4. Déployer
./scripts/deploy-registry.sh deploy dev
```

---

## 🎯 Cas d'usage

### Cas 1 : Première installation

```bash
# Sur Mac
./deployment/scripts/create-deployment-package.sh
# → Option 2
# → Configurer SSH
# → Laisser le script faire

# Sur VPS
ssh cicbi@vps
cd /srv/home/cicbi-api-backend
./install.sh
./scripts/deploy-registry.sh deploy prod
```

---

### Cas 2 : Mise à jour

```bash
# Sur Mac
./deployment/scripts/create-deployment-package.sh
# → Option 2 (écrase l'ancien package)

# Sur VPS
cd /srv/home/cicbi-api-backend
git pull  # Si nécessaire
./scripts/deploy-registry.sh deploy prod
```

---

### Cas 3 : Package uniquement (transfert manuel)

```bash
# Sur Mac
./deployment/scripts/create-deployment-package.sh
# → Option 1

# Transférer manuellement
scp ~/cicbi-deployment-package.tar.gz cicbi@vps:/srv/home/

# Sur VPS
cd /srv/home
tar -xzf cicbi-deployment-package.tar.gz
mv cicbi-deployment-package cicbi-api-backend
cd cicbi-api-backend
./install.sh
```

---

## 🔍 Diagnostic

### Test de connexion SSH

```bash
# Tester la connexion avant d'utiliser le script
ssh -p 22 cicbi@51.79.8.116

# Si ça fonctionne → Option 2 du script
# Sinon → Configurer SSH d'abord
```

### Erreur sshpass non trouvé

```bash
# Installer sshpass
brew install hudochenkov/sshpass/sshpass

# Ou utiliser la clé SSH (recommandé)
```

### Erreur de connexion SSH

**Vérifier :**
1. L'IP/hostname est correct
2. Le port SSH est correct (22 par défaut)
3. L'utilisateur existe sur le VPS
4. La clé SSH est configurée (si mode clé)

---

## 📊 Comparaison avant/après

### ❌ Avant (manuel)

```bash
# 1. Créer le package manuellement
mkdir ~/package
cp deployment/*.yml ~/package/
cp .env.* ~/package/
tar -czf package.tar.gz ~/package/

# 2. Transférer
scp package.tar.gz user@vps:/srv/

# 3. Se connecter
ssh user@vps

# 4. Décompresser
cd /srv
tar -xzf package.tar.gz

# 5. Configurer
chmod +x scripts/*.sh
...
```

**Temps :** ~10-15 minutes  
**Étapes :** 20+  
**Risque d'erreur :** Élevé

---

### ✅ Après (automatisé)

```bash
# Lancer le script
./deployment/scripts/create-deployment-package.sh

# Choisir l'option 2
# Répondre aux questions
# Confirmer

# ✅ Tout est fait automatiquement !
```

**Temps :** ~2 minutes  
**Étapes :** 5  
**Risque d'erreur :** Faible

---

## ✅ Avantages

**Interface interactive :**
- ✅ Menu clair et intuitif
- ✅ Confirmations avant chaque action
- ✅ Messages colorés et structurés

**Transfert SSH :**
- ✅ Connexion testée avant transfert
- ✅ Création automatique des répertoires
- ✅ Décompression automatique
- ✅ Permissions configurées

**Flexibilité :**
- ✅ Mode local uniquement (option 1)
- ✅ Mode complet avec transfert (option 2)
- ✅ Configuration personnalisable (option 3)

**Sécurité :**
- ✅ Support clé SSH (recommandé)
- ✅ Support mot de passe (avec sshpass)
- ✅ Test de connexion avant transfert
- ✅ Confirmation avant écrasement

---

## 📝 Notes

**Important :**
- Le package ne contient **pas** le code source
- Le code est dans l'image Docker sur Docker Hub
- Le VPS pull simplement l'image et la démarre

**Fichiers sensibles :**
- Les `.env.*` doivent être édités sur le VPS après installation
- Ne pas commiter les `.env.*` avec des secrets réels

---

## 🔒 Fichiers à commiter dans Git

### ❌ NE JAMAIS COMMITER

**Fichiers en clair (secrets exposés) :**
```bash
.env                    # ❌ Jamais !
.env.dev                # ❌ Jamais !
.env.staging            # ❌ Jamais !
.env.prod               # ❌ Jamais !
.env.key                # ❌ TRÈS IMPORTANT - Clé de chiffrement !
```

**Pourquoi ?**
- Contiennent des secrets en clair (mots de passe, tokens, clés API)
- Risque d'exposition si le dépôt devient public
- La clé `.env.key` permet de déchiffrer tous les secrets

### ✅ TOUJOURS COMMITER

**Fichiers chiffrés (sécurisés) :**
```bash
.env.dev.encrypted      # ✅ OUI - Chiffré avec Fernet
.env.staging.encrypted  # ✅ OUI - Chiffré
.env.prod.encrypted     # ✅ OUI - Chiffré
```

**Pourquoi ?**
- Les valeurs sont **chiffrées** et inutilisables sans `.env.key`
- Nécessaires pour le déploiement sur le VPS
- Le VPS peut les récupérer via `git pull`
- Partageables en toute sécurité dans Git

**Configuration .gitignore :**

Le `.gitignore` a été configuré pour :
```gitignore
# ❌ Ignorer les fichiers en clair
.env
.env.dev
.env.staging
.env.prod
.env.key

# ✅ Inclure les fichiers chiffrés
!.env.*.encrypted
!.env.dev.encrypted
!.env.staging.encrypted
!.env.prod.encrypted
```

**Vérification :**
```bash
# Vérifier ce qui sera commité
git status

# Résultat attendu :
# modified:   .env.dev.encrypted  ← ✅ Tracké (chiffré)
# .env.dev n'apparaît pas         ← ✅ Ignoré (en clair)
# .env.key n'apparaît pas         ← ✅ Ignoré (clé)
```

**Workflow recommandé :**
```bash
# 1. Éditer le fichier en clair (local)
nano .env.dev

# 2. Chiffrer
python3 deployment/scripts/env-encrypt.py encrypt .env.dev

# 3. Commiter UNIQUEMENT le fichier chiffré
git add .env.dev.encrypted
git commit -m "chore: Update dev environment variables"
git push

# 4. Sur le VPS
git pull  # Récupère .env.dev.encrypted
python3 scripts/env-encrypt.py decrypt .env.dev.encrypted
```

**Documentation complète :** `deployment/GIT_ENV_FILES.md`

---

## 🆘 Troubleshooting

### Le script ne démarre pas

```bash
# Rendre exécutable
chmod +x deployment/scripts/create-deployment-package.sh
```

### Connexion SSH échoue

```bash
# Vérifier la connexion manuellement
ssh -p 22 -v cicbi@51.79.8.116

# Copier la clé si nécessaire
ssh-copy-id -p 22 cicbi@51.79.8.116
```

### sshpass non trouvé

```bash
# Installer sshpass
brew install hudochenkov/sshpass/sshpass

# Ou utiliser l'option "Clé SSH" (recommandé)
```

---

**Date :** 18 décembre 2025  
**Version :** 2.0.0 (Interactive + SSH)  
**Status :** ✅ PRODUCTION READY

🎯 **Le script est maintenant complètement interactif avec transfert SSH automatique !**

