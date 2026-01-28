# 🔧 Guide - Configuration YAML pour les variables sensibles

## ✅ Amélioration appliquée !

Au lieu de hardcoder 100+ variables sensibles dans le code Python, la configuration est maintenant externalisée dans un fichier YAML facilement éditable.

---

## 📁 Fichiers créés

### 1. Configuration YAML

**Fichier :** `deployment/scripts/sensitive-vars.yml`

**Contenu :**
```yaml
# Patterns de variables sensibles
sensitive_patterns:
  - PASSWORD
  - SECRET
  - KEY
  - TOKEN
  - PRIVATE
  - DATABASE_PASSWORD
  - JWT_SECRET_KEY
  - GITHUB_TOKEN
  # ... et bien d'autres

# Variables à exclure (même si elles contiennent un mot-clé)
exclude_patterns:
  - PUBLIC_KEY
  - JWT_PUBLIC_KEY
  
# Valeurs à ignorer
ignore_values:
  - changeme
  - CHANGEZ_CETTE_CLE
  
# Options
options:
  case_sensitive: false
  partial_match: true
  encrypted_marker_prefix: "ENC["
  encrypted_marker_suffix: "]"
```

### 2. Script Python mis à jour

**Fichier :** `deployment/scripts/env-encrypt.py`

**Nouveautés :**
- ✅ Charge la configuration depuis YAML
- ✅ Supporte 100+ patterns sans toucher au code
- ✅ Configuration par défaut si YAML absent
- ✅ Options configurables (marqueurs, permissions, etc.)

---

## 🚀 Utilisation

### Utilisation normale (automatique)

```bash
# Le script charge automatiquement sensitive-vars.yml
python3 deployment/scripts/env-encrypt.py encrypt .env.dev

# Résultat :
# 📋 Configuration chargée depuis deployment/scripts/sensitive-vars.yml
# 🔒 Chiffrement de .env.dev → .env.dev.encrypted
# 🔐 DATABASE_PASSWORD: chiffré
# 🔐 JWT_SECRET_KEY: chiffré
# ✅ 4 variable(s) chiffrée(s)
```

### Utilisation avec configuration personnalisée

```bash
# Utiliser votre propre fichier de config
python3 deployment/scripts/env-encrypt.py encrypt .env.dev --config my-config.yml
```

---

## 📝 Personnalisation de la configuration

### Ajouter de nouvelles variables sensibles

**Méthode 1 : Éditer sensitive-vars.yml**

```bash
# Ouvrir le fichier
nano deployment/scripts/sensitive-vars.yml

# Ajouter dans sensitive_patterns:
sensitive_patterns:
  - PASSWORD
  - SECRET
  # ... existant ...
  - STRIPE_API_KEY       # Nouvelle
  - PAYPAL_CLIENT_SECRET # Nouvelle
  - TWILIO_AUTH_TOKEN    # Nouvelle
```

**Méthode 2 : Créer un fichier personnalisé**

```yaml
# my-sensitive-vars.yml
sensitive_patterns:
  - MY_CUSTOM_SECRET
  - COMPANY_API_KEY
  - INTERNAL_TOKEN
```

```bash
# Utiliser votre config
python3 deployment/scripts/env-encrypt.py encrypt .env.dev \
  --config my-sensitive-vars.yml
```

---

## 🔍 Exemples de détection

### Variables qui SERONT chiffrées

Selon `sensitive-vars.yml` :

```bash
DATABASE_PASSWORD=secret123          → Contient PASSWORD ✅
JWT_SECRET_KEY=mykey                 → Contient SECRET et KEY ✅
GITHUB_TOKEN=ghp_xxx                 → Contient TOKEN ✅
MY_API_KEY=abc123                    → Contient KEY ✅
SMTP_PASSWORD=pass                   → Contient PASSWORD ✅
STRIPE_SECRET_KEY=sk_test_xxx        → Contient SECRET et KEY ✅
AWS_ACCESS_KEY_ID=AKIA...            → Dans la liste ✅
REDIS_PASSWORD=redis123              → Contient PASSWORD ✅
```

### Variables qui NE seront PAS chiffrées

```bash
DATABASE_HOST=localhost              → Pas de pattern sensible ❌
APP_ENV=production                   → Pas de pattern sensible ❌
PUBLIC_KEY=ssh-rsa...                → Dans exclude_patterns ❌
DATABASE_PASSWORD=changeme           → Valeur dans ignore_values ❌
DEBUG=true                           → Pas de pattern sensible ❌
PASSWORD_MIN_LENGTH=8                → Dans exclude_patterns ❌
```

---

## ⚙️ Options configurables

### Dans `sensitive-vars.yml` > `options:`

```yaml
options:
  # Sensibilité à la casse
  case_sensitive: false  # PASSWORD = password = Password
  
  # Match exact ou partiel
  exact_match: false     # Si true, DATABASE_PASSWORD ne match que si == PASSWORD
  partial_match: true    # Si true, DATABASE_PASSWORD match si contient PASSWORD
  
  # Avertissements
  warn_on_sensitive_in_clear: true  # Afficher warning si valeur ignorée
  
  # Format de chiffrement
  encrypted_marker_prefix: "ENC["   # Début du marqueur
  encrypted_marker_suffix: "]"      # Fin du marqueur
  
  # Permissions du fichier
  output_file_permissions: 0o600    # chmod 600
```

---

## 📊 Avantages de l'approche YAML

| Aspect | Avant (hardcodé) | Après (YAML) |
|--------|------------------|--------------|
| **Ajout de variables** | Modifier le code Python | Éditer le YAML |
| **Maintenabilité** | Difficile avec 100+ vars | Facile |
| **Lisibilité** | Code complexe | Configuration claire |
| **Partage** | Difficile | Simple (1 fichier) |
| **Versioning** | Git du code | Git de la config |
| **Flexibilité** | Limitée | Très flexible |

---

## 🎯 Cas d'usage avancés

### Cas 1 : Configuration par environnement

```bash
# Development
python3 env-encrypt.py encrypt .env.dev \
  --config sensitive-vars-dev.yml

# Production (plus strict)
python3 env-encrypt.py encrypt .env.prod \
  --config sensitive-vars-prod.yml
```

### Cas 2 : Configuration par projet

```bash
# Projet A : Cloud AWS
sensitive-patterns:
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - AWS_SESSION_TOKEN

# Projet B : Cloud Azure
sensitive-patterns:
  - AZURE_CLIENT_SECRET
  - AZURE_TENANT_ID
  - AZURE_SUBSCRIPTION_ID
```

### Cas 3 : Patterns regex (future extension)

```yaml
# Futur : support des regex
sensitive_patterns:
  - pattern: "^AWS_.*"
    type: regex
  - pattern: ".*_PASSWORD$"
    type: regex
```

---

## 🔧 Maintenance

### Ajouter un nouveau provider (ex: Stripe)

```bash
# 1. Éditer sensitive-vars.yml
nano deployment/scripts/sensitive-vars.yml

# 2. Ajouter dans sensitive_patterns:
  - STRIPE_SECRET_KEY
  - STRIPE_API_KEY
  - STRIPE_WEBHOOK_SECRET

# 3. Tester
python3 deployment/scripts/env-encrypt.py encrypt .env.dev

# 4. Vérifier
grep STRIPE .env.dev.encrypted
# Doit afficher : STRIPE_SECRET_KEY=ENC[...]
```

### Exclure une variable

```bash
# Éditer sensitive-vars.yml
nano deployment/scripts/sensitive-vars.yml

# Ajouter dans exclude_patterns:
  - MY_PUBLIC_API_KEY  # Même si contient KEY, ne pas chiffrer

# Vérifier
python3 deployment/scripts/env-encrypt.py encrypt .env.dev
# MY_PUBLIC_API_KEY ne sera pas chiffré
```

---

## 📝 Template de configuration

### Configuration minimale

```yaml
# sensitive-vars-minimal.yml
sensitive_patterns:
  - PASSWORD
  - SECRET
  - TOKEN

options:
  case_sensitive: false
```

### Configuration complète

```yaml
# sensitive-vars-complete.yml
sensitive_patterns:
  # Génériques
  - PASSWORD
  - SECRET
  - KEY
  - TOKEN
  - PRIVATE
  - CREDENTIAL
  
  # Cloud providers
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - AZURE_CLIENT_SECRET
  - GOOGLE_CREDENTIALS
  
  # Databases
  - DATABASE_PASSWORD
  - POSTGRES_PASSWORD
  - MYSQL_PASSWORD
  - REDIS_PASSWORD
  
  # APIs
  - API_KEY
  - API_SECRET
  - STRIPE_SECRET_KEY
  - PAYPAL_SECRET
  
exclude_patterns:
  - PUBLIC_KEY
  - EXAMPLE_KEY
  - TEST_TOKEN

ignore_values:
  - changeme
  - xxx
  - ""

options:
  case_sensitive: false
  partial_match: true
  encrypted_marker_prefix: "ENC["
  encrypted_marker_suffix: "]"
  output_file_permissions: 0o600
```

---

## ✅ Résumé

**Problème initial :** 100+ variables hardcodées dans le code Python

**Solution :** Configuration externalisée dans `sensitive-vars.yml`

**Avantages :**
- ✅ Facile à maintenir
- ✅ Pas besoin de modifier le code
- ✅ Supporte des centaines de patterns
- ✅ Configuration par projet/environnement
- ✅ Versionnable avec Git

**Fichiers :**
- `deployment/scripts/sensitive-vars.yml` : Configuration
- `deployment/scripts/env-encrypt.py` : Script (mis à jour)
- `app/requirements.txt` : PyYAML ajouté

---

## 🚀 Prochaines étapes

1. **Tester avec vos fichiers .env**
   ```bash
   python3 deployment/scripts/env-encrypt.py encrypt .env.dev
   ```

2. **Personnaliser sensitive-vars.yml**
   - Ajouter vos variables spécifiques
   - Ajuster les exclude_patterns
   - Modifier les options selon vos besoins

3. **Commiter la configuration**
   ```bash
   git add deployment/scripts/sensitive-vars.yml
   git add deployment/scripts/env-encrypt.py
   git add app/requirements.txt
   git commit -m "feat: Configuration YAML pour variables sensibles"
   ```

---

**Date :** 17 décembre 2025  
**Amélioration :** Configuration externalisée avec YAML  
**Maintenabilité :** ✅ Excellente

🎯 **Vous pouvez maintenant gérer des centaines de variables sensibles facilement !**

