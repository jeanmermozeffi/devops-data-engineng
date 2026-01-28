# 🔐 CHIFFREMENT DES SECRETS DANS LES FICHIERS .ENV

## 🎯 Problème

Les fichiers `.env` contiennent des secrets en **clair** :

```bash
# .env.dev
DATABASE_PASSWORD=super-secret-123
JWT_SECRET_KEY=mon-secret-jwt-key
GITHUB_TOKEN=ghp_xxxxxxxxxxx
```

**Risques :**
- 🚨 Secrets visibles en clair sur le disque
- 🚨 Compromission si fichier volé
- 🚨 Difficile de partager (email, chat, etc.)

---

## ✅ Solution : Chiffrement des secrets

### Méthode 1 : Script de chiffrement Python (RECOMMANDÉE)

J'ai créé un outil complet de chiffrement pour vos fichiers `.env`.

#### Installation

```bash
cd /Users/jeanmermozeffi/PycharmProjects/cicbi-api-backend

# La dépendance cryptography est déjà dans requirements.txt
pip install cryptography  # Si pas déjà installé
```

#### Utilisation

```bash
# 1. Générer une clé de chiffrement (une seule fois)
python deployment/scripts/env-encrypt.py generate-key

# Résultat :
# ✅ Clé générée: .env.key
# 🔑 Clé: fXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=
# ⚠️  Sauvegardez cette clé en lieu sûr !

# 2. Chiffrer un fichier .env
python deployment/scripts/env-encrypt.py encrypt .env.dev

# Résultat : .env.dev.encrypted
```

#### Exemple de fichier chiffré

**Avant (.env.dev) :**
```bash
APP_ENV=dev
DATABASE_HOST=localhost
DATABASE_PASSWORD=super-secret-123
JWT_SECRET_KEY=mon-secret-jwt
GITHUB_TOKEN=ghp_xxxxxxxxxxx
```

**Après (.env.dev.encrypted) :**
```bash
APP_ENV=dev
DATABASE_HOST=localhost
DATABASE_PASSWORD=ENC[gAAAAABnYXZ1ZXM...XYZ123==]
JWT_SECRET_KEY=ENC[gAAAAABnYXZ1ZXM...ABC456==]
GITHUB_TOKEN=ENC[gAAAAABnYXZ1ZXM...DEF789==]
```

**Avantages :**
- ✅ Variables sensibles chiffrées (PASSWORD, SECRET, KEY, TOKEN)
- ✅ Variables normales en clair (APP_ENV, DATABASE_HOST)
- ✅ Format compatible avec docker-compose

---

## 🔄 Workflow complet

### Étape 1 : Chiffrer vos fichiers .env

```bash
cd /Users/jeanmermozeffi/PycharmProjects/cicbi-api-backend

# Générer la clé (une fois)
python deployment/scripts/env-encrypt.py generate-key

# Chiffrer vos fichiers
python deployment/scripts/env-encrypt.py encrypt .env.dev
python deployment/scripts/env-encrypt.py encrypt .env.staging
python deployment/scripts/env-encrypt.py encrypt .env.prod

# Résultat :
# .env.dev.encrypted
# .env.staging.encrypted
# .env.prod.encrypted
```

### Étape 2 : Sauvegarder la clé en sécurité

```bash
# Copier la clé dans un gestionnaire de mots de passe
cat .env.key

# OU l'envoyer de manière sécurisée (ne PAS commiter dans git)
```

### Étape 3 : Mettre à jour .gitignore

```bash
# .gitignore
.env
.env.dev
.env.staging
.env.prod
.env.*.local
.env.key  # ⚠️ IMPORTANT : Ne jamais commiter la clé

# Optionnel : commiter les fichiers chiffrés
# .env.*.encrypted peuvent être commités (ils sont chiffrés)
```

### Étape 4 : Sur le VPS, déchiffrer

```bash
# Sur le VPS
cd /srv/cicbi-api-backend

# 1. Copier la clé (de manière sécurisée)
echo "fXXXXXXXXXXXXXXXXXXXXXXXXX=" > .env.key
chmod 600 .env.key

# 2. Déchiffrer les fichiers
python scripts/env-encrypt.py decrypt .env.dev.encrypted
python scripts/env-encrypt.py decrypt .env.staging.encrypted
python scripts/env-encrypt.py decrypt .env.prod.encrypted

# Résultat :
# .env.dev (déchiffré)
# .env.staging (déchiffré)
# .env.prod (déchiffré)

# 3. Démarrer les conteneurs
./scripts/deploy-registry.sh deploy dev
```

---

## 🔐 Méthode 2 : Déchiffrement automatique au runtime

### Option A : Modifier le code de l'application

```python
# app/src/main.py
from utils.env_loader import load_encrypted_env

# Au lieu de :
# from dotenv import load_dotenv
# load_dotenv()

# Utiliser :
load_encrypted_env('.env.dev')

# Les variables sont automatiquement déchiffrées au démarrage !
```

### Option B : Script de démarrage

```bash
#!/bin/bash
# start-with-decrypt.sh

# Déchiffrer au démarrage
python scripts/env-encrypt.py decrypt .env.dev.encrypted -o .env.dev

# Démarrer l'application
uvicorn main:app --host 0.0.0.0 --port 80

# Nettoyer le fichier déchiffré à l'arrêt
trap "rm -f .env.dev" EXIT
```

---

## 📊 Comparaison des méthodes

| Méthode | Sécurité | Facilité | Performance |
|---------|----------|----------|-------------|
| **Fichiers .env en clair** | ❌ Faible | ✅ Simple | ✅ Rapide |
| **Fichiers .env chiffrés** | ✅ Bonne | ✅ Simple | ✅ Rapide |
| **Déchiffrement au runtime** | ✅ Excellente | ⚠️ Moyen | ✅ Rapide |
| **Vault/AWS Secrets** | ✅ Excellente | ❌ Complexe | ⚠️ Moyen |

---

## 🎯 Commandes utiles

### Chiffrer une valeur spécifique

```bash
# Chiffrer un nouveau mot de passe
python deployment/scripts/env-encrypt.py encrypt-value "nouveau-password"

# Résultat :
# 🔒 Valeur chiffrée:
#    ENC[gAAAAABnYXZ1ZXM...XYZ123==]

# Copier dans .env.dev.encrypted :
DATABASE_PASSWORD=ENC[gAAAAABnYXZ1ZXM...XYZ123==]
```

### Déchiffrer une valeur spécifique

```bash
# Voir ce qu'une valeur chiffrée contient
python deployment/scripts/env-encrypt.py decrypt-value "ENC[gAAAAABnYXZ1ZXM...XYZ123==]"

# Résultat :
# 🔓 Valeur déchiffrée:
#    nouveau-password
```

### Rechiffrer après modification

```bash
# 1. Déchiffrer
python deployment/scripts/env-encrypt.py decrypt .env.dev.encrypted

# 2. Modifier .env.dev
nano .env.dev

# 3. Rechiffrer
python deployment/scripts/env-encrypt.py encrypt .env.dev

# 4. Supprimer le fichier en clair
rm .env.dev
```

---

## 🔒 Gestion de la clé de chiffrement

### Génération de la clé

```bash
# Automatique (recommandé)
python deployment/scripts/env-encrypt.py generate-key

# Manuel (si besoin d'une clé spécifique)
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

### Sauvegarde de la clé

**Option 1 : Gestionnaire de mots de passe**
- 1Password
- LastPass
- Bitwarden
- KeePass

**Option 2 : Variable d'environnement système**
```bash
# Sur le VPS
export ENCRYPTION_KEY="fXXXXXXXXXXXXXXXXXXXXXXXXX="
echo 'export ENCRYPTION_KEY="fXXX..."' >> ~/.bashrc
```

**Option 3 : Secrets Manager cloud**
- AWS Secrets Manager
- Google Secret Manager
- Azure Key Vault

### Rotation de la clé

```bash
# 1. Générer une nouvelle clé
python deployment/scripts/env-encrypt.py generate-key -k .env.key.new

# 2. Déchiffrer avec l'ancienne clé
python deployment/scripts/env-encrypt.py decrypt .env.dev.encrypted -k .env.key

# 3. Rechiffrer avec la nouvelle clé
python deployment/scripts/env-encrypt.py encrypt .env.dev -k .env.key.new

# 4. Remplacer la clé
mv .env.key .env.key.old
mv .env.key.new .env.key
```

---

## 🚨 Bonnes pratiques de sécurité

### ✅ À FAIRE

1. **Générer une clé unique par environnement**
   ```bash
   .env.dev.key    # Clé pour dev
   .env.staging.key # Clé pour staging
   .env.prod.key    # Clé pour prod
   ```

2. **Ne JAMAIS commiter la clé dans git**
   ```bash
   # .gitignore
   .env.key
   .env.*.key
   ```

3. **Protéger les fichiers de clé**
   ```bash
   chmod 600 .env.key
   ```

4. **Sauvegarder la clé en lieu sûr**
   - Gestionnaire de mots de passe
   - Vault sécurisé
   - Backup chiffré

5. **Utiliser des clés différentes par environnement**
   - Si une clé est compromise, seul un environnement est affecté

### ❌ À NE PAS FAIRE

1. ❌ Commiter `.env.key` dans git
2. ❌ Partager la clé par email/chat en clair
3. ❌ Utiliser la même clé partout
4. ❌ Hardcoder la clé dans le code
5. ❌ Oublier de sauvegarder la clé

---

## 📝 Structure des fichiers recommandée

### Sur votre Mac (développement)

```
/Users/jeanmermozeffi/PycharmProjects/cicbi-api-backend/
├── .env.dev                    # ❌ Git ignored (clair, local uniquement)
├── .env.staging                # ❌ Git ignored (clair, local uniquement)
├── .env.prod                   # ❌ Git ignored (clair, local uniquement)
├── .env.dev.encrypted          # ✅ Peut être commité (chiffré)
├── .env.staging.encrypted      # ✅ Peut être commité (chiffré)
├── .env.prod.encrypted         # ✅ Peut être commité (chiffré)
├── .env.key                    # ❌ Git ignored (JAMAIS commiter)
├── .env.example                # ✅ Commité (template sans secrets)
└── deployment/scripts/
    └── env-encrypt.py          # ✅ Commité (outil)
```

### Sur le VPS

```
/srv/cicbi-api-backend/
├── .env.dev                    # Déchiffré au déploiement
├── .env.staging                # Déchiffré au déploiement
├── .env.prod                   # Déchiffré au déploiement
├── .env.key                    # Copié de manière sécurisée
└── scripts/
    └── env-encrypt.py
```

---

## 🎯 Workflow recommandé

### Développement (Mac)

```bash
# 1. Travailler avec fichiers en clair localement
nano .env.dev

# 2. Avant commit, chiffrer
python deployment/scripts/env-encrypt.py encrypt .env.dev

# 3. Commit du fichier chiffré
git add .env.dev.encrypted
git commit -m "Update secrets"
git push

# 4. Garder .env.dev local pour dev
# (ne PAS commiter)
```

### Déploiement (VPS)

```bash
# 1. Pull les changements
git pull

# 2. Déchiffrer avec la clé sécurisée
python scripts/env-encrypt.py decrypt .env.dev.encrypted

# 3. Redémarrer l'application
./scripts/deploy-registry.sh deploy dev
```

---

## 🔐 Méthode 3 : Alternatives avancées

### Option A : Docker Secrets (Swarm/Kubernetes)

```yaml
# docker-compose.yml
services:
  api:
    secrets:
      - db_password
      - jwt_secret

secrets:
  db_password:
    file: ./secrets/db_password.txt
  jwt_secret:
    file: ./secrets/jwt_secret.txt
```

### Option B : HashiCorp Vault

```python
import hvac

client = hvac.Client(url='http://vault:8200', token='xxx')
secret = client.secrets.kv.v2.read_secret_version(path='app/database')
password = secret['data']['data']['password']
```

### Option C : AWS Secrets Manager

```python
import boto3

client = boto3.client('secretsmanager')
response = client.get_secret_value(SecretId='prod/database/password')
password = response['SecretString']
```

---

## ✅ Résumé

### Solution créée pour vous

1. ✅ **Script de chiffrement** : `deployment/scripts/env-encrypt.py`
2. ✅ **Loader automatique** : `app/src/utils/env_loader.py`
3. ✅ **Cryptography** déjà dans requirements.txt

### Utilisation simple

```bash
# Chiffrer
python deployment/scripts/env-encrypt.py encrypt .env.dev

# Déchiffrer
python deployment/scripts/env-encrypt.py decrypt .env.dev.encrypted

# Chiffrer une valeur
python deployment/scripts/env-encrypt.py encrypt-value "mon-secret"
```

### Avantages

- ✅ Secrets chiffrés au repos
- ✅ Partage sécurisé possible (fichiers chiffrés)
- ✅ Compatible avec votre workflow actuel
- ✅ Pas de changement de code nécessaire
- ✅ Rotation de secrets facile

---

**Date :** 17 décembre 2025
**Conclusion :** Vos secrets peuvent maintenant être chiffrés et stockés en toute sécurité ! 🔐

🎯 **Prochaines étapes :** Testez le script de chiffrement sur un fichier .env de test !

