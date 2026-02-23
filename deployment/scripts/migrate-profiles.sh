#!/bin/bash

# ============================================================================
# Script de migration des profils vers le nouveau format
# Convertit les anciens profils au format standardisé
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/.registry-profiles"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_ROOT

# Charger la configuration projet (.devops.yml) via loader central
source "$SCRIPT_DIR/config-loader.sh"
load_devops_config || true
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_ROOT")}"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Migration des profils vers le nouveau format     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Fonction pour migrer un profil
migrate_profile() {
    local profile_file=$1
    local profile_name=$(basename "$profile_file" .env)

    echo -e "${YELLOW}Profil : ${profile_name}${NC}"

    # Charger le profil existant
    source "$profile_file"

    # Vérifier si le profil a déjà le nouveau format
    if grep -q "^STAGING_BRANCH=" "$profile_file" && \
       grep -q "^REGISTRY_TOKEN=" "$profile_file" && \
       grep -q "^GIT_REPO=" "$profile_file"; then
        echo -e "  ${GREEN}✓${NC} Déjà au nouveau format"
        return 0
    fi

    echo -e "  ${YELLOW}→${NC} Migration nécessaire"

    # Sauvegarder l'ancien profil
    cp "$profile_file" "${profile_file}.backup"
    echo -e "  ${GREEN}✓${NC} Sauvegarde créée : ${profile_name}.env.backup"

    # Créer le nouveau profil
    local current_date=$(date)
    cat > "$profile_file" <<EOF
# Profil Registry: ${profile_name}
# Type: ${REGISTRY_TYPE:-dockerhub} (${REGISTRY_URL:-docker.io})
# Migré le: ${current_date}

REGISTRY_TYPE=${REGISTRY_TYPE:-dockerhub}
REGISTRY_URL=${REGISTRY_URL:-docker.io}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_TOKEN=${REGISTRY_TOKEN:-}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-}
IMAGE_NAME=${IMAGE_NAME:-${PROJECT_NAME}}
GIT_REPO=${GIT_REPO:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
DEV_BRANCH=${DEV_BRANCH:-dev}
STAGING_BRANCH=${STAGING_BRANCH:-staging}
PROD_BRANCH=${PROD_BRANCH:-prod}
EOF

    echo -e "  ${GREEN}✓${NC} Profil migré au nouveau format"

    # Proposer de chiffrer
    read -p "  Voulez-vous chiffrer ce profil maintenant? (y/N): " encrypt_choice
    if [[ "$encrypt_choice" =~ ^[Yy]$ ]]; then
        if [ -f "$SCRIPT_DIR/env-encrypt.py" ]; then
            if python3 "$SCRIPT_DIR/env-encrypt.py" encrypt "$profile_file" 2>&1 | grep -q "chiffré"; then
                echo -e "  ${GREEN}✓${NC} Profil chiffré avec succès"
                # Supprimer le profil non chiffré
                rm -f "$profile_file"
                echo -e "  ${GREEN}✓${NC} Profil non chiffré supprimé"
            else
                echo -e "  ${RED}✗${NC} Erreur lors du chiffrement"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC}  Script de chiffrement non trouvé"
        fi
    fi

    echo ""
}

# Créer le dossier s'il n'existe pas
mkdir -p "$PROFILES_DIR"

# Chercher tous les profils non chiffrés
echo "Recherche des profils à migrer..."
echo ""

profiles_found=0
if [ -d "$PROFILES_DIR" ]; then
    for profile in "$PROFILES_DIR"/*.env; do
        if [ -f "$profile" ]; then
            migrate_profile "$profile"
            ((profiles_found++))
        fi
    done
fi

# Si aucun profil trouvé
if [ $profiles_found -eq 0 ]; then
    echo -e "${YELLOW}Aucun profil à migrer${NC}"
    echo ""
    echo "Options :"
    echo "  1. Créer un nouveau profil : ./deployment/scripts/deploy-registry.sh"
    echo "  2. Les profils sont peut-être déjà chiffrés (*.env.encrypted)"
    echo ""

    # Vérifier les profils chiffrés
    if ls "$PROFILES_DIR"/*.env.encrypted 2>/dev/null | grep -q .; then
        echo -e "${GREEN}Profils chiffrés trouvés :${NC}"
        ls -1 "$PROFILES_DIR"/*.env.encrypted | xargs -n 1 basename | sed 's/^/  - /'
        echo ""
        echo -e "${GREEN}✓${NC} Ces profils sont déjà au bon format"
    fi
else
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Migration terminée                                ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} $profiles_found profil(s) migré(s)"
    echo ""
    echo "Prochaines étapes :"
    echo "  1. Vérifier les profils migrés"
    echo "  2. Tester le déploiement : ./deployment/scripts/deploy-registry.sh"
    echo "  3. Supprimer les sauvegardes (.backup) si tout fonctionne"
    echo ""
fi
