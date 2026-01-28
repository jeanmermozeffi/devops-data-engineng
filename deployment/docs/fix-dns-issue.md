# Fix Docker DNS Resolution Issue

## Problème
Erreur lors du build Docker : `Temporary failure resolving 'deb.debian.org'`

```
Err:1 http://deb.debian.org/debian trixie InRelease
  Temporary failure resolving 'deb.debian.org'
```

## Solution (LA SEULE QUI FONCTIONNE)

### Configurer les DNS de Docker sur le serveur

**IMPORTANT:** C'est la SEULE solution qui fonctionne. Les flags `--dns` ne sont pas supportés par `docker build`.

#### Méthode Automatique (Recommandée)

Utilisez le script fourni :

```bash
# 1. Copier le script sur le serveur
scp deployment/scripts/fix-dns.sh votre-serveur:/tmp/

# 2. Se connecter au serveur
ssh votre-serveur

# 3. Diagnostiquer
sudo /tmp/fix-dns.sh check

# 4. Corriger automatiquement
sudo /tmp/fix-dns.sh fix

# 5. Tester
sudo /tmp/fix-dns.sh test
```

#### Méthode Manuelle

Sur le serveur, éditez `/etc/docker/daemon.json` :

```bash
sudo nano /etc/docker/daemon.json
```

Ajoutez ou modifiez pour inclure :

```json
{
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1"]
}
```

**Si le fichier contient déjà d'autres configurations**, ajoutez simplement la ligne `"dns"` :

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1"]
}
```

Redémarrez Docker :

```bash
sudo systemctl restart docker
```

Vérifiez que Docker a bien redémarré :

```bash
sudo systemctl status docker
docker ps
```

## Diagnostic

### 1. Vérifier si le serveur peut résoudre les DNS

```bash
# Test de résolution depuis le système
nslookup deb.debian.org
ping -c 2 deb.debian.org

# Vérifier les DNS configurés sur le système
cat /etc/resolv.conf
```

### 2. Vérifier la configuration Docker

```bash
# Voir la config actuelle
cat /etc/docker/daemon.json

# Voir les infos Docker
docker info | grep -A 5 DNS
```

### 3. Tester depuis un conteneur Docker

```bash
# Test simple
docker run --rm debian:trixie-slim cat /etc/resolv.conf

# Test apt-get update
docker run --rm debian:trixie-slim apt-get update
```

Si le dernier test fonctionne, le problème est résolu.

## Pourquoi les autres solutions NE FONCTIONNENT PAS

- ❌ `docker build --dns=8.8.8.8` → **Flag non supporté par docker build**
- ❌ `docker build --network=host` → Ne résout pas les DNS
- ❌ Modifier le Dockerfile → Complexe et non maintainable

✅ **SEULE SOLUTION : Configurer `/etc/docker/daemon.json`**

## Après la correction

Une fois les DNS configurés, relancez le déploiement :

```bash
./deployment/scripts/deploy.sh deploy dev --use-git --branch dev
```

Le build devrait maintenant fonctionner correctement.
