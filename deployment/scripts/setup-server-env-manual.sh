#!/bin/bash

# ============================================================================
# Script Helper - Configuration des fichiers .env sur le serveur
# ============================================================================
#
# USAGE:
#   ./setup-server-env.sh [server-user@server-host]
#
# EXEMPLE:
#   ./setup-server-env.sh user@server
#
# ============================================================================

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$DEPLOYMENT_DIR/.." && pwd)"
export PROJECT_ROOT

# Charger la configuration projet (.devops.yml) via loader central
source "$SCRIPT_DIR/config-loader.sh"
load_devops_config || true

# Nom projet robuste (depuis .devops.yml ou fallback dossier)
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_ROOT")}"
SERVER_APP_DIR="/srv/home/${PROJECT_NAME}"

SERVER=$1

if [ -z "$SERVER" ]; then
    log_error "Usage: $0 <user@server-host>"
    echo ""
    echo "Exemple:"
    echo "  $0 user@server"
    exit 1
fi

log_header "Configuration des fichiers .env sur le serveur"

echo -e "${CYAN}Serveur cible:${NC} $SERVER"
echo ""

# Étape 1: Vérifier que la clé existe
log_info "Étape 1/5: Vérification de la clé de chiffrement..."

if [ ! -f "$PROJECT_ROOT/.env.key" ]; then
    log_warn "Clé de chiffrement non trouvée"
    read -p "Voulez-vous générer une nouvelle clé? (y/N): " generate_key

    if [[ "$generate_key" =~ ^[Yy]$ ]]; then
        log_info "Génération d'une nouvelle clé..."
        python3 "$SCRIPT_DIR/env-encrypt.py" generate-key
        log_success "Clé générée: $PROJECT_ROOT/.env.key"
    else
        log_error "Clé de chiffrement requise. Abandon."
        exit 1
    fi
else
    log_success "Clé de chiffrement trouvée"
fi

# Étape 2: Chiffrer les fichiers .env
log_info "Étape 2/5: Chiffrement des fichiers .env..."

for env in dev staging prod; do
    env_file="$PROJECT_ROOT/.env.$env"

    if [ -f "$env_file" ]; then
        log_info "Chiffrement de .env.$env..."
        python3 "$SCRIPT_DIR/env-encrypt.py" encrypt "$env_file"

        if [ -f "${env_file}.encrypted" ]; then
            log_success ".env.$env chiffré"
        else
            log_warn "Échec du chiffrement de .env.$env"
        fi
    else
        log_warn "Fichier .env.$env non trouvé, ignoré"
    fi
done

# Étape 3: Créer le répertoire deployment sur le serveur si nécessaire
log_info "Étape 3/5: Préparation du serveur..."

ssh "$SERVER" "mkdir -p \"$SERVER_APP_DIR/deployment\"" || {
    log_error "Impossible de se connecter au serveur $SERVER"
    exit 1
}

log_success "Répertoire créé sur le serveur"

# Étape 4: Transférer les fichiers
log_info "Étape 4/5: Transfert des fichiers sur le serveur..."

# Transférer la clé de chiffrement
log_info "Transfert de .env.key..."
scp "$PROJECT_ROOT/.env.key" "$SERVER:$SERVER_APP_DIR/" || {
    log_error "Échec du transfert de la clé"
    exit 1
}
log_success "Clé transférée"

# Transférer les fichiers chiffrés
for env in dev staging prod; do
    encrypted_file="$PROJECT_ROOT/.env.${env}.encrypted"

    if [ -f "$encrypted_file" ]; then
        log_info "Transfert de .env.$env.encrypted..."
        scp "$encrypted_file" "$SERVER:$SERVER_APP_DIR/deployment/" || {
            log_warn "Échec du transfert de .env.$env.encrypted"
            continue
        }
        log_success ".env.$env.encrypted transféré"
    fi
done

# Étape 5: Sécuriser les fichiers sur le serveur
log_info "Étape 5/5: Sécurisation des fichiers sur le serveur..."

ssh "$SERVER" "SERVER_APP_DIR='$SERVER_APP_DIR' bash -s" << 'ENDSSH'
cd "$SERVER_APP_DIR"

# Protéger la clé de chiffrement
if [ -f .env.key ]; then
    chmod 600 .env.key
    echo "✓ Clé de chiffrement protégée (600)"
fi

# Créer le marker pour la détection serveur
touch deployment/.server-marker
echo "✓ Marker serveur créé"

# Supprimer tout fichier .env non chiffré qui pourrait exister
for env_file in .env.dev .env.staging .env.prod; do
    if [ -f "$env_file" ]; then
        rm -f "$env_file"
        echo "✓ Fichier $env_file non chiffré supprimé (sécurité)"
    fi
done

# Vérifier la configuration
echo ""
echo "Configuration finale:"
echo "===================="

# Clé
if [ -f .env.key ]; then
    echo "✓ .env.key présent ($(ls -l .env.key | awk '{print $1}'))"
else
    echo "✗ .env.key MANQUANT"
fi

# Fichiers chiffrés
for env in dev staging prod; do
    if [ -f "deployment/.env.${env}.encrypted" ]; then
        echo "✓ .env.$env.encrypted présent"
    else
        echo "✗ .env.$env.encrypted manquant"
    fi
done

# Marker
if [ -f deployment/.server-marker ]; then
    echo "✓ .server-marker présent"
else
    echo "✗ .server-marker manquant"
fi

ENDSSH

log_success "Configuration terminée!"

echo ""
log_header "Récapitulatif"

echo -e "${CYAN}Fichiers installés sur $SERVER:${NC}"
echo "  • $SERVER_APP_DIR/.env.key (chmod 600)"
echo "  • $SERVER_APP_DIR/deployment/.env.*.encrypted"
echo "  • $SERVER_APP_DIR/deployment/.server-marker"
echo ""
echo -e "${GREEN}Le serveur est maintenant configuré!${NC}"
echo ""
echo -e "${CYAN}Pour déployer:${NC}"
echo "  ssh $SERVER"
echo "  cd $SERVER_APP_DIR/deployment/scripts"
echo "  ./deploy-registry.sh deploy dev"
echo ""
