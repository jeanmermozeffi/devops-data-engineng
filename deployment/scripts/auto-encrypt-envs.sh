#!/bin/bash

# ============================================================================
# Script d'auto-chiffrement des fichiers .env
# ============================================================================
# Ce script automatise le chiffrement de tous les fichiers .env trouvés
# et supprime les versions non chiffrées pour sécuriser le serveur.
#
# USAGE:
#   ./auto-encrypt-envs.sh                  # Mode interactif
#   ./auto-encrypt-envs.sh --auto-confirm   # Mode automatique (sans confirmation)
#   ./auto-encrypt-envs.sh --help           # Afficher l'aide
#
# ============================================================================

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Fonctions d'affichage
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENCRYPT_SCRIPT="$SCRIPT_DIR/env-encrypt.py"
SENSITIVE_VARS="$SCRIPT_DIR/sensitive-vars.yml"
PROJECT_ROOT="${PROJECT_ROOT:-$PARENT_DIR}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
KEY_FILE="$PROJECT_ROOT/.env.key"
AUTO_CONFIRM=false
KEEP_CLEAR=false

# Détecter et utiliser le venv si disponible
PROJECT_VENV_DIR="$PROJECT_ROOT/.venv"
DEVOPS_VENV_DIR="$PARENT_DIR/.venv"
if [ -d "$PROJECT_VENV_DIR" ] && [ -f "$PROJECT_VENV_DIR/bin/python3" ]; then
    PYTHON_CMD="$PROJECT_VENV_DIR/bin/python3"
    log_info "Utilisation du venv projet: $PROJECT_VENV_DIR"
elif [ -d "$DEVOPS_VENV_DIR" ] && [ -f "$DEVOPS_VENV_DIR/bin/python3" ]; then
    PYTHON_CMD="$DEVOPS_VENV_DIR/bin/python3"
    log_info "Utilisation du venv devops: $DEVOPS_VENV_DIR"
else
    PYTHON_CMD="python3"
    log_info "Utilisation de Python global"
fi

# Parser les arguments
for arg in "$@"; do
    case $arg in
        --auto-confirm)
            AUTO_CONFIRM=true
            ;;
        --keep-clear)
            KEEP_CLEAR=true
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --auto-confirm    Mode automatique (pas de confirmation)
  --keep-clear      Conserver les fichiers .env en clair après chiffrement
  --help, -h        Afficher cette aide

Description:
  Ce script automatise le chiffrement de tous les fichiers .env
  trouvés dans le répertoire du projet cible.
  Par défaut, les fichiers .env en clair sont supprimés après chiffrement.
  Avec --keep-clear, les fichiers .env en clair sont conservés.

Étapes:
  1. Vérifier les dépendances Python
  2. Générer une clé de chiffrement (si inexistante)
  3. Lister les fichiers .env à chiffrer
  4. Chiffrer chaque fichier .env
  5. Supprimer les fichiers .env non chiffrés (sauf --keep-clear)
  6. Afficher le résumé

EOF
            exit 0
            ;;
        *)
            log_error "Argument inconnu: $arg"
            echo "Utilisez --help pour l'aide"
            exit 1
            ;;
    esac
done

# ============================================================================
# Vérifications préliminaires
# ============================================================================

log_header "CHIFFREMENT AUTOMATIQUE DES FICHIERS .ENV"
log_info "Projet cible: $PROJECT_ROOT"

# Vérifier que le script Python existe
if [ ! -f "$ENCRYPT_SCRIPT" ]; then
    log_error "Script env-encrypt.py non trouvé: $ENCRYPT_SCRIPT"
    exit 1
fi

# Vérifier que sensitive-vars.yml existe
if [ ! -f "$SENSITIVE_VARS" ]; then
    log_warn "Fichier sensitive-vars.yml non trouvé: $SENSITIVE_VARS"
    log_info "Le chiffrement se fera sans configuration de variables sensibles"
fi

# Vérifier Python 3
if ! command -v $PYTHON_CMD &> /dev/null; then
    log_error "Python 3 n'est pas installé"
    exit 1
fi

# Vérifier les dépendances Python
log_info "Vérification des dépendances Python..."
if ! $PYTHON_CMD -c "import cryptography" 2>/dev/null; then
    log_warn "Module 'cryptography' non installé"
    log_info "Installation: pip3 install cryptography"
    read -p "Installer maintenant? (y/N): " install
    if [[ "$install" =~ ^[Yy]$ ]]; then
        pip3 install cryptography
    else
        exit 1
    fi
fi

if ! $PYTHON_CMD -c "import yaml" 2>/dev/null; then
    log_warn "Module 'pyyaml' non installé"
    log_info "Installation: pip3 install pyyaml"
    read -p "Installer maintenant? (y/N): " install
    if [[ "$install" =~ ^[Yy]$ ]]; then
        pip3 install pyyaml
    else
        exit 1
    fi
fi

log_success "Dépendances OK"
echo ""

# ============================================================================
# Générer la clé de chiffrement
# ============================================================================

if [ -f "$KEY_FILE" ]; then
    log_info "Clé de chiffrement existante trouvée: $KEY_FILE"
else
    if [ -d "$KEY_FILE" ]; then
        KEY_DIR_BACKUP="${KEY_FILE}.dir.bak.$(date +%Y%m%d%H%M%S)"
        mv "$KEY_FILE" "$KEY_DIR_BACKUP"
        log_warn "Chemin clé invalide (dossier): déplacé vers $KEY_DIR_BACKUP"
    fi

    log_info "Génération d'une nouvelle clé de chiffrement..."
    $PYTHON_CMD "$ENCRYPT_SCRIPT" generate-key --key-file "$KEY_FILE"
    log_success "Clé générée: $KEY_FILE"
    log_warn "⚠️  IMPORTANT: Sauvegardez cette clé dans un endroit sûr !"
fi

echo ""

# ============================================================================
# Lister les fichiers .env
# ============================================================================

log_info "Recherche des fichiers .env..."
cd "$PROJECT_ROOT"

# Trouver tous les fichiers .env (mais pas .example, .encrypted, .key ou .registry)
# Note: .env.registry ne contient pas de secrets, juste des noms publics (registry, username, image)
ENV_FILES=$(find . -maxdepth 1 -type f \( -name ".env" -o -name ".env.*" \) ! -name "*.example" ! -name "*.encrypted" ! -name ".env.key" ! -name ".env.registry" ! -name ".env.local" ! -name ".env.bak")

if [ -z "$ENV_FILES" ]; then
    log_warn "Aucun fichier .env trouvé à chiffrer"
    exit 0
fi

echo -e "${CYAN}Fichiers .env trouvés:${NC}"
echo "$ENV_FILES" | sed 's/^\.\//  - /'
echo ""

# ============================================================================
# Confirmation
# ============================================================================

if [ "$AUTO_CONFIRM" = false ]; then
    log_warn "⚠️  ATTENTION: Cette opération va:"
    echo "  1. Chiffrer tous les fichiers .env listés ci-dessus"
    if [ "$KEEP_CLEAR" = true ]; then
        echo "  2. Conserver les versions non chiffrées (--keep-clear)"
    else
        echo "  2. Supprimer les versions non chiffrées"
    fi
    echo ""
    read -p "Continuer? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Opération annulée"
        exit 0
    fi
    echo ""
fi

# ============================================================================
# Chiffrement
# ============================================================================

log_header "CHIFFREMENT EN COURS"

ENCRYPTED_COUNT=0
FAILED_COUNT=0
DELETED_COUNT=0

for env_file in $ENV_FILES; do
    # Enlever le ./ au début
    env_file="${env_file#./}"

    if [ -d "${env_file}.encrypted" ]; then
        encrypted_dir_backup="${env_file}.encrypted.dir.bak.$(date +%Y%m%d%H%M%S)"
        mv "${env_file}.encrypted" "$encrypted_dir_backup"
        log_warn "Chemin chiffré invalide (dossier): ${env_file}.encrypted -> $encrypted_dir_backup"
    fi

    log_info "Chiffrement de $env_file..."

    if $PYTHON_CMD "$ENCRYPT_SCRIPT" encrypt "$env_file" --key-file "$KEY_FILE" 2>&1; then
        log_success "✓ $env_file → ${env_file}.encrypted"
        ENCRYPTED_COUNT=$((ENCRYPTED_COUNT + 1))
    else
        log_error "✗ Échec du chiffrement de $env_file"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo ""

# ============================================================================
# Suppression des fichiers non chiffrés
# ============================================================================

if [ "$KEEP_CLEAR" = true ]; then
    log_info "Option --keep-clear active: conservation des fichiers .env en clair"
    echo ""
elif [ $ENCRYPTED_COUNT -gt 0 ]; then
    log_header "SUPPRESSION DES FICHIERS NON CHIFFRÉS"

    for env_file in $ENV_FILES; do
        env_file="${env_file#./}"
        encrypted_file="${env_file}.encrypted"

        # Vérifier que le fichier chiffré existe avant de supprimer
        if [ -f "$encrypted_file" ]; then
            log_info "Suppression de $env_file..."
            rm -f "$env_file"
            log_success "✓ $env_file supprimé"
            DELETED_COUNT=$((DELETED_COUNT + 1))
        else
            log_warn "⚠️  $encrypted_file non trouvé, conservation de $env_file"
        fi
    done

    echo ""
fi

# ============================================================================
# Résumé
# ============================================================================

log_header "RÉSUMÉ"

echo -e "${WHITE}Opération terminée:${NC}"
echo -e "  ${GREEN}✓${NC} Fichiers chiffrés : ${CYAN}$ENCRYPTED_COUNT${NC}"
echo -e "  ${RED}✗${NC} Échecs           : ${CYAN}$FAILED_COUNT${NC}"
echo -e "  ${YELLOW}🗑${NC}  Fichiers supprimés: ${CYAN}$DELETED_COUNT${NC}"
echo ""

if [ -f "$KEY_FILE" ]; then
    echo -e "${YELLOW}⚠️  IMPORTANT:${NC}"
    echo -e "  Clé de chiffrement: ${CYAN}$KEY_FILE${NC}"
    echo -e "  ${RED}Sauvegardez cette clé dans un endroit sûr !${NC}"
    echo -e "  Sans cette clé, vous ne pourrez pas déchiffrer vos fichiers."
    echo ""
fi

log_success "Chiffrement terminé avec succès !"

exit 0
