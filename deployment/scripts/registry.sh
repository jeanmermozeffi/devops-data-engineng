#!/bin/bash

# ============================================================================
# ${PROJECT_NAME:-DevOps} - Docker Registry Management (Interactive & Multi-Registry)
# Description: Gestion complète du registry Docker avec support multi-registries
# Usage: ./registry.sh [command] [arguments] [options]
#        ./registry.sh                    Mode interactif
#        ./registry.sh interactive        Mode interactif
# ============================================================================

set -e  # Exit on error

# ============================================================================
# COULEURS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# ============================================================================
# FONCTIONS D'AFFICHAGE
# ============================================================================

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

print_separator() {
    echo -e "${CYAN}----------------------------------------${NC}"
}

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Charger la configuration depuis .devops.yml
source "$SCRIPT_DIR/config-loader.sh"
load_devops_config

# Si PROJECT_ROOT n'est pas défini (ancien comportement), utiliser ../..
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
fi

cd "$PROJECT_ROOT"

# Répertoire pour stocker les profils
PROFILES_DIR="$SCRIPT_DIR/.registry-profiles"
mkdir -p "$PROFILES_DIR"

# Variables globales pour la configuration actuelle
# Ces variables peuvent être surchargées par les profils ou .devops.yml
# REGISTRY_URL, REGISTRY_USERNAME, IMAGE_NAME, etc. sont chargés par config-loader.sh
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"
REGISTRY_TOKEN="${REGISTRY_TOKEN:-}"
CURRENT_PROFILE="${CURRENT_PROFILE:-}"

# Utiliser les valeurs depuis .devops.yml si disponibles
# Sinon, utiliser des valeurs par défaut vides (compatibilité)
REGISTRY_URL="${REGISTRY_URL:-}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"
IMAGE_NAME="${IMAGE_NAME:-}"
GIT_REPO="${GIT_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GIT_USERNAME="${GIT_USERNAME:-}"  # Username Git (GitLab principalement)
DEV_BRANCH="${DEV_BRANCH:-dev}"
STAGING_BRANCH="${STAGING_BRANCH:-staging}"
PROD_BRANCH="${PROD_BRANCH:-main}"
REGISTRY_TYPE="${REGISTRY_TYPE:-dockerhub}"

# ============================================================================
# CONFIGURATIONS DES REGISTRIES
# ============================================================================

# Obtenir l'URL par défaut selon le type de registry
get_default_registry_url() {
    local type=$1
    case "$type" in
        dockerhub)
            echo "docker.io"
            ;;
        gitlab)
            echo "registry.gitlab.com"
            ;;
        github)
            echo "ghcr.io"
            ;;
        custom)
            echo ""
            ;;
        *)
            echo "docker.io"
            ;;
    esac
}

# Obtenir la description d'un type de registry
get_registry_description() {
    local type=$1
    case "$type" in
        dockerhub)
            echo "Docker Hub (docker.io)"
            ;;
        gitlab)
            echo "GitLab Container Registry (registry.gitlab.com)"
            ;;
        github)
            echo "GitHub Container Registry (ghcr.io)"
            ;;
        custom)
            echo "Registry Docker personnalisé"
            ;;
        *)
            echo "Inconnu"
            ;;
    esac
}

# ============================================================================
# GESTION DES PROFILS
# ============================================================================

# Créer un nouveau profil
profile_create() {
    local profile_name=$1

    if [ -z "$profile_name" ]; then
        read -p "Nom du profil: " profile_name
    fi

    if [ -z "$profile_name" ]; then
        log_error "Nom de profil requis"
        return 1
    fi

    local profile_file="$PROFILES_DIR/${profile_name}.env"

    if [ -f "$profile_file" ]; then
        read -p "Le profil '$profile_name' existe déjà. Écraser? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            log_info "Création annulée"
            return 0
        fi
    fi

    log_header "CRÉATION DU PROFIL: $profile_name"

    # Afficher les infos du projet depuis .devops.yml
    echo -e "${CYAN}Configuration du projet (depuis .devops.yml):${NC}"
    echo -e "  Registry URL: ${WHITE}${REGISTRY_URL:-non défini}${NC}"
    echo -e "  Username: ${WHITE}${REGISTRY_USERNAME:-non défini}${NC}"
    echo -e "  Image: ${WHITE}${IMAGE_NAME:-non défini}${NC}"
    echo ""
    print_separator
    echo ""

    # Sélection du type de registry
    echo -e "${CYAN}Type de registry:${NC}"
    echo "  1) Docker Hub (docker.io)"
    echo "  2) GitLab Container Registry"
    echo "  3) GitHub Container Registry"
    echo "  4) Registry personnalisé"
    echo ""
    read -p "Choisissez le type de registry (1-4): " registry_choice

    local registry_type
    case "$registry_choice" in
        1) registry_type="dockerhub" ;;
        2) registry_type="gitlab" ;;
        3) registry_type="github" ;;
        4) registry_type="custom" ;;
        *)
            log_error "Choix invalide"
            return 1
            ;;
    esac

    echo ""
    echo -e "${CYAN}Authentification au registry:${NC}"
    echo "  1) Token (recommandé)"
    echo "  2) Mot de passe"
    echo "  3) Aucun (connexion interactive)"
    read -p "Méthode d'authentification (1-3): " auth_choice

    local registry_token=""
    local registry_password=""
    case "$auth_choice" in
        1)
            read -s -p "Token d'accès au registry: " registry_token
            echo ""
            ;;
        2)
            read -s -p "Mot de passe du registry: " registry_password
            echo ""
            ;;
        3)
            log_info "Authentification interactive sera utilisée"
            ;;
    esac

    # Token GitHub optionnel
    echo ""
    read -p "Token GitHub (optionnel, pour repos privés): " github_token

    # Créer le fichier de profil (CREDENTIALS UNIQUEMENT)
    cat > "$profile_file" << EOF
# Profil Registry: $profile_name
# Type: $(get_registry_description "$registry_type")
# Créé le: $(date)
#
# NOTE: Ce profil contient uniquement les credentials.
# Les informations du projet (registry_url, registry_username, image_name, etc.)
# sont chargées depuis le fichier .devops.yml du projet.

REGISTRY_TYPE=$registry_type
REGISTRY_TOKEN=$registry_token
REGISTRY_PASSWORD=$registry_password
GITHUB_TOKEN=$github_token
EOF

    log_success "Profil '$profile_name' créé avec succès"
    log_info "Fichier: $profile_file"
    echo ""
    log_info "Les infos du projet sont lues depuis .devops.yml"
}

# Lister les profils disponibles
profile_list() {
    log_header "PROFILS DISPONIBLES"

    if [ ! -d "$PROFILES_DIR" ] || [ -z "$(ls -A $PROFILES_DIR/*.env 2>/dev/null)" ]; then
        log_warn "Aucun profil trouvé"
        return 0
    fi

    echo -e "${CYAN}Projet actuel:${NC} ${WHITE}${REGISTRY_USERNAME:-?}/${IMAGE_NAME:-?}${NC} (depuis .devops.yml)"
    echo ""

    local current_marker=""
    for pfile in "$PROFILES_DIR"/*.env; do
        local pname=$(basename "$pfile" .env)
        if [ "$pname" == "$CURRENT_PROFILE" ]; then
            current_marker=" ${GREEN}(actif)${NC}"
        else
            current_marker=""
        fi

        # Lire le type depuis le profil sans utiliser source
        local ptype=$(grep "^REGISTRY_TYPE=" "$pfile" 2>/dev/null | cut -d'=' -f2)
        local has_token=$(grep -q "^REGISTRY_TOKEN=.\+" "$pfile" 2>/dev/null && echo "oui" || echo "non")

        echo -e "  ${CYAN}●${NC} ${WHITE}$pname${NC}$current_marker"
        echo -e "    Type: $(get_registry_description "$ptype")"
        echo -e "    Token configuré: $has_token"
        echo ""
    done
}

# Charger un profil
profile_load() {
    local profile_name=$1

    if [ -z "$profile_name" ]; then
        # Mode interactif - afficher une liste numérotée
        log_header "CHARGER UN PROFIL"

        if [ ! -d "$PROFILES_DIR" ] || [ -z "$(ls -A $PROFILES_DIR/*.env 2>/dev/null)" ]; then
            log_warn "Aucun profil trouvé"
            return 1
        fi

        local profiles=()
        local i=1
        for pfile in "$PROFILES_DIR"/*.env; do
            local pname=$(basename "$pfile" .env)
            profiles+=("$pname")

            # Lire le type de registry depuis le profil (sans source pour ne pas polluer)
            local ptype=$(grep "^REGISTRY_TYPE=" "$pfile" 2>/dev/null | cut -d'=' -f2)
            printf "  ${CYAN}%d)${NC} ${WHITE}%s${NC}\n" "$i" "$pname"
            printf "     Type: %s\n" "$(get_registry_description "$ptype")"
            printf "\n"
            ((i++))
        done

        echo ""
        read -p "Choisissez un profil (1-${#profiles[@]}) ou tapez le nom: " choice

        # Vérifier si c'est un numéro
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
                profile_name="${profiles[$((choice-1))]}"
            else
                log_error "Numéro invalide"
                return 1
            fi
        else
            profile_name="$choice"
        fi
    fi

    local profile_file="$PROFILES_DIR/${profile_name}.env"

    if [ ! -f "$profile_file" ]; then
        log_error "Profil '$profile_name' introuvable"
        return 1
    fi

    # Charger UNIQUEMENT les credentials REGISTRY depuis le profil
    # GITHUB_TOKEN vient de .devops.yml (spécifique au projet Git)
    # Les autres valeurs (REGISTRY_URL, REGISTRY_USERNAME, IMAGE_NAME, etc.)
    # viennent aussi de .devops.yml et ne doivent PAS être écrasées
    local temp_type=$(grep "^REGISTRY_TYPE=" "$profile_file" 2>/dev/null | cut -d'=' -f2)
    local temp_token=$(grep "^REGISTRY_TOKEN=" "$profile_file" 2>/dev/null | cut -d'=' -f2)
    local temp_password=$(grep "^REGISTRY_PASSWORD=" "$profile_file" 2>/dev/null | cut -d'=' -f2)

    # Appliquer les credentials REGISTRY uniquement
    [ -n "$temp_type" ] && REGISTRY_TYPE="$temp_type"
    [ -n "$temp_token" ] && REGISTRY_TOKEN="$temp_token"
    [ -n "$temp_password" ] && REGISTRY_PASSWORD="$temp_password"
    # Note: GITHUB_TOKEN n'est PAS chargé depuis le profil (vient de .devops.yml)

    CURRENT_PROFILE="$profile_name"

    log_success "Profil '$profile_name' chargé (credentials)"
    log_info "Type: $(get_registry_description "$REGISTRY_TYPE")"
    log_info "Projet: ${REGISTRY_USERNAME:-non défini}/${IMAGE_NAME:-non défini} (depuis .devops.yml)"
}

# Supprimer un profil
profile_delete() {
    local profile_name=$1

    if [ -z "$profile_name" ]; then
        log_header "SUPPRIMER UN PROFIL"

        if [ ! -d "$PROFILES_DIR" ] || [ -z "$(ls -A $PROFILES_DIR/*.env 2>/dev/null)" ]; then
            log_warn "Aucun profil trouvé"
            return 1
        fi

        local profiles=()
        local i=1
        for profile_file in "$PROFILES_DIR"/*.env; do
            local pname=$(basename "$profile_file" .env)
            profiles+=("$pname")

            # Charger le profil pour afficher les détails
            source "$profile_file"
            printf "  ${CYAN}%d)${NC} ${WHITE}%s${NC}\n" "$i" "$pname"
            printf "     Registry: %s\n" "$(get_registry_description "$REGISTRY_TYPE")"
            printf "\n"
            ((i++))
        done

        echo ""
        read -p "Choisissez un profil (1-${#profiles[@]}) ou tapez le nom: " choice

        # Vérifier si c'est un numéro
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
                profile_name="${profiles[$((choice-1))]}"
            else
                log_error "Numéro invalide"
                return 1
            fi
        else
            profile_name="$choice"
        fi
    fi

    local profile_file="$PROFILES_DIR/${profile_name}.env"

    if [ ! -f "$profile_file" ]; then
        log_error "Profil '$profile_name' introuvable"
        return 1
    fi

    read -p "Supprimer le profil '$profile_name'? (yes/n): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Suppression annulée"
        return 0
    fi

    rm "$profile_file"
    log_success "Profil '$profile_name' supprimé"
}

# Afficher le profil actuel et la configuration complète
profile_show() {
    log_header "CONFIGURATION ACTUELLE"

    echo -e "${CYAN}Profil credentials:${NC}"
    if [ -z "$CURRENT_PROFILE" ]; then
        echo -e "  Profil:            ${YELLOW}Aucun profil chargé${NC}"
    else
        echo -e "  Profil:            ${WHITE}$CURRENT_PROFILE${NC}"
    fi
    echo -e "  Registry Type:     $(get_registry_description "$REGISTRY_TYPE")"
    echo -e "  Has Token:         $([ -n "$REGISTRY_TOKEN" ] && echo "${GREEN}Oui${NC}" || echo "${YELLOW}Non${NC}")"
    echo -e "  Has GitHub Token:  $([ -n "$GITHUB_TOKEN" ] && echo "${GREEN}Oui${NC}" || echo "${YELLOW}Non${NC}")"
    echo ""

    echo -e "${CYAN}Configuration projet (depuis .devops.yml):${NC}"
    echo -e "  Registry URL:      ${WHITE}${REGISTRY_URL:-non défini}${NC}"
    echo -e "  Username:          ${WHITE}${REGISTRY_USERNAME:-non défini}${NC}"
    echo -e "  Image:             ${WHITE}${IMAGE_NAME:-non défini}${NC}"
    echo -e "  Git Repo:          ${WHITE}${GIT_REPO:-non défini}${NC}"
    echo -e "  Dev Branch:        ${WHITE}${DEV_BRANCH:-dev}${NC}"
    echo -e "  Staging Branch:    ${WHITE}${STAGING_BRANCH:-staging}${NC}"
    echo -e "  Prod Branch:       ${WHITE}${PROD_BRANCH:-main}${NC}"
}

# ============================================================================
# CHARGEMENT DE LA CONFIGURATION
# ============================================================================

load_config() {
    # Essayer de charger depuis .env.registry (legacy)
    local legacy_config="$SCRIPT_DIR/.env.registry"
    if [ -f "$legacy_config" ]; then
        log_info "Chargement de la configuration depuis .env.registry"
        source "$legacy_config"
        CURRENT_PROFILE="legacy"
        REGISTRY_TYPE="${REGISTRY_TYPE:-dockerhub}"
        return 0
    fi

    # Essayer de charger le dernier profil utilisé
    local last_profile_file="$PROFILES_DIR/.last"
    if [ -f "$last_profile_file" ]; then
        local last_profile=$(cat "$last_profile_file")
        if profile_load "$last_profile" 2>/dev/null; then
            return 0
        fi
    fi

    # Fallback: utiliser la configuration projet (.devops.yml)
    if [ -n "$REGISTRY_USERNAME" ] && [ -n "$IMAGE_NAME" ]; then
        CURRENT_PROFILE="devops-yml"
        REGISTRY_TYPE="${REGISTRY_TYPE:-dockerhub}"
        return 0
    fi

    # Aucune configuration trouvée
    return 1
}

# Sauvegarder le profil utilisé
save_last_profile() {
    if [ -n "$CURRENT_PROFILE" ]; then
        echo "$CURRENT_PROFILE" > "$PROFILES_DIR/.last"
    fi
}

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================

# Générer un tag de version basé sur la date et le commit
generate_version_tag() {
    local env=$1
    local date_tag=$(date +%Y%m%d-%H%M%S)
    local git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
    echo "${env}-v${date_tag}-${git_hash}"
}

# ============================================================================
# FONCTIONS VERSIONING SÉMANTIQUE
# ============================================================================

# Extraire la dernière version depuis les tags Docker Hub
get_latest_version() {
    local env=$1
    local api_url="https://hub.docker.com/v2/repositories/${REGISTRY_USERNAME}/${IMAGE_NAME}/tags?page_size=100"

    # Récupérer tous les tags de l'environnement au format vX.Y.Z (sémantique uniquement)
    # Exclure les tags date+hash (v20251216-...) et ne garder que vX.Y.Z
    local tags=$(curl -s "$api_url" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep "^${env}-v[0-9]\+\.[0-9]\+\.[0-9]\+$" | sed "s/^${env}-//" | sort -rV)

    if [ -z "$tags" ]; then
        # Aucun tag sémantique trouvé, retourner v0.0.0
        echo "v0.0.0"
        return 0
    fi

    # Retourner la dernière version sémantique
    local latest=$(echo "$tags" | head -n1)
    echo "$latest"
}

# Incrémenter une version (PATCH, MINOR, MAJOR)
increment_version() {
    local version=$1
    local type=$2

    # Retirer le 'v' si présent
    version=${version#v}

    # Extraire MAJOR.MINOR.PATCH
    local major minor patch
    IFS='.' read -r major minor patch <<< "$version"

    case "$type" in
        PATCH)
            ((patch++))
            ;;
        MINOR)
            ((minor++))
            patch=0
            ;;
        MAJOR)
            ((major++))
            minor=0
            patch=0
            ;;
        *)
            echo "Type invalide: $type" >&2
            return 1
            ;;
    esac

    echo "v${major}.${minor}.${patch}"
}

# Menu de sélection de version
choose_version() {
    local env=$1

    echo "" >&2
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}║      Gestion de Version (Semantic Versioning)     ║${NC}" >&2
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2

    # Récupérer la dernière version
    local current_version=$(get_latest_version "$env")

    echo -e "${WHITE}ℹ️  Dernière version: ${GREEN}${current_version}${NC}" >&2
    echo "" >&2
    echo -e "${CYAN}Type de version (Versioning Sémantique):${NC}" >&2
    echo "" >&2

    # Calculer les nouvelles versions
    local patch_version=$(increment_version "$current_version" "PATCH")
    local minor_version=$(increment_version "$current_version" "MINOR")
    local major_version=$(increment_version "$current_version" "MAJOR")

    echo -e "  ${GREEN}1.${NC} ${WHITE}PATCH${NC} - ${current_version} → ${GREEN}${patch_version}${NC}" >&2
    echo -e "     └─ Correctifs de bugs, petites corrections" >&2
    echo "" >&2
    echo -e "  ${GREEN}2.${NC} ${WHITE}MINOR${NC} - ${current_version} → ${CYAN}${minor_version}${NC}" >&2
    echo -e "     └─ Nouvelles fonctionnalités (rétrocompatibles)" >&2
    echo "" >&2
    echo -e "  ${GREEN}3.${NC} ${WHITE}MAJOR${NC} - ${current_version} → ${YELLOW}${major_version}${NC}" >&2
    echo -e "     └─ Changements incompatibles (breaking changes)" >&2
    echo "" >&2
    echo -e "  ${GREEN}4.${NC} ${WHITE}Personnalisée${NC} - Entrer manuellement" >&2
    echo -e "  ${GREEN}5.${NC} ${WHITE}Date+Hash${NC} - Format: ${env}-v20251216-abc123 (ancien style)" >&2
    echo -e "  ${GREEN}6.${NC} ${WHITE}Latest${NC} - Utiliser ${env}-latest" >&2
    echo -e "  ${GREEN}0.${NC} Annuler" >&2
    echo "" >&2

    read -p "Choisissez le type de version (0-6): " version_choice

    case "$version_choice" in
        1)
            echo "$patch_version"
            ;;
        2)
            echo "$minor_version"
            ;;
        3)
            echo "$major_version"
            ;;
        4)
            echo "" >&2
            read -p "Entrez la version (format: vX.Y.Z): " custom_version
            # Valider le format
            if [[ "$custom_version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                # Ajouter 'v' si absent
                custom_version=${custom_version#v}
                echo "v${custom_version}"
            else
                log_error "Format invalide. Utilisez vX.Y.Z (ex: v1.2.3)" >&2
                return 1
            fi
            ;;
        5)
            # Ancien style date+hash
            generate_version_tag "$env"
            ;;
        6)
            # Latest
            echo "latest"
            ;;
        0)
            log_info "Opération annulée" >&2
            return 1
            ;;
        *)
            log_error "Choix invalide" >&2
            return 1
            ;;
    esac
}

# Obtenir la branche Git pour un environnement
get_git_branch() {
    local env=$1
    case "$env" in
        dev)
            echo "${DEV_BRANCH:-develop}"
            ;;
        staging)
            echo "${STAGING_BRANCH:-staging}"
            ;;
        prod)
            echo "${PROD_BRANCH:-main}"
            ;;
        *)
            log_error "Environnement invalide: $env (doit être dev, staging ou prod)"
            exit 1
            ;;
    esac
}

# Construire le nom complet de l'image selon le type de registry
get_full_image_name() {
    local env=$1
    local tag=${2:-latest}

    # Si le tag est "latest", ajouter l'env en préfixe
    # Sinon, le tag contient déjà l'env (format: dev-v20251216-...)
    local final_tag
    if [ "$tag" == "latest" ]; then
        final_tag="${env}-latest"
    else
        final_tag="${tag}"
    fi

    case "$REGISTRY_TYPE" in
        dockerhub)
            echo "${REGISTRY_USERNAME}/${IMAGE_NAME}:${final_tag}"
            ;;
        gitlab)
            echo "${REGISTRY_URL}/${REGISTRY_USERNAME}/${IMAGE_NAME}:${final_tag}"
            ;;
        github)
            echo "${REGISTRY_URL}/${REGISTRY_USERNAME}/${IMAGE_NAME}:${final_tag}"
            ;;
        custom)
            echo "${REGISTRY_URL}/${REGISTRY_USERNAME}/${IMAGE_NAME}:${final_tag}"
            ;;
        *)
            # Fallback
            if [ "$REGISTRY_URL" == "docker.io" ]; then
                echo "${REGISTRY_USERNAME}/${IMAGE_NAME}:${final_tag}"
            else
                echo "${REGISTRY_URL}/${REGISTRY_USERNAME}/${IMAGE_NAME}:${final_tag}"
            fi
            ;;
    esac
}

# Vérifier si Docker est connecté au registry
check_registry_login() {
    log_info "Vérification de la connexion au registry..."

    if docker info 2>/dev/null | grep -q "Username: ${REGISTRY_USERNAME}"; then
        log_success "Déjà connecté au registry"
        return 0
    fi

    log_warn "Non connecté au registry"
    return 1
}

# Se connecter au registry
registry_login() {
    log_header "CONNEXION AU REGISTRY"

    if check_registry_login; then
        return 0
    fi

    log_info "Registry: $REGISTRY_URL ($(get_registry_description "$REGISTRY_TYPE"))"
    log_info "Username: $REGISTRY_USERNAME"

    if [ -z "$REGISTRY_PASSWORD" ] && [ -z "$REGISTRY_TOKEN" ]; then
        log_info "Connexion interactive au registry..."
        docker login "$REGISTRY_URL" -u "$REGISTRY_USERNAME"
    elif [ -n "$REGISTRY_TOKEN" ]; then
        log_info "Connexion avec token..."
        echo "$REGISTRY_TOKEN" | docker login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" --password-stdin
    else
        log_info "Connexion avec mot de passe..."
        echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" --password-stdin
    fi

    log_success "Connecté au registry"
}

# ============================================================================
# COMMANDES PRINCIPALES
# ============================================================================

# Build une image avec Git clone
cmd_build() {
    local env=$1
    local version_tag=${2:-$(generate_version_tag "$env")}
    local no_cache=${3:-false}
    local use_git=${4:-true}

    log_header "BUILD IMAGE - Environnement: $env"

    local git_branch=$(get_git_branch "$env")
    local full_image_name=$(get_full_image_name "$env" "$version_tag")
    local full_image_latest=$(get_full_image_name "$env" "latest")

    log_info "Image: $full_image_name"
    log_info "Branche Git: $git_branch"
    log_info "Tag: $version_tag"

    # Sélectionner le Dockerfile
    local dockerfile
    local dockerfile_dir="${DEPLOYMENT_DIR:-deployment}/docker"

    if [ "$use_git" == "true" ]; then
        # Essayer d'abord la variante .git, sinon utiliser le Dockerfile normal
        if [ -f "$dockerfile_dir/Dockerfile.${env}.git" ]; then
            dockerfile="$dockerfile_dir/Dockerfile.${env}.git"
            log_info "Mode: Clone depuis Git (Dockerfile.${env}.git)"
        elif [ -f "$dockerfile_dir/Dockerfile.${env}" ]; then
            dockerfile="$dockerfile_dir/Dockerfile.${env}"
            log_warn "Dockerfile.${env}.git non trouvé, utilisation de Dockerfile.${env}"
            log_info "Mode: Copie locale"
        fi
    else
        dockerfile="$dockerfile_dir/Dockerfile.${env}"
        log_info "Mode: Copie locale"
    fi

    if [ -z "$dockerfile" ] || [ ! -f "$dockerfile" ]; then
        log_error "Dockerfile non trouvé dans $dockerfile_dir/"
        log_info "Dockerfiles attendus: Dockerfile.${env} ou Dockerfile.${env}.git"
        exit 1
    fi

    # Vérifier si buildx est disponible pour multi-architecture
    local use_buildx=false
    local buildx_builder=""
    if docker buildx version &>/dev/null; then
        use_buildx=true

        # Créer ou utiliser un builder buildx si nécessaire
        buildx_builder="devops-builder"
        if ! docker buildx inspect "$buildx_builder" &>/dev/null; then
            log_info "Création du builder Docker Buildx: $buildx_builder"
            docker buildx create --name "$buildx_builder" --driver docker-container --bootstrap --use
        else
            log_info "Utilisation du builder existant: $buildx_builder"
            docker buildx use "$buildx_builder"
        fi

        log_info "Docker Buildx activé - Build pour architecture locale uniquement (pour éviter les erreurs)"
        log_info "Pour build multi-arch, utilisez: ./registry.sh build-push $env"
    else
        log_warn "Docker Buildx non disponible - Build pour l'architecture locale uniquement"
    fi

    # Arguments de build
    # Normaliser GIT_REPO pour éviter les formats SSH dans le Dockerfile (git@host:org/repo.git)
    local git_repo_build="$GIT_REPO"
    if echo "$git_repo_build" | grep -q "^git@"; then
        git_repo_build=$(echo "$git_repo_build" | sed -E 's|^git@([^:]+):|https://\1/|')
    fi
    local app_source_dir="${APP_SOURCE_DIR:-app}"
    local app_dest_dir="${APP_DEST_DIR:-app}"
    local requirements_path="${REQUIREMENTS_PATH:-requirements.txt}"
    local app_entrypoint="${APP_ENTRYPOINT:-app.main:app}"
    local workdir="${WORKDIR:-/app}"
    local app_python_path="${APP_PYTHON_PATH:-}"
    local build_args=(
        "--file" "$dockerfile"
        "--build-arg" "GIT_BRANCH=$git_branch"
        "--build-arg" "GIT_REPO=$git_repo_build"
        "--build-arg" "APP_SOURCE_DIR=$app_source_dir"
        "--build-arg" "APP_DEST_DIR=$app_dest_dir"
        "--build-arg" "REQUIREMENTS_PATH=$requirements_path"
        "--build-arg" "APP_ENTRYPOINT=$app_entrypoint"
        "--build-arg" "WORKDIR=$workdir"
        "--build-arg" "APP_PYTHON_PATH=$app_python_path"
        "--build-arg" "BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        "--build-arg" "VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    )

    # Ajouter le token GitHub/GitLab comme secret si disponible (sécurisé)
    local secret_args=()
    local secret_file=""
    local username_file=""

    if [ -n "$GITHUB_TOKEN" ]; then
        # Créer un fichier temporaire pour le secret token
        # Nettoyer le token (enlever espaces, newlines, retours chariot)
        local CLEAN_TOKEN=$(echo "$GITHUB_TOKEN" | tr -d ' \n\r\t')
        secret_file=$(mktemp)
        printf "%s" "$CLEAN_TOKEN" > "$secret_file"
        secret_args+=("--secret" "id=github_token,src=$secret_file")
        # Exposer aussi sous l'id git_token (utilisé par les Dockerfiles .git pour le clone)
        secret_args+=("--secret" "id=git_token,src=$secret_file")

        # Si c'est GitLab, ajouter aussi le username
        if echo "$GIT_REPO" | grep -q "gitlab.com"; then
            log_info "Détection GitLab - Configuration du username"

            # Utiliser GIT_USERNAME depuis .devops.yml
            if [ -n "$GIT_USERNAME" ]; then
                log_info "Username GitLab depuis .devops.yml: $GIT_USERNAME"
                local CLEAN_USERNAME=$(echo "$GIT_USERNAME" | tr -d ' \n\r\t')
                username_file=$(mktemp)
                printf "%s" "$CLEAN_USERNAME" > "$username_file"
                secret_args+=("--secret" "id=git_username,src=$username_file")
            else
                log_warn "GIT_USERNAME non défini dans .devops.yml"
                log_warn "Ajoutez 'git_username: votre-username' dans .devops.yml"
                log_warn "Le build peut échouer pour les repositories privés GitLab"
            fi
        fi
    fi

    # No cache
    if [ "$no_cache" == "true" ]; then
        build_args+=("--no-cache")
    fi

    # Build
    log_info "Démarrage du build..."
    print_separator

    if [ "$use_buildx" == "true" ]; then
        # Build avec buildx pour l'architecture locale (évite l'erreur manifest lists)
        # Note: --load ne supporte qu'une seule plateforme à la fois
        docker buildx build \
            --tag "$full_image_name" \
            --tag "$full_image_latest" \
            "${build_args[@]}" \
            "${secret_args[@]}" \
            --load \
            .
    else
        # Build classique
        docker build \
            --tag "$full_image_name" \
            --tag "$full_image_latest" \
            "${build_args[@]}" \
            "${secret_args[@]}" \
            .
    fi

    # Nettoyer les fichiers de secrets temporaires
    if [ -n "$secret_file" ] && [ -f "$secret_file" ]; then
        rm -f "$secret_file"
    fi
    if [ -n "$username_file" ] && [ -f "$username_file" ]; then
        rm -f "$username_file"
    fi

    print_separator
    log_success "Image construite avec succès!"
    log_success "Tags: $version_tag, latest"

    # Afficher la taille de l'image
    log_info "Taille de l'image:"
    docker images "$full_image_name" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"
}

# Push une image vers le registry
cmd_push() {
    local env=$1
    local version_tag=${2:-latest}

    log_header "PUSH IMAGE - Environnement: $env"

    registry_login

    local full_image_name=$(get_full_image_name "$env" "$version_tag")
    local full_image_latest=$(get_full_image_name "$env" "latest")

    log_info "Push de l'image: $full_image_name"
    docker push "$full_image_name"

    if [ "$version_tag" != "latest" ]; then
        log_info "Push de l'image: $full_image_latest"
        docker push "$full_image_latest"
    fi

    log_success "Images envoyées au registry"
    log_info "Pour déployer: docker pull $full_image_name"
}

# Pull une image depuis le registry
cmd_pull() {
    local env=$1
    local version_tag=${2:-latest}

    log_header "PULL IMAGE - Environnement: $env"

    registry_login

    local full_image_name=$(get_full_image_name "$env" "$version_tag")

    log_info "Pull de l'image: $full_image_name"
    docker pull "$full_image_name"

    log_success "Image téléchargée"
}

# Build multi-architecture et push directement (sans load local)
cmd_build_push_multiarch() {
    local env=$1
    local version_tag=${2:-$(generate_version_tag "$env")}
    local no_cache=${3:-false}
    local use_git=${4:-true}

    log_header "BUILD + PUSH MULTI-ARCH - Environnement: $env"

    # Vérifier que buildx est disponible
    if ! docker buildx version &>/dev/null; then
        log_error "Docker Buildx est requis pour les builds multi-architecture"
        log_info "Installez Docker Buildx: https://docs.docker.com/buildx/working-with-buildx/"
        exit 1
    fi

    registry_login

    # Déterminer le mode build (clone ou local)
    local build_mode="local"
    if [ "$use_git" == "true" ]; then
        build_mode="clone"
    fi

    # Obtenir la branche Git selon l'environnement
    local git_branch
    case "$env" in
        dev)     git_branch="${DEV_BRANCH:-dev}" ;;
        staging) git_branch="${STAGING_BRANCH:-staging}" ;;
        prod)    git_branch="${PROD_BRANCH:-main}" ;;
        *)       git_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')" ;;
    esac

    # Déterminer le Dockerfile selon mode build et environnement
    local dockerfile
    local dockerfile_dir="${DEPLOYMENT_DIR:-deployment}/docker"

    if [ "$use_git" == "true" ]; then
        # Essayer d'abord la variante .git, sinon utiliser le Dockerfile normal
        if [ -f "$dockerfile_dir/Dockerfile.${env}.git" ]; then
            dockerfile="$dockerfile_dir/Dockerfile.${env}.git"
        elif [ -f "$dockerfile_dir/Dockerfile.${env}" ]; then
            dockerfile="$dockerfile_dir/Dockerfile.${env}"
            log_warn "Dockerfile.${env}.git non trouvé, utilisation de Dockerfile.${env}"
        fi
    else
        dockerfile="$dockerfile_dir/Dockerfile.${env}"
    fi

    # Vérifier que le Dockerfile existe
    if [ -z "$dockerfile" ] || [ ! -f "$dockerfile" ]; then
        log_error "Dockerfile non trouvé dans $dockerfile_dir/"
        log_info "Dockerfiles attendus: Dockerfile.${env} ou Dockerfile.${env}.git"
        exit 1
    fi

    local full_image_name=$(get_full_image_name "$env" "$version_tag")
    local full_image_latest=$(get_full_image_name "$env" "latest")

    log_info "Image: $full_image_name"
    log_info "Branche Git: $git_branch"
    log_info "Tag: $version_tag"
    log_info "Mode: Build multi-architecture (linux/amd64,linux/arm64)"
    log_info "Push direct vers registry (pas de chargement local)"

    # Créer ou utiliser un builder buildx
    local buildx_builder="devops-builder"
    if ! docker buildx inspect "$buildx_builder" &>/dev/null; then
        log_info "Création du builder Docker Buildx: $buildx_builder"
        docker buildx create --name "$buildx_builder" --driver docker-container --bootstrap --use
    else
        log_info "Utilisation du builder existant: $buildx_builder"
        docker buildx use "$buildx_builder"
    fi

    # Arguments de build
    local git_repo_build="$GIT_REPO"
    if echo "$git_repo_build" | grep -q "^git@"; then
        git_repo_build=$(echo "$git_repo_build" | sed -E 's|^git@([^:]+):|https://\1/|')
    fi
    local app_source_dir="${APP_SOURCE_DIR:-app}"
    local app_dest_dir="${APP_DEST_DIR:-app}"
    local requirements_path="${REQUIREMENTS_PATH:-requirements.txt}"
    local app_entrypoint="${APP_ENTRYPOINT:-app.main:app}"
    local workdir="${WORKDIR:-/app}"
    local app_python_path="${APP_PYTHON_PATH:-}"
    local build_args=(
        "--file" "$dockerfile"
        "--platform" "linux/amd64,linux/arm64"
        "--build-arg" "GIT_BRANCH=$git_branch"
        "--build-arg" "GIT_REPO=$git_repo_build"
        "--build-arg" "APP_SOURCE_DIR=$app_source_dir"
        "--build-arg" "APP_DEST_DIR=$app_dest_dir"
        "--build-arg" "REQUIREMENTS_PATH=$requirements_path"
        "--build-arg" "APP_ENTRYPOINT=$app_entrypoint"
        "--build-arg" "WORKDIR=$workdir"
        "--build-arg" "APP_PYTHON_PATH=$app_python_path"
        "--build-arg" "BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        "--build-arg" "VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
        "--tag" "$full_image_name"
        "--tag" "$full_image_latest"
        "--push"  # Push directement sans charger localement
    )

    # Ajouter le token GitHub/GitLab comme secret si disponible (sécurisé)
    local secret_args=()
    local secret_file=""
    local username_file=""

    if [ -n "$GITHUB_TOKEN" ]; then
        # Créer un fichier temporaire pour le secret token
        # Nettoyer le token (enlever espaces, newlines, retours chariot)
        local CLEAN_TOKEN=$(echo "$GITHUB_TOKEN" | tr -d ' \n\r\t')
        secret_file=$(mktemp)
        printf "%s" "$CLEAN_TOKEN" > "$secret_file"
        secret_args+=("--secret" "id=github_token,src=$secret_file")
        # Exposer aussi sous l'id git_token (utilisé par les Dockerfiles .git pour le clone)
        secret_args+=("--secret" "id=git_token,src=$secret_file")

        # Si c'est GitLab, ajouter aussi le username
        if echo "$GIT_REPO" | grep -q "gitlab.com"; then
            log_info "Détection GitLab - Configuration du username"

            # Utiliser GIT_USERNAME depuis .devops.yml
            if [ -n "$GIT_USERNAME" ]; then
                log_info "Username GitLab depuis .devops.yml: $GIT_USERNAME"
                local CLEAN_USERNAME=$(echo "$GIT_USERNAME" | tr -d ' \n\r\t')
                username_file=$(mktemp)
                printf "%s" "$CLEAN_USERNAME" > "$username_file"
                secret_args+=("--secret" "id=git_username,src=$username_file")
            else
                log_warn "GIT_USERNAME non défini dans .devops.yml"
                log_warn "Ajoutez 'git_username: votre-username' dans .devops.yml"
                log_warn "Le build peut échouer pour les repositories privés GitLab"
            fi
        fi
    fi

    # No cache
    if [ "$no_cache" == "true" ]; then
        build_args+=("--no-cache")
    fi

    # Build et push
    log_info "Démarrage du build multi-arch et push..."
    print_separator

    docker buildx build "${build_args[@]}" "${secret_args[@]}" .

    # Nettoyer les fichiers de secrets temporaires
    if [ -n "$secret_file" ] && [ -f "$secret_file" ]; then
        rm -f "$secret_file"
    fi
    if [ -n "$username_file" ] && [ -f "$username_file" ]; then
        rm -f "$username_file"
    fi
    print_separator
    log_success "Image multi-architecture construite et pushée avec succès!"
    log_success "Tags: $version_tag, latest"
    log_success "Architectures: linux/amd64, linux/arm64"
}

# Build et push en une seule commande
cmd_release() {
    local env=$1
    local version_tag=${2:-$(generate_version_tag "$env")}
    local no_cache=${3:-false}
    local use_git=${4:-true}

    log_header "RELEASE - Environnement: $env"

    # Confirmation pour la production
    if [ "$env" == "prod" ]; then
        read -p "Vous êtes sur le point de créer une release PRODUCTION. Continuer ? (yes/n): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Release annulée"
            exit 0
        fi
    fi

    # Vérifier si buildx est disponible pour multi-arch
    if docker buildx version &>/dev/null; then
        log_info "Docker Buildx détecté - Build multi-architecture (linux/amd64,linux/arm64)"
        cmd_build_push_multiarch "$env" "$version_tag" "$no_cache" "$use_git"
    else
        log_warn "Docker Buildx non disponible - Build pour architecture locale uniquement"
        # Build local puis push
        cmd_build "$env" "$version_tag" "$no_cache" "$use_git"
        cmd_push "$env" "$version_tag"
    fi

    log_success "Release $version_tag créée avec succès!"
}

# Lister les images disponibles
cmd_list() {
    local env=${1:-}

    log_header "IMAGES LOCALES"

    if [ -n "$env" ]; then
        local pattern=$(get_full_image_name "$env" "*" | sed 's/:.*$//')
        docker images "$pattern" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    else
        docker images "${REGISTRY_USERNAME}/${IMAGE_NAME}" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    fi
}

# Lister les tags disponibles dans le registry
cmd_list_remote() {
    local env=$1

    log_header "TAGS DISPONIBLES DANS LE REGISTRY - $env"

    registry_login

    log_info "Interrogation du registry..."

    case "$REGISTRY_TYPE" in
        dockerhub)
            local api_url="https://registry.hub.docker.com/v2/repositories/${REGISTRY_USERNAME}/${IMAGE_NAME}/tags"
            local tags=$(curl -s "$api_url" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep "^${env}-")

            if [ -z "$tags" ]; then
                log_warn "Aucun tag trouvé pour l'environnement $env"
            else
                echo "$tags" | while read tag; do
                    echo "  - $tag"
                done
            fi
            ;;
        gitlab)
            log_warn "Listing distant pour GitLab Registry nécessite l'API GitLab"
            log_info "Utilisez: curl --header 'PRIVATE-TOKEN: <your_token>' https://gitlab.com/api/v4/projects/<project_id>/registry/repositories/<repo_id>/tags"
            ;;
        github)
            log_warn "Listing distant pour GitHub Container Registry nécessite l'API GitHub"
            log_info "Utilisez: gh api /user/packages/container/${IMAGE_NAME}/versions"
            ;;
        *)
            log_warn "Listing distant non supporté pour ce registry"
            ;;
    esac
}

# Nettoyer les images locales
cmd_clean() {
    local env=${1:-}
    local keep_latest=${2:-true}

    log_header "NETTOYAGE DES IMAGES LOCALES"

    read -p "Supprimer les images locales ? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        log_info "Nettoyage annulé"
        exit 0
    fi

    if [ -n "$env" ]; then
        local pattern=$(get_full_image_name "$env" "*" | sed 's/:.*$//')

        if [ "$keep_latest" == "true" ]; then
            log_info "Suppression des images $pattern (sauf latest)..."
            docker images "$pattern" --format "{{.Repository}}:{{.Tag}}" | grep -v "latest" | xargs -r docker rmi || true
        else
            log_info "Suppression de toutes les images $pattern..."
            docker rmi $(docker images "$pattern" -q) || true
        fi
    else
        log_info "Suppression des images dangling..."
        docker image prune -f
    fi

    log_success "Nettoyage terminé"
}

# Afficher les informations d'une image
cmd_inspect() {
    local env=$1
    local version_tag=${2:-latest}

    log_header "INSPECTION IMAGE - $env:$version_tag"

    local full_image_name=$(get_full_image_name "$env" "$version_tag")

    log_info "Image: $full_image_name"
    print_separator

    docker inspect "$full_image_name" --format '
Image ID: {{.Id}}
Created: {{.Created}}
Size: {{.Size}} bytes
Architecture: {{.Config.Architecture}}
OS: {{.Os}}

Environment:
{{range .Config.Env}}  - {{.}}
{{end}}

Labels:
{{range $k, $v := .Config.Labels}}  - {{$k}}: {{$v}}
{{end}}
'
}

# Nettoyer les builders Docker Buildx
cmd_cleanup_buildx() {
    log_header "NETTOYAGE DES BUILDERS BUILDX"

    log_info "Liste des builders existants:"
    docker buildx ls

    echo ""
    read -p "Voulez-vous supprimer le builder 'devops-builder'? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        log_info "Nettoyage annulé"
        return 0
    fi

    if docker buildx inspect devops-builder &>/dev/null; then
        log_info "Suppression du builder 'devops-builder'..."
        docker buildx rm devops-builder
        log_success "Builder 'devops-builder' supprimé"
    else
        log_warn "Builder 'devops-builder' introuvable"
    fi

    echo ""
    read -p "Voulez-vous nettoyer tous les caches de build? (y/n): " confirm_prune
    if [ "$confirm_prune" == "y" ]; then
        log_info "Nettoyage du cache de build..."
        docker buildx prune -f
        log_success "Cache de build nettoyé"
    fi

    log_success "Nettoyage terminé"
}

# ============================================================================
# MODE INTERACTIF
# ============================================================================

# Afficher le menu principal
show_interactive_menu() {
    clear
    log_header "${PROJECT_NAME:-DevOps} - Docker Registry Management"

    if [ -n "$CURRENT_PROFILE" ]; then
        echo -e "${GREEN}Profil actif:${NC} $CURRENT_PROFILE"
        echo -e "${GREEN}Registry:${NC} $(get_registry_description "$REGISTRY_TYPE")"
        echo -e "${GREEN}Image:${NC} ${REGISTRY_USERNAME}/${IMAGE_NAME}"
    else
        echo -e "${YELLOW}Aucun profil chargé${NC}"
    fi

    echo ""
    print_separator
    echo -e "${CYAN}GESTION DES PROFILS${NC}"
    echo "  1) Créer un nouveau profil"
    echo "  2) Charger un profil existant"
    echo "  3) Lister les profils"
    echo "  4) Afficher le profil actuel"
    echo "  5) Supprimer un profil"
    echo ""
    print_separator
    echo -e "${CYAN}OPÉRATIONS DOCKER${NC}"
    echo "  6) Build une image"
    echo "  7) Push une image vers le registry"
    echo "  8) Pull une image depuis le registry"
    echo "  9) Release (Build + Push)"
    echo " 10) Lister les images locales"
    echo " 11) Lister les tags dans le registry"
    echo " 12) Nettoyer les images locales"
    echo " 13) Inspecter une image"
    echo " 14) Se connecter au registry"
    echo -e " 15) ${YELLOW}Build + Push Multi-Architecture (amd64+arm64)${NC}"
    echo " 16) Nettoyer les builders Buildx"
    echo ""
    print_separator
    echo "  0) Quitter"
    print_separator
    echo ""
}

# Menu pour choisir l'environnement
choose_environment() {
    echo "" >&2
    echo -e "${CYAN}Environnements disponibles:${NC}" >&2
    echo -e "  ${CYAN}1)${NC} ${WHITE}dev${NC}     - Environnement de développement" >&2
    echo -e "  ${CYAN}2)${NC} ${WHITE}staging${NC} - Environnement de pré-production" >&2
    echo -e "  ${CYAN}3)${NC} ${WHITE}prod${NC}    - Environnement de production" >&2
    echo "" >&2
    read -p "Choisissez l'environnement (1=dev, 2=staging, 3=prod): " env_choice

    case "$env_choice" in
        1) echo "dev" ;;
        2) echo "staging" ;;
        3) echo "prod" ;;
        *)
            log_error "Choix invalide. Utilisez 1 pour dev, 2 pour staging ou 3 pour prod"
            return 1
            ;;
    esac
}

# Vérifier qu'un profil est chargé
ensure_profile_loaded() {
    if [ -z "$CURRENT_PROFILE" ]; then
        if [ -n "$REGISTRY_USERNAME" ] && [ -n "$IMAGE_NAME" ]; then
            CURRENT_PROFILE="devops-yml"
            log_warn "Aucun profil chargé - utilisation de la configuration .devops.yml (sans credentials)"
            return 0
        fi
        log_error "Aucun profil chargé. Veuillez charger ou créer un profil."
        echo ""
        read -p "Appuyez sur Entrée pour continuer..."
        return 1
    fi
    return 0
}

# Mode interactif principal
interactive_mode() {
    while true; do
        show_interactive_menu
        read -p "Votre choix: " choice

        case "$choice" in
            1)
                profile_create
                echo ""
                read -p "Voulez-vous charger ce profil maintenant? (y/n): " load_choice
                if [ "$load_choice" == "y" ]; then
                    read -p "Nom du profil: " profile_name
                    profile_load "$profile_name"
                fi
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            2)
                profile_load
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            3)
                profile_list
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            4)
                profile_show
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            5)
                profile_delete
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            6)
                ensure_profile_loaded || continue
                env=$(choose_environment) || continue
                echo ""

                # Proposer le versioning sémantique
                version=$(choose_version "$env") || continue

                # Construire le tag complet (ajouter env- si nécessaire)
                if [ "$version" == "latest" ]; then
                    version="${env}-latest"
                elif [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                    version="${env}-${version}"
                fi
                # Sinon, version contient déjà le format complet (date+hash)

                echo ""
                read -p "Build sans cache? (y/n): " no_cache_input
                no_cache=$([ "$no_cache_input" == "y" ] && echo "true" || echo "false")
                echo ""
                read -p "Utiliser Git clone? (y/n): " use_git_input
                use_git=$([ "$use_git_input" != "n" ] && echo "true" || echo "false")

                cmd_build "$env" "$version" "$no_cache" "$use_git"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            7)
                ensure_profile_loaded || continue
                env=$(choose_environment) || continue
                echo ""
                read -p "Version tag (défaut: latest): " version
                version=${version:-latest}
                cmd_push "$env" "$version"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            8)
                ensure_profile_loaded || continue
                env=$(choose_environment) || continue
                echo ""
                read -p "Version tag (défaut: latest): " version
                version=${version:-latest}
                cmd_pull "$env" "$version"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            9)
                ensure_profile_loaded || continue
                env=$(choose_environment) || continue
                echo ""

                # Proposer le versioning sémantique
                version=$(choose_version "$env") || continue

                # Construire le tag complet (ajouter env- si nécessaire)
                if [ "$version" == "latest" ]; then
                    version="${env}-latest"
                elif [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                    version="${env}-${version}"
                fi
                # Sinon, version contient déjà le format complet (date+hash)

                echo ""
                read -p "Build sans cache? (y/n): " no_cache_input
                no_cache=$([ "$no_cache_input" == "y" ] && echo "true" || echo "false")
                echo ""
                read -p "Utiliser Git clone? (y/n): " use_git_input
                use_git=$([ "$use_git_input" != "n" ] && echo "true" || echo "false")

                cmd_release "$env" "$version" "$no_cache" "$use_git"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            10)
                ensure_profile_loaded || continue
                echo ""
                read -p "Filtrer par environnement? (dev/prod/laisser vide): " env
                cmd_list "$env"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            11)
                ensure_profile_loaded || continue
                env=$(choose_environment) || continue
                cmd_list_remote "$env"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            12)
                ensure_profile_loaded || continue
                echo ""
                echo -e "${CYAN}Environnement à nettoyer:${NC}"
                echo "  1) dev"
                echo "  2) staging"
                echo "  3) prod"
                echo "  4) Tous (pas de filtre)"
                echo ""
                read -p "Choisissez (1-4): " env_filter_choice

                case "$env_filter_choice" in
                    1) env="dev" ;;
                    2) env="staging" ;;
                    3) env="prod" ;;
                    4) env="" ;;
                    *)
                        log_error "Choix invalide"
                        read -p "Appuyez sur Entrée pour continuer..."
                        continue
                        ;;
                esac

                echo ""
                read -p "Garder les tags 'latest'? (y/n): " keep_latest_input
                keep_latest=$([ "$keep_latest_input" != "n" ] && echo "true" || echo "false")
                cmd_clean "$env" "$keep_latest"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            13)
                ensure_profile_loaded || continue
                env=$(choose_environment) || continue

                echo ""
                echo -e "${CYAN}Inspecter une image:${NC}"
                print_separator

                echo ""
                read -p "Version tag (défaut: latest): " version
                version=${version:-latest}

                echo ""
                print_separator
                cmd_inspect "$env" "$version"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            14)
                ensure_profile_loaded || continue
                registry_login
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            15)
                ensure_profile_loaded || continue
                env=$(choose_environment) || continue
                echo ""

                # Proposer le versioning sémantique
                version=$(choose_version "$env") || continue

                # Construire le tag complet (ajouter env- si nécessaire)
                if [ "$version" == "latest" ]; then
                    version="${env}-latest"
                elif [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                    version="${env}-${version}"
                fi
                # Sinon, version contient déjà le format complet (date+hash)

                echo ""
                read -p "Build sans cache? (y/n): " no_cache_input
                no_cache=$([ "$no_cache_input" == "y" ] && echo "true" || echo "false")
                echo ""
                read -p "Utiliser Git clone? (y/n): " use_git_input
                use_git=$([ "$use_git_input" != "n" ] && echo "true" || echo "false")

                cmd_build_push_multiarch "$env" "$version" "$no_cache" "$use_git"
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            16)
                cmd_cleanup_buildx
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            0)
                log_info "Au revoir!"
                exit 0
                ;;
            *)
                log_error "Choix invalide"
                sleep 1
                ;;
        esac
    done
}

# ============================================================================
# AIDE
# ============================================================================

show_help() {
    cat << EOF
${WHITE}${PROJECT_NAME:-DevOps} - Docker Registry Management (Multi-Registry Support)${NC}

${CYAN}USAGE:${NC}
    ./registry.sh                          Mode interactif
    ./registry.sh interactive              Mode interactif
    ./registry.sh <command> [args]         Mode CLI

${CYAN}GESTION DES PROFILS:${NC}
    profile create [name]              Créer un nouveau profil
    profile load [name]                Charger un profil existant
    profile list                       Lister tous les profils
    profile show                       Afficher le profil actuel
    profile delete [name]              Supprimer un profil

${CYAN}BUILD & RELEASE:${NC}
    build <env> [version] [options]            Construire une image (architecture locale)
        --no-cache                             Construire sans cache
        --local                                Utiliser les fichiers locaux (pas Git)
        --profile <name>                       Utiliser un profil spécifique

    build-push-multiarch <env> [version]       Build multi-arch (amd64+arm64) et push
        --no-cache                             Construire sans cache
        --local                                Utiliser les fichiers locaux (pas Git)

    push <env> [version]                       Envoyer l'image vers le registry
    pull <env> [version]                       Télécharger l'image depuis le registry
    release <env> [version] [options]          Build + Push en une commande (arch locale)

${CYAN}GESTION:${NC}
    list [env]                         Lister les images locales
    list-remote <env>                  Lister les tags dans le registry
    clean [env] [--all]                Nettoyer les images locales
    inspect <env> [version]            Inspecter une image
    login                              Se connecter au registry
    cleanup-buildx                     Nettoyer les builders Docker Buildx

${CYAN}REGISTRIES SUPPORTÉS:${NC}
    - Docker Hub (docker.io)
    - GitLab Container Registry (registry.gitlab.com)
    - GitHub Container Registry (ghcr.io)
    - Registries Docker personnalisés

${CYAN}EXEMPLES:${NC}

    ${WHITE}Mode interactif:${NC}
    ./registry.sh
    ./registry.sh interactive

    ${WHITE}Créer un profil:${NC}
    ./registry.sh profile create dockerhub-prod
    ./registry.sh profile create gitlab-dev

    ${WHITE}Build avec un profil:${NC}
    ./registry.sh build dev --profile dockerhub-prod
    ./registry.sh release prod v1.2.3 --profile gitlab-dev

    ${WHITE}Lister les profils:${NC}
    ./registry.sh profile list
    ./registry.sh profile show

    ${WHITE}Opérations classiques:${NC}
    ./registry.sh build dev
    ./registry.sh release prod v1.2.3 --no-cache
    ./registry.sh list dev
    ./registry.sh pull prod v1.2.3

${CYAN}CONFIGURATION:${NC}
    Les profils sont stockés dans: deployment/scripts/.registry-profiles/

    Format d'un profil (.env):
    REGISTRY_TYPE=dockerhub|gitlab|github|custom
    REGISTRY_URL=docker.io
    REGISTRY_USERNAME=username
    REGISTRY_TOKEN=token_or_password
    IMAGE_NAME=my-project
    GIT_REPO=https://github.com/user/repo.git
    GITHUB_TOKEN=ghp_xxx
    DEV_BRANCH=develop
    PROD_BRANCH=main

${CYAN}ENVIRONNEMENTS:${NC}
    dev     Environnement de développement
    prod    Environnement de production

${CYAN}MIGRATION DEPUIS L'ANCIENNE VERSION:${NC}
    L'ancien fichier .env.registry est toujours supporté.
    Pour migrer vers le système de profils:
    1. ./registry.sh profile create mon-profil
    2. Configurer le nouveau profil
    3. Optionnel: supprimer .env.registry

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Si aucun argument, essayer de charger la config puis lancer le mode interactif
    if [ $# -eq 0 ]; then
        load_config || log_warn "Aucune configuration trouvée, veuillez créer un profil"
        interactive_mode
        exit 0
    fi

    COMMAND=$1
    shift

    # Commande interactive explicite
    if [ "$COMMAND" == "interactive" ]; then
        load_config || log_warn "Aucune configuration trouvée, veuillez créer un profil"
        interactive_mode
        exit 0
    fi

    # Gestion des profils
    if [ "$COMMAND" == "profile" ]; then
        PROFILE_CMD=${1:-}
        shift 2>/dev/null || true

        case "$PROFILE_CMD" in
            create)
                profile_create "$@"
                ;;
            load)
                profile_load "$@"
                save_last_profile
                ;;
            list)
                profile_list
                ;;
            show)
                profile_show
                ;;
            delete)
                profile_delete "$@"
                ;;
            *)
                log_error "Commande de profil inconnue: $PROFILE_CMD"
                echo "Commandes disponibles: create, load, list, show, delete"
                exit 1
                ;;
        esac
        exit 0
    fi

    # Commandes qui ne nécessitent pas de profil
    if [ "$COMMAND" == "help" ] || [ "$COMMAND" == "--help" ] || [ "$COMMAND" == "-h" ]; then
        show_help
        exit 0
    fi

    if [ "$COMMAND" == "cleanup-buildx" ]; then
        cmd_cleanup_buildx
        exit 0
    fi

    # Pour les autres commandes, charger la configuration
    # Vérifier si --profile est spécifié
    PROFILE_ARG=""
    for arg in "$@"; do
        if [ "$arg" == "--profile" ]; then
            shift
            PROFILE_ARG="$1"
            shift
            break
        fi
    done

    if [ -n "$PROFILE_ARG" ]; then
        profile_load "$PROFILE_ARG"
    else
        if ! load_config; then
            log_error "Aucune configuration trouvée"
            log_info "Créez un profil avec: ./registry.sh profile create <nom>"
            exit 1
        fi
    fi

    save_last_profile

    # Exécuter la commande
    case "$COMMAND" in
        build)
            ENV=${1:-}
            VERSION=${2:-}
            NO_CACHE=false
            USE_GIT=true
            shift 2 2>/dev/null || shift 1 2>/dev/null || true
            while [ $# -gt 0 ]; do
                case "$1" in
                    --no-cache) NO_CACHE=true ;;
                    --local) USE_GIT=false ;;
                    --profile) shift ;; # Déjà traité
                esac
                shift
            done
            [ -z "$VERSION" ] && VERSION=$(generate_version_tag "$ENV")
            cmd_build "$ENV" "$VERSION" "$NO_CACHE" "$USE_GIT"
            ;;
        push)
            cmd_push "${1:-}" "${2:-latest}"
            ;;
        pull)
            cmd_pull "${1:-}" "${2:-latest}"
            ;;
        release)
            ENV=${1:-}
            VERSION=${2:-}
            NO_CACHE=false
            USE_GIT=true
            shift 2 2>/dev/null || shift 1 2>/dev/null || true
            while [ $# -gt 0 ]; do
                case "$1" in
                    --no-cache) NO_CACHE=true ;;
                    --local) USE_GIT=false ;;
                    --profile) shift ;; # Déjà traité
                esac
                shift
            done
            [ -z "$VERSION" ] && VERSION=$(generate_version_tag "$ENV")
            cmd_release "$ENV" "$VERSION" "$NO_CACHE" "$USE_GIT"
            ;;
        build-push-multiarch|multiarch)
            ENV=${1:-}
            VERSION=${2:-}
            NO_CACHE=false
            USE_GIT=true
            shift 2 2>/dev/null || shift 1 2>/dev/null || true
            while [ $# -gt 0 ]; do
                case "$1" in
                    --no-cache) NO_CACHE=true ;;
                    --local) USE_GIT=false ;;
                    --profile) shift ;; # Déjà traité
                esac
                shift
            done
            [ -z "$ENV" ] && { log_error "Environnement requis"; exit 1; }
            [ -z "$VERSION" ] && VERSION=$(generate_version_tag "$ENV")
            cmd_build_push_multiarch "$ENV" "$VERSION" "$NO_CACHE" "$USE_GIT"
            ;;
        list)
            cmd_list "${1:-}"
            ;;
        list-remote|remote)
            cmd_list_remote "${1:-}"
            ;;
        clean)
            ENV=${1:-}
            KEEP_LATEST=true
            shift 2>/dev/null || true
            while [ $# -gt 0 ]; do
                case "$1" in
                    --all) KEEP_LATEST=false ;;
                esac
                shift
            done
            cmd_clean "$ENV" "$KEEP_LATEST"
            ;;
        inspect)
            cmd_inspect "${1:-}" "${2:-latest}"
            ;;
        login)
            registry_login
            ;;
        *)
            log_error "Commande inconnue: $COMMAND"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
