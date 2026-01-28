# 🚀 Workflow de Déploiement CICBI API

Ce document explique les différents workflows disponibles pour déployer votre application sur le serveur.

---

## 📋 Workflow Recommandé : Déploiement Complet Automatisé

**Script** : `deployment/scripts/create-deployment-package.sh`

### ✅ Ce workflow fait TOUT automatiquement :

1. ✅ Crée le package de déploiement
2. ✅ Copie vos fichiers `.env` réels depuis la racine du projet
3. ✅ Transfère le package sur le serveur via SSH
4. ✅ Extrait et installe le package
5. ✅ **Crée automatiquement l'environnement virtuel Python**
6. ✅ **Chiffre automatiquement** tous les fichiers `.env`
7. ✅ **Supprime les versions non chiffrées** (sécurité)
8. ✅ **Crée le marker `.server-marker`** pour la détection automatique
9. ✅ **Configure le profil registry** par défaut
10. ✅ **Préserve les fichiers sensibles** lors des mises à jour (.env.key, .venv, logs)

### 📝 Utilisation :

```bash
# Sur votre machine locale
cd /home/jeeff/PycharmProjects/cicbi-api-backend
./deployment/scripts/create-deployment-package.sh

# Menu interactif :
# 1) Créer le package uniquement
# 2) Créer et copier vers le serveur (SSH)  ← RECOMMANDÉ
# 3) Configuration avancée
```

### 🎯 Résultat :

Après exécution, sur le serveur :
- ✅ Tous les fichiers sont en place
- ✅ Les `.env` sont chiffrés (`.env.dev.encrypted`, etc.)
- ✅ Le marker `.server-marker` est créé
- ✅ Le profil registry est configuré
- ✅ Le venv Python est prêt
- ✅ Vous pouvez déployer immédiatement :

```bash
# Sur le serveur
cd /srv/home/cicbi-api-backend
./scripts/deploy-registry.sh deploy dev
```

---

## 🔧 Workflow Alternatif : Mise à Jour Manuelle des .env

**Script** : `deployment/scripts/setup-server-env-manual.sh`

### 📌 Utilisez ce workflow UNIQUEMENT si :

- Vous voulez mettre à jour **seulement les fichiers .env** (sans redéployer tout le package)
- Vous avez déjà un déploiement existant sur le serveur
- Vous voulez chiffrer/mettre à jour les secrets sans toucher au code

### 📝 Utilisation :

```bash
# Sur votre machine locale
cd /home/jeeff/PycharmProjects/cicbi-api-backend/deployment/scripts
./setup-server-env-manual.sh cicbi@cicsrvbiaptcat
```

### 🎯 Ce que fait ce script :

1. Génère/vérifie la clé de chiffrement
2. Chiffre les fichiers `.env` localement
3. Transfère UNIQUEMENT :
   - `.env.key`
   - `.env.*.encrypted`
4. Crée le marker `.server-marker`
5. Sécurise les permissions

⚠️ **Important** : Ce script ne transfère PAS les scripts de déploiement ni les fichiers docker-compose.

---

## 🆚 Comparaison des Workflows

| Fonctionnalité | `create-deployment-package.sh` | `setup-server-env-manual.sh` |
|----------------|--------------------------------|------------------------------|
| **Package complet** | ✅ Scripts + Docker Compose + .env | ❌ Seulement .env |
| **Transfert SSH** | ✅ Automatique | ✅ Automatique |
| **Chiffrement .env** | ✅ Sur le serveur (auto) | ✅ Local puis transfert |
| **Création venv** | ✅ Sur le serveur | ❌ Non |
| **Config registry** | ✅ Profils créés | ❌ Non |
| **Marker serveur** | ✅ Créé automatiquement | ✅ Créé |
| **Préservation fichiers** | ✅ .env.key, .venv, logs | ⚠️ Non applicable |
| **Usage recommandé** | 🌟 Déploiement complet | 🔧 Mise à jour .env uniquement |

---

## 📦 Cas d'Usage par Workflow

### Utilisez `create-deployment-package.sh` pour :

- ✅ **Premier déploiement** sur le serveur
- ✅ **Mise à jour complète** (nouveau code, nouveaux scripts)
- ✅ **Réinstallation** après nettoyage du serveur
- ✅ **Migration** vers un nouveau serveur
- ✅ **Mise à jour des .env ET du code**

**Exemple** :
```bash
# Déploiement initial ou mise à jour complète
./deployment/scripts/create-deployment-package.sh
# Choisir option 2 : Créer et copier vers le serveur
```

---

### Utilisez `setup-server-env-manual.sh` pour :

- 🔧 **Mise à jour rapide** d'un secret dans .env
- 🔧 **Ajout** d'une nouvelle variable d'environnement
- 🔧 **Rotation des clés** (changer les secrets)
- 🔧 **Correction** d'une configuration .env

**Exemple** :
```bash
# Vous avez modifié DATABASE_PASSWORD dans .env.prod
nano .env.prod  # Sur votre machine locale
./deployment/scripts/setup-server-env-manual.sh cicbi@serveur
# Les .env sont re-chiffrés et transférés

# Sur le serveur, redémarrez l'application
ssh cicbi@serveur
cd /srv/home/cicbi-api-backend
./scripts/deploy-registry.sh restart prod
```

---

## 🔄 Workflow Complet Recommandé

### 1️⃣ Premier Déploiement

```bash
# Sur votre machine locale
cd /home/jeeff/PycharmProjects/cicbi-api-backend

# 1. Vérifier que vos .env sont à jour
ls -la .env.dev .env.staging .env.prod

# 2. Créer et déployer le package
./deployment/scripts/create-deployment-package.sh
# → Choisir option 2 : Créer et copier vers le serveur

# 3. Sur le serveur, déployer
ssh cicbi@cicsrvbiaptcat
cd /srv/home/cicbi-api-backend
./scripts/deploy-registry.sh deploy dev
```

### 2️⃣ Mise à Jour du Code (Build + Push + Deploy)

```bash
# Sur votre machine locale
cd /home/jeeff/PycharmProjects/cicbi-api-backend

# 1. Build et push vers Docker Hub
./deployment/scripts/registry.sh build-push dev

# 2. Sur le serveur, déployer la nouvelle image
ssh cicbi@cicsrvbiaptcat
cd /srv/home/cicbi-api-backend
./scripts/deploy-registry.sh deploy dev dev-latest
```

### 3️⃣ Mise à Jour des .env Uniquement

```bash
# Sur votre machine locale
cd /home/jeeff/PycharmProjects/cicbi-api-backend

# 1. Modifier vos .env localement
nano .env.dev

# 2. Option A : Mise à jour rapide (recommandé)
./deployment/scripts/setup-server-env-manual.sh cicbi@cicsrvbiaptcat

# OU Option B : Redéploiement complet
./deployment/scripts/create-deployment-package.sh
# → Choisir option 2

# 3. Sur le serveur, redémarrer
ssh cicbi@cicsrvbiaptcat
cd /srv/home/cicbi-api-backend
./scripts/deploy-registry.sh restart dev
```

### 4️⃣ Mise à Jour Complète (Code + .env + Scripts)

```bash
# Sur votre machine locale
cd /home/jeeff/PycharmProjects/cicbi-api-backend

# 1. Build et push la nouvelle image
./deployment/scripts/registry.sh build-push dev

# 2. Redéployer le package complet
./deployment/scripts/create-deployment-package.sh
# → Choisir option 2 : Créer et copier vers le serveur
```

---

## 🔐 Sécurité et Bonnes Pratiques

### ✅ À FAIRE

1. **Toujours** utiliser les fichiers chiffrés sur le serveur
2. **Sauvegarder** `.env.key` dans un gestionnaire de secrets sécurisé
3. **Vérifier** les permissions : `chmod 600 .env.key`
4. **Tester** le déchiffrement avant un déploiement critique
5. **Séparer** les secrets par environnement (dev ≠ staging ≠ prod)

### ❌ À ÉVITER

1. ❌ **Jamais** commiter `.env` ou `.env.key` dans git
2. ❌ **Jamais** transférer de `.env` non chiffré sur le serveur
3. ❌ **Jamais** partager `.env.key` par email/chat
4. ❌ **Jamais** utiliser les mêmes secrets entre dev et prod
5. ❌ **Jamais** laisser des `.env` non chiffrés sur le serveur

---

## 🆘 Dépannage

### Le déploiement échoue : "env file not found"

```bash
# Sur le serveur, vérifier les fichiers
ssh cicbi@cicsrvbiaptcat
cd /srv/home/cicbi-api-backend
ls -la .env.* deployment/.env.*.encrypted

# Si les .env.*.encrypted manquent :
# → Utiliser create-deployment-package.sh (option 2)
```

### Les .env ne sont pas chiffrés sur le serveur

```bash
# Sur le serveur
ssh cicbi@cicsrvbiaptcat
cd /srv/home/cicbi-api-backend

# Re-chiffrer manuellement
./scripts/auto-encrypt-envs.sh --auto-confirm
```

### Le marker serveur n'existe pas

```bash
# Sur le serveur
ssh cicbi@cicsrvbiaptcat
cd /srv/home/cicbi-api-backend
touch .server-marker
```

---

## 📚 Documentation Complémentaire

- **Configuration Serveur** : `deployment/SERVEUR-SETUP.md`
- **Chiffrement .env** : Voir `deployment/scripts/env-encrypt.py --help`
- **Déploiement Registry** : Voir `deployment/scripts/deploy-registry.sh help`

---

**Dernière mise à jour** : 18 décembre 2025
