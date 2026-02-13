#!/bin/bash

# ============================================================================
# DevOps - Script de déploiement depuis Registry
# Déploiement des images Docker depuis Docker Hub ou autre registry
# ============================================================================
#
# USAGE:
#   ./deploy-registry.sh deploy <env> [tag]       Déployer une image
#   ./deploy-registry.sh list-tags <env>          Lister les tags disponibles
#   ./deploy-registry.sh pull <env> [tag]         Télécharger une image
#   ./deploy-registry.sh status <env>             Status des conteneurs
#   ./deploy-registry.sh logs <env> [service]     Voir les logs
#   ./deploy-registry.sh stop <env>               Arrêter les services
#   ./deploy-registry.sh restart <env>            Redémarrer les services
#   ./deploy-registry.sh superset-import <env>    Importer les assets Superset
#
# EXAMPLES:
#   ./deploy-registry.sh deploy dev
#   ./deploy-registry.sh deploy dev dev-v20251216-163525-3be7822
#   ./deploy-registry.sh deploy prod prod-latest
#   ./deploy-registry.sh list-tags dev
#   ./deploy-registry.sh logs dev ${IMAGE_NAME:-api}
#
# ============================================================================

set -e

# ============================================================================
# COULEURS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

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

# Charger la configuration depuis .devops.yml (définit PROJECT_ROOT, PROJECT_NAME, etc.)
# Ne pas échouer si le fichier n'existe pas (package minimal sur serveur)
source "$SCRIPT_DIR/config-loader.sh"
load_devops_config || true

# Si PROJECT_ROOT n'est pas défini (ancien comportement), utiliser ../..
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
fi

# Fallback package minimal: si .env.registry est à la racine du script,
# forcer PROJECT_ROOT sur ce dossier (évite /srv/home/.env.*).
if [ -f "$SCRIPT_DIR/.env.registry" ] && [ ! -f "$PROJECT_ROOT/.env.registry" ]; then
    PROJECT_ROOT="$SCRIPT_DIR"
    export PROJECT_ROOT
fi

# DEPLOYMENT_DIR relatif au projet
DEPLOYMENT_DIR="${DEPLOYMENT_DIR:-$PROJECT_ROOT/deployment}"
# Fallback: package minimal (fichiers à la racine)
if [ ! -d "$DEPLOYMENT_DIR" ] && [ -f "$PROJECT_ROOT/.env.registry" ]; then
    DEPLOYMENT_DIR="$PROJECT_ROOT"
fi

# Se placer dans le répertoire du projet
cd "$PROJECT_ROOT"

# Debug: afficher les chemins au démarrage (décommentez pour diagnostiquer)
# echo "DEBUG: SCRIPT_DIR=$SCRIPT_DIR" >&2
# echo "DEBUG: DEPLOYMENT_DIR=$DEPLOYMENT_DIR" >&2
# echo "DEBUG: PROJECT_ROOT=$PROJECT_ROOT" >&2

# Nom du projet Docker Compose (chargé depuis .devops.yml ou fallback)
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-${PROJECT_NAME:-app}}"

# Dossier des profils registry (partagé avec registry.sh)
PROFILES_DIR="$SCRIPT_DIR/.registry-profiles"
CURRENT_PROFILE=""
LAST_PROFILE_FILE="$PROFILES_DIR/.current"

# Chiffrer un profil
encrypt_profile() {
    local profile_name=$1
    local profile_file="$PROFILES_DIR/${profile_name}.env"

    # Vérifier si env-encrypt.py existe
    local encrypt_script="$SCRIPT_DIR/env-encrypt.py"
    if [ ! -f "$encrypt_script" ]; then
        log_warn "Script de chiffrement non trouvé, profil conservé en clair"
        return 1
    fi

    # Vérifier si python3 ou venv existe
    local python_cmd="python3"
    if [ -f "$DEPLOYMENT_DIR/../.venv/bin/python3" ]; then
        python_cmd="$DEPLOYMENT_DIR/../.venv/bin/python3"
    fi

    # Chiffrer le profil
    log_info "Chiffrement du profil..."
    if $python_cmd "$encrypt_script" encrypt "$profile_file" >/dev/null 2>&1; then
        # Supprimer la version non chiffrée
        rm -f "$profile_file"
        log_success "Profil chiffré avec succès"
        return 0
    else
        log_warn "Échec du chiffrement, profil conservé en clair"
        return 1
    fi
}

# Déchiffrer et charger un profil
load_encrypted_profile() {
    local profile_name=$1
    local encrypted_file="$PROFILES_DIR/${profile_name}.env.encrypted"

    # Vérifier si le fichier chiffré existe
    if [ ! -f "$encrypted_file" ]; then
        return 1
    fi

    # Vérifier si env-encrypt.py existe
    local encrypt_script="$SCRIPT_DIR/env-encrypt.py"
    if [ ! -f "$encrypt_script" ]; then
        log_error "Script de déchiffrement non trouvé"
        return 1
    fi

    # Vérifier si python3 ou venv existe
    local python_cmd="python3"
    if [ -f "$DEPLOYMENT_DIR/../.venv/bin/python3" ]; then
        python_cmd="$DEPLOYMENT_DIR/../.venv/bin/python3"
    fi

    # Déchiffrer le profil dans un fichier temporaire
    local temp_file="/tmp/.registry-profile-$$"
    if $python_cmd "$encrypt_script" decrypt "$encrypted_file" >/dev/null 2>&1; then
        # Le fichier déchiffré est créé sans .encrypted
        local decrypted_file="$PROFILES_DIR/${profile_name}.env"
        if [ -f "$decrypted_file" ]; then
            # Charger les variables
            source "$decrypted_file"
            # Supprimer le fichier déchiffré temporaire
            rm -f "$decrypted_file"
            return 0
        fi
    fi

    rm -f "$temp_file"
    return 1
}

# Charger uniquement les credentials depuis un fichier de profil
# Ne PAS écraser les valeurs de .devops.yml (REGISTRY_URL, REGISTRY_USERNAME, IMAGE_NAME, etc.)
load_credentials_from_file() {
    local profile_file=$1

    if [ ! -f "$profile_file" ]; then
        return 1
    fi

    # Charger UNIQUEMENT les credentials REGISTRY
    # GITHUB_TOKEN vient de .devops.yml (spécifique au projet Git)
    local temp_type=$(grep "^REGISTRY_TYPE=" "$profile_file" 2>/dev/null | cut -d'=' -f2)
    local temp_token=$(grep "^REGISTRY_TOKEN=" "$profile_file" 2>/dev/null | cut -d'=' -f2)
    local temp_password=$(grep "^REGISTRY_PASSWORD=" "$profile_file" 2>/dev/null | cut -d'=' -f2)

    # Appliquer les credentials REGISTRY uniquement
    [ -n "$temp_type" ] && REGISTRY_TYPE="$temp_type"
    [ -n "$temp_token" ] && REGISTRY_TOKEN="$temp_token"
    [ -n "$temp_password" ] && REGISTRY_PASSWORD="$temp_password"
    # Note: GITHUB_TOKEN n'est PAS chargé depuis le profil (vient de .devops.yml)

    return 0
}

# Charger le dernier profil utilisé si disponible
load_profile() {
    # Essayer de charger depuis le fichier .current
    if [ -f "$LAST_PROFILE_FILE" ]; then
        local last_profile=$(cat "$LAST_PROFILE_FILE")

        # Essayer d'abord de charger un profil chiffré
        if [ -f "$PROFILES_DIR/${last_profile}.env.encrypted" ]; then
            if load_encrypted_profile "$last_profile"; then
                CURRENT_PROFILE="$last_profile"
                log_info "Profil registry chiffré chargé: $CURRENT_PROFILE" >&2
                return 0
            fi
        fi

        # Sinon, essayer le profil non chiffré (charger uniquement credentials)
        if [ -f "$PROFILES_DIR/${last_profile}.env" ]; then
            load_credentials_from_file "$PROFILES_DIR/${last_profile}.env"
            CURRENT_PROFILE="$last_profile"
            log_info "Profil registry chargé: $CURRENT_PROFILE" >&2
            return 0
        fi
    fi

    # Fallback: chercher .env.registry (legacy)
    local legacy_config="$DEPLOYMENT_DIR/.env.registry"
    if [ -f "$legacy_config" ]; then
        log_warn "Utilisation du fichier legacy .env.registry" >&2
        log_info "Migrez vers les profils avec: ./scripts/registry.sh profile create" >&2
        load_credentials_from_file "$legacy_config"
        # Sur un package minimal (sans .devops.yml), charger aussi les infos projet
        if [ -z "$REGISTRY_URL" ]; then
            REGISTRY_URL=$(grep "^REGISTRY_URL=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        if [ -z "$REGISTRY_USERNAME" ]; then
            REGISTRY_USERNAME=$(grep "^REGISTRY_USERNAME=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        if [ -z "$IMAGE_NAME" ]; then
            IMAGE_NAME=$(grep "^IMAGE_NAME=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        # Charger aussi les variables de configuration de l'application (si présentes)
        if [ -z "$PROJECT_NAME" ]; then
            PROJECT_NAME=$(grep "^PROJECT_NAME=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        if [ -z "$COMPOSE_PROJECT_NAME" ]; then
            COMPOSE_PROJECT_NAME=$(grep "^COMPOSE_PROJECT_NAME=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        if [ -z "$APP_ENTRYPOINT" ]; then
            APP_ENTRYPOINT=$(grep "^APP_ENTRYPOINT=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        if [ -z "$APP_PYTHON_PATH" ]; then
            APP_PYTHON_PATH=$(grep "^APP_PYTHON_PATH=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        if [ -z "$APP_SOURCE_DIR" ]; then
            APP_SOURCE_DIR=$(grep "^APP_SOURCE_DIR=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        if [ -z "$APP_DEST_DIR" ]; then
            APP_DEST_DIR=$(grep "^APP_DEST_DIR=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        if [ -z "$WORKDIR" ]; then
            WORKDIR=$(grep "^WORKDIR=" "$legacy_config" 2>/dev/null | cut -d'=' -f2)
        fi
        CURRENT_PROFILE="legacy"
        return 0
    fi

    # Aucun profil trouvé - Vérifier si .devops.yml a les infos nécessaires
    if [ -n "$REGISTRY_USERNAME" ] && [ -n "$IMAGE_NAME" ]; then
        log_warn "Aucun profil trouvé, mais configuration projet disponible depuis .devops.yml" >&2
        log_info "Créez un profil pour stocker vos credentials: ./registry.sh profile create" >&2
        CURRENT_PROFILE=""
        return 0
    fi

    # Aucune configuration - proposer la création
    log_warn "Aucune configuration trouvée!" >&2
    echo "" >&2
    echo -e "${YELLOW}Voulez-vous créer un nouveau profil maintenant? (y/N):${NC} " >&2
    read -p "" create_now >&2

    if [[ "$create_now" =~ ^[Yy]$ ]]; then
        # Créer un profil de manière interactive
        create_profile_interactive

        # Recharger le profil nouvellement créé
        if [ -f "$LAST_PROFILE_FILE" ]; then
            local new_profile=$(cat "$LAST_PROFILE_FILE")
            if [ -f "$PROFILES_DIR/${new_profile}.env" ]; then
                load_credentials_from_file "$PROFILES_DIR/${new_profile}.env"
                CURRENT_PROFILE="$new_profile"
                log_success "Profil '$new_profile' chargé!" >&2
                return 0
            elif [ -f "$PROFILES_DIR/${new_profile}.env.encrypted" ]; then
                if load_encrypted_profile "$new_profile"; then
                    CURRENT_PROFILE="$new_profile"
                    log_success "Profil '$new_profile' chargé!" >&2
                    return 0
                fi
            fi
        fi
    fi

    log_info "Créez un profil avec: cd $SCRIPT_DIR && ./registry.sh profile create" >&2
    return 1
}

# Charger le profil
load_profile || exit 1

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================

# Détecter si on est sur le serveur ou en local
is_server_environment() {
    # Détecter si on est sur le serveur en vérifiant plusieurs critères
    # 1. Vérifier si on est dans /srv/home (typique d'un serveur)
    if [[ "$PROJECT_ROOT" == /srv/home* ]]; then
        return 0  # true = serveur
    fi

    # 2. Vérifier si une variable d'environnement spécifique existe
    if [ -n "$DEVOPS_SERVER_ENV" ]; then
        return 0  # true = serveur
    fi

    # 3. Vérifier la présence d'un fichier marker
    if [ -f "$DEPLOYMENT_DIR/.server-marker" ]; then
        return 0  # true = serveur
    fi

    return 1  # false = local
}

# Obtenir ou préparer le fichier .env pour un environnement
get_env_file() {
    local env=$1
    local env_file_path=""

    # Sur le serveur, chercher les fichiers chiffrés
    if is_server_environment; then
        local encrypted_env="$DEPLOYMENT_DIR/.env.${env}.encrypted"
        local temp_env="/tmp/.env.${env}.$$"

        # Vérifier si le fichier chiffré existe
        if [ -f "$encrypted_env" ]; then
            log_info "Environnement serveur détecté - déchiffrement de .env.$env..." >&2

            # Vérifier si env-encrypt.py existe
            local encrypt_script="$SCRIPT_DIR/env-encrypt.py"
            if [ ! -f "$encrypt_script" ]; then
                log_error "Script de déchiffrement non trouvé: $encrypt_script" >&2
                return 1
            fi

            # Vérifier si python3 ou venv existe
            local python_cmd="python3"
            if [ -f "$PROJECT_ROOT/.venv/bin/python3" ]; then
                python_cmd="$PROJECT_ROOT/.venv/bin/python3"
            elif [ -f "$DEPLOYMENT_DIR/.venv/bin/python3" ]; then
                python_cmd="$DEPLOYMENT_DIR/.venv/bin/python3"
            fi

            # Déchiffrer le fichier
            if $python_cmd "$encrypt_script" decrypt "$encrypted_env" >/dev/null 2>&1; then
                local decrypted_file="$DEPLOYMENT_DIR/.env.${env}"
                if [ -f "$decrypted_file" ]; then
                    # Copier vers un fichier temporaire
                    cp "$decrypted_file" "$temp_env"
                    # Supprimer le fichier déchiffré
                    rm -f "$decrypted_file"
                    env_file_path="$temp_env"
                    log_success "Fichier .env.$env déchiffré avec succès" >&2
                    echo "$env_file_path"
                    return 0
                fi
            else
                log_error "Échec du déchiffrement de .env.$env" >&2
                return 1
            fi
        else
            # Fallback: chercher à la racine du projet
            if [ -f "$PROJECT_ROOT/.env.$env" ]; then
                log_warn "Fichier chiffré non trouvé, utilisation de .env.$env non chiffré" >&2
                env_file_path="$PROJECT_ROOT/.env.$env"
                echo "$env_file_path"
                return 0
            else
                log_error "Fichier .env.$env introuvable (ni chiffré ni en clair)" >&2
                log_info "Chiffré attendu: $encrypted_env" >&2
                log_info "Clair attendu: $PROJECT_ROOT/.env.$env" >&2
                return 1
            fi
        fi
    else
        # En local, utiliser directement le fichier .env
        env_file_path="$PROJECT_ROOT/.env.$env"

        if [ ! -f "$env_file_path" ]; then
            log_error "Fichier .env.$env non trouvé à la racine du projet!" >&2
            log_info "Chemin attendu: $env_file_path" >&2
            return 1
        fi

        log_info "Environnement local détecté - utilisation de .env.$env" >&2
        echo "$env_file_path"
        return 0
    fi

    return 1
}

# Nettoyer les fichiers temporaires
cleanup_temp_env() {
    local env_file=$1

    # Supprimer uniquement si c'est un fichier temporaire
    if [[ "$env_file" == /tmp/.env.* ]]; then
        rm -f "$env_file"
    fi
}

# Construire le nom complet de l'image
build_image_full() {
    local env=$1
    local tag=${2:-${env}-latest}

    if [ "$REGISTRY_URL" == "docker.io" ]; then
        echo "${REGISTRY_USERNAME}/${IMAGE_NAME}:${tag}"
    else
        echo "${REGISTRY_URL}/${REGISTRY_USERNAME}/${IMAGE_NAME}:${tag}"
    fi
}

# Lister les tags disponibles dans le registry
list_available_tags() {
    local env=$1

    log_header "TAGS DISPONIBLES - $env"

    case "$REGISTRY_TYPE" in
        dockerhub)
            log_info "Interrogation de Docker Hub..."
            local api_url="https://hub.docker.com/v2/repositories/${REGISTRY_USERNAME}/${IMAGE_NAME}/tags?page_size=100"

            # Récupérer les tags et filtrer par environnement
            local tags=$(curl -s "$api_url" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep "^${env}-" | sort -r)

            if [ -z "$tags" ]; then
                log_warn "Aucun tag trouvé pour l'environnement $env"
                return 1
            fi

            echo -e "${CYAN}Tags disponibles pour ${WHITE}$env${NC}:\n"

            local count=1
            echo "$tags" | while IFS= read -r tag; do
                if [[ "$tag" == *"-latest" ]]; then
                    echo -e "  ${GREEN}$count)${NC} ${WHITE}$tag${NC} ${CYAN}(recommandé)${NC}"
                else
                    echo -e "  ${CYAN}$count)${NC} $tag"
                fi
                ((count++))
            done

            echo ""
            log_info "Utilisation: ./deploy-registry.sh deploy $env <tag>"
            ;;

        github)
            log_warn "Listing des tags GitHub Container Registry non implémenté"
            log_info "Consultez: https://github.com/${REGISTRY_USERNAME}/${IMAGE_NAME}/pkgs/container/${IMAGE_NAME}"
            ;;

        gitlab)
            log_warn "Listing des tags GitLab Container Registry non implémenté"
            log_info "Consultez: https://gitlab.com/${REGISTRY_USERNAME}/${IMAGE_NAME}/container_registry"
            ;;

        *)
            log_warn "Listing non supporté pour le type de registry: $REGISTRY_TYPE"
            ;;
    esac
}

# Vérifier qu'une image existe dans le registry
check_image_exists() {
    local image_full=$1

    log_info "Vérification de l'image dans le registry..."

    if docker manifest inspect "$image_full" >/dev/null 2>&1; then
        log_success "Image trouvée: $image_full"
        return 0
    else
        log_error "Image non trouvée: $image_full"
        return 1
    fi
}

# Obtenir les fichiers docker-compose à utiliser
get_compose_files() {
    local env=$1
    # --env-file est nécessaire pour la substitution de variables dans le YAML
    # (env_file dans docker-compose.yml charge les variables dans le container, pas pour le parsing YAML)

    # Déterminer le chemin du fichier .env selon le mode de déploiement:
    # - Mode développement (structure complète): ../..env.${env} (depuis deployment/compose/)
    # - Mode package minimal (fichiers à la racine): ./.env.${env}
    local env_file_path
    if [ "$DEPLOYMENT_DIR" = "$PROJECT_ROOT" ]; then
        # Package minimal: tous les fichiers sont à la racine
        env_file_path="./.env.${env}"
    else
        # Structure complète: les docker-compose sont dans deployment/
        env_file_path="../.env.${env}"
    fi

    echo "--env-file ${env_file_path} -f docker-compose.registry.yml -f docker-compose.${env}-registry.yml"
}

# ============================================================================
# FONCTIONS VERSIONING SÉMANTIQUE
# ============================================================================

# Extraire la dernière version depuis les tags
get_latest_version() {
    local env=$1
    local api_url="https://hub.docker.com/v2/repositories/${REGISTRY_USERNAME}/${IMAGE_NAME}/tags?page_size=100"

    # Récupérer tous les tags de l'environnement au format vX.Y.Z (sémantique uniquement)
    # Exclure les tags date+hash (v20251216-...) et ne garder que vX.Y.Z
    local tags=$(curl -s "$api_url" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep "^${env}-v[0-9]\+\.[0-9]\+\.[0-9]\+$" | sed "s/^${env}-//" | sort -rV)

    if [ -z "$tags" ]; then
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
    echo -e "  ${GREEN}5.${NC} ${WHITE}Latest${NC} - Utiliser ${env}-latest" >&2
    echo -e "  ${GREEN}0.${NC} Annuler" >&2
    echo "" >&2

    read -p "Choisissez le type de version (0-5): " version_choice

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

# ============================================================================
# FONCTIONS MODE INTERACTIF
# ============================================================================

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

# Menu pour choisir un tag
choose_tag() {
    local env=$1
    local mode=${2:-"deploy"}  # deploy ou release

    echo "" >&2

    if [ "$mode" == "release" ]; then
        # Mode release : proposer le versioning sémantique
        echo -e "${CYAN}Mode: ${WHITE}Nouvelle version (Release)${NC}" >&2
        echo "" >&2

        local version=$(choose_version "$env")
        if [ $? -ne 0 ] || [ -z "$version" ]; then
            return 1
        fi

        # Construire le tag complet
        if [ "$version" == "latest" ]; then
            echo "${env}-latest"
        else
            echo "${env}-${version}"
        fi
    else
        # Mode deploy : liste des tags existants
        echo -e "${CYAN}Tags disponibles pour ${WHITE}$env${NC}:" >&2
        echo "" >&2

        # Récupérer les tags depuis Docker Hub
        local api_url="https://hub.docker.com/v2/repositories/${REGISTRY_USERNAME}/${IMAGE_NAME}/tags?page_size=100"
        local tags=$(curl -s "$api_url" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep "^${env}-" | sort -rV)

        if [ -z "$tags" ]; then
            log_warn "Aucun tag trouvé, utilisation de ${env}-latest" >&2
            echo "${env}-latest"
            return 0
        fi

        # Afficher les tags avec numérotation
        local tags_array=()
        local count=1
        while IFS= read -r tag; do
            tags_array+=("$tag")
            if [[ "$tag" == *"-latest" ]]; then
                echo -e "  ${GREEN}$count)${NC} ${WHITE}$tag${NC} ${CYAN}(recommandé)${NC}" >&2
            elif [[ "$tag" =~ -v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                # Tag avec version sémantique
                echo -e "  ${GREEN}$count)${NC} ${CYAN}$tag${NC}" >&2
            else
                echo -e "  ${GREEN}$count)${NC} $tag" >&2
            fi
            ((count++))
        done <<< "$tags"

        echo "" >&2
        read -p "Choisissez un tag (1-${#tags_array[@]}) ou Entrée pour ${env}-latest: " tag_choice

        # Si vide, utiliser latest
        if [ -z "$tag_choice" ]; then
            echo "${env}-latest"
            return 0
        fi

        # Si c'est un numéro
        if [[ "$tag_choice" =~ ^[0-9]+$ ]]; then
            if [ "$tag_choice" -ge 1 ] && [ "$tag_choice" -le "${#tags_array[@]}" ]; then
                local selected_tag="${tags_array[$((tag_choice-1))]}"
                echo "$selected_tag"
                return 0
            else
                log_error "Numéro invalide" >&2
                return 1
            fi
        else
            # Sinon, c'est un nom de tag
            echo "$tag_choice"
            return 0
        fi
    fi
}

# ============================================================================
# GESTION DES PROFILS
# ============================================================================

# Lister les profils disponibles
list_profiles() {
    local show_numbers=${1:-false}
    echo -e "${CYAN}Profils disponibles:${NC}"

    # Créer une liste unique de profils (chiffrés et non chiffrés)
    local profiles=()
    if [ -d "$PROFILES_DIR" ]; then
        for file in "$PROFILES_DIR"/*.env "$PROFILES_DIR"/*.env.encrypted; do
            if [ -f "$file" ]; then
                local name=$(basename "$file" .env.encrypted)
                name=$(basename "$name" .env)
                # Ajouter seulement si pas déjà dans la liste
                if [[ ! " ${profiles[@]} " =~ " ${name} " ]]; then
                    profiles+=("$name")
                fi
            fi
        done
    fi

    if [ ${#profiles[@]} -eq 0 ]; then
        log_warn "Aucun profil trouvé"
        return
    fi

    local current_profile=$(cat "$LAST_PROFILE_FILE" 2>/dev/null || echo "")
    local index=1

    for name in "${profiles[@]}"; do
        local encrypted_marker=""
        if [ -f "$PROFILES_DIR/${name}.env.encrypted" ] && [ ! -f "$PROFILES_DIR/${name}.env" ]; then
            encrypted_marker=" ${CYAN}[chiffré]${NC}"
        fi

        if [ "$show_numbers" = "true" ]; then
            if [ "$name" = "$current_profile" ]; then
                echo -e "  ${GREEN}${index})${NC} ${GREEN}●${NC} $name ${YELLOW}(actuel)${NC}${encrypted_marker}"
            else
                echo -e "  ${WHITE}${index})${NC} ${WHITE}○${NC} $name${encrypted_marker}"
            fi
        else
            if [ "$name" = "$current_profile" ]; then
                echo -e "  ${GREEN}●${NC} $name ${YELLOW}(actuel)${NC}${encrypted_marker}"
            else
                echo -e "  ${WHITE}○${NC} $name${encrypted_marker}"
            fi
        fi
        ((index++))
    done
}

# Afficher la configuration actuelle
show_current_profile() {
    log_header "Configuration actuelle"

    echo -e "${CYAN}Profil credentials:${NC}"
    if [ -f "$LAST_PROFILE_FILE" ]; then
        local profile_name=$(cat "$LAST_PROFILE_FILE")
        echo -e "  Profil: ${WHITE}$profile_name${NC}"
        echo -e "  Type: $(get_registry_description "$REGISTRY_TYPE")"
        echo -e "  Token configuré: $([ -n "$REGISTRY_TOKEN" ] && echo "${GREEN}Oui${NC}" || echo "${YELLOW}Non${NC}")"
        echo -e "  GitHub Token: $([ -n "$GITHUB_TOKEN" ] && echo "${GREEN}Oui${NC}" || echo "${YELLOW}Non${NC}")"
    else
        echo -e "  ${YELLOW}Aucun profil chargé${NC}"
    fi
    echo ""

    echo -e "${CYAN}Configuration projet (depuis .devops.yml):${NC}"
    echo -e "  Registry URL: ${WHITE}${REGISTRY_URL:-non défini}${NC}"
    echo -e "  Username: ${WHITE}${REGISTRY_USERNAME:-non défini}${NC}"
    echo -e "  Image: ${WHITE}${IMAGE_NAME:-non défini}${NC}"
    echo -e "  Git Repo: ${WHITE}${GIT_REPO:-non défini}${NC}"
    echo -e "  Dev Branch: ${WHITE}${DEV_BRANCH:-dev}${NC}"
    echo -e "  Staging Branch: ${WHITE}${STAGING_BRANCH:-staging}${NC}"
    echo -e "  Prod Branch: ${WHITE}${PROD_BRANCH:-main}${NC}"
}

# Créer un profil de manière interactive (appelé depuis load_profile)
create_profile_interactive() {
    log_header "Création d'un nouveau profil (credentials)" >&2

    # Afficher les infos du projet depuis .devops.yml
    echo -e "${CYAN}Configuration projet (depuis .devops.yml):${NC}" >&2
    echo -e "  Registry URL: ${WHITE}${REGISTRY_URL:-non défini}${NC}" >&2
    echo -e "  Username: ${WHITE}${REGISTRY_USERNAME:-non défini}${NC}" >&2
    echo -e "  Image: ${WHITE}${IMAGE_NAME:-non défini}${NC}" >&2
    echo "" >&2
    print_separator >&2
    echo "" >&2

    # Demander le nom du profil
    read -p "Nom du profil [dockerhub-dev]: " profile_name >&2
    profile_name=${profile_name:-dockerhub-dev}

    # Vérifier si le profil existe déjà
    if [ -f "$PROFILES_DIR/${profile_name}.env" ] || [ -f "$PROFILES_DIR/${profile_name}.env.encrypted" ]; then
        log_warn "Un profil '$profile_name' existe déjà" >&2
        read -p "Voulez-vous l'écraser? (y/N): " overwrite >&2
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            log_info "Création annulée" >&2
            return 1
        fi
        # Supprimer les anciennes versions
        rm -f "$PROFILES_DIR/${profile_name}.env"
        rm -f "$PROFILES_DIR/${profile_name}.env.encrypted"
    fi

    # Demander UNIQUEMENT les credentials
    echo "" >&2
    echo -e "${CYAN}Type de registry:${NC}" >&2
    echo "  1) Docker Hub" >&2
    echo "  2) GitLab Container Registry" >&2
    echo "  3) GitHub Container Registry" >&2
    echo "  4) Custom" >&2
    read -p "Choix [1]: " reg_choice >&2

    local reg_type
    case "${reg_choice:-1}" in
        1) reg_type="dockerhub" ;;
        2) reg_type="gitlab" ;;
        3) reg_type="github" ;;
        4) reg_type="custom" ;;
        *) reg_type="dockerhub" ;;
    esac

    echo "" >&2
    echo -e "${CYAN}Authentification:${NC}" >&2
    read -p "Registry Token (optionnel): " reg_token >&2
    read -sp "Registry Password (optionnel): " reg_password >&2
    echo "" >&2
    read -p "GitHub Token (optionnel, pour repos privés): " github_token >&2

    # Créer le dossier s'il n'existe pas
    mkdir -p "$PROFILES_DIR"

    # Créer le profil avec UNIQUEMENT les credentials
    local current_date=$(date)
    cat > "$PROFILES_DIR/${profile_name}.env" <<EOF
# Profil Registry: ${profile_name}
# Type: ${reg_type}
# Créé le: ${current_date}
#
# NOTE: Ce profil contient uniquement les credentials.
# Les informations du projet (registry_url, registry_username, image_name, etc.)
# sont chargées depuis le fichier .devops.yml du projet.

REGISTRY_TYPE=${reg_type}
REGISTRY_TOKEN=${reg_token}
REGISTRY_PASSWORD=${reg_password}
GITHUB_TOKEN=${github_token}
EOF

    log_success "Profil '$profile_name' créé avec succès!" >&2
    log_info "Les infos du projet sont lues depuis .devops.yml" >&2

    # Définir comme profil par défaut
    echo "$profile_name" > "$LAST_PROFILE_FILE"

    # Chiffrer le profil pour protéger les secrets
    encrypt_profile "$profile_name" >&2
}

# Créer un nouveau profil (credentials uniquement)
create_profile() {
    log_header "Créer un nouveau profil (credentials)"

    # Afficher les infos du projet depuis .devops.yml
    echo -e "${CYAN}Configuration projet (depuis .devops.yml):${NC}"
    echo -e "  Registry URL: ${WHITE}${REGISTRY_URL:-non défini}${NC}"
    echo -e "  Username: ${WHITE}${REGISTRY_USERNAME:-non défini}${NC}"
    echo -e "  Image: ${WHITE}${IMAGE_NAME:-non défini}${NC}"
    echo ""
    print_separator
    echo ""

    # Demander le nom du profil
    echo "Nom du profil (ex: dockerhub-dev, ghcr-prod):"
    read -p "> " profile_name

    if [ -z "$profile_name" ]; then
        log_error "Nom de profil requis"
        return 1
    fi

    # Vérifier si le profil existe déjà (chiffré ou non)
    if [ -f "$PROFILES_DIR/${profile_name}.env" ] || [ -f "$PROFILES_DIR/${profile_name}.env.encrypted" ]; then
        log_warn "Le profil '$profile_name' existe déjà"
        read -p "Écraser? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            log_info "Création annulée"
            return 0
        fi
        # Supprimer les anciennes versions
        rm -f "$PROFILES_DIR/${profile_name}.env"
        rm -f "$PROFILES_DIR/${profile_name}.env.encrypted"
    fi

    # Demander UNIQUEMENT les credentials
    echo ""
    echo -e "${CYAN}Type de registry:${NC}"
    echo "  1) Docker Hub"
    echo "  2) GitLab Container Registry"
    echo "  3) GitHub Container Registry"
    echo "  4) Custom"
    read -p "Choix [1]: " reg_choice

    local reg_type
    case "${reg_choice:-1}" in
        1) reg_type="dockerhub" ;;
        2) reg_type="gitlab" ;;
        3) reg_type="github" ;;
        4) reg_type="custom" ;;
        *) reg_type="dockerhub" ;;
    esac

    echo ""
    echo -e "${CYAN}Authentification:${NC}"
    read -p "Registry Token (optionnel): " reg_token
    read -sp "Registry Password (optionnel): " reg_password
    echo ""
    read -p "GitHub Token (optionnel, pour repos privés): " github_token

    # Créer le dossier s'il n'existe pas
    mkdir -p "$PROFILES_DIR"

    # Créer le profil avec UNIQUEMENT les credentials
    local current_date=$(date)
    cat > "$PROFILES_DIR/${profile_name}.env" <<EOF
# Profil Registry: ${profile_name}
# Type: ${reg_type}
# Créé le: ${current_date}
#
# NOTE: Ce profil contient uniquement les credentials.
# Les informations du projet (registry_url, registry_username, image_name, etc.)
# sont chargées depuis le fichier .devops.yml du projet.

REGISTRY_TYPE=${reg_type}
REGISTRY_TOKEN=${reg_token}
REGISTRY_PASSWORD=${reg_password}
GITHUB_TOKEN=${github_token}
EOF

    log_success "Profil '$profile_name' créé avec succès!"
    log_info "Les infos du projet sont lues depuis .devops.yml"

    # Chiffrer le profil pour protéger les secrets
    encrypt_profile "$profile_name"

    # Demander si on veut l'utiliser
    read -p "Utiliser ce profil maintenant? (y/N): " use_now
    if [[ "$use_now" =~ ^[Yy]$ ]]; then
        echo "$profile_name" > "$LAST_PROFILE_FILE"
        log_success "Profil '$profile_name' activé"
    fi
}

# Charger un profil existant
switch_profile() {
    log_header "Changer de profil"

    echo ""
    list_profiles true
    echo ""

    read -p "Numéro ou nom du profil à charger: " choice

    if [ -z "$choice" ]; then
        log_error "Choix requis"
        return 1
    fi

    local profile_name=""

    # Si c'est un nombre, récupérer le profil par index
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        # Créer une liste unique de profils (chiffrés et non chiffrés)
        local profiles=()
        for file in "$PROFILES_DIR"/*.env "$PROFILES_DIR"/*.env.encrypted; do
            if [ -f "$file" ]; then
                local name=$(basename "$file" .env.encrypted)
                name=$(basename "$name" .env)
                if [[ ! " ${profiles[@]} " =~ " ${name} " ]]; then
                    profiles+=("$name")
                fi
            fi
        done

        # Récupérer le profil par index
        if [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
            profile_name="${profiles[$((choice-1))]}"
        else
            log_error "Numéro invalide: $choice"
            return 1
        fi
    else
        profile_name="$choice"
    fi

    # Vérifier si le profil existe (chiffré ou non)
    if [ ! -f "$PROFILES_DIR/${profile_name}.env" ] && [ ! -f "$PROFILES_DIR/${profile_name}.env.encrypted" ]; then
        log_error "Profil '$profile_name' non trouvé"
        return 1
    fi

    echo "$profile_name" > "$LAST_PROFILE_FILE"
    log_success "Profil '$profile_name' activé"
    log_info "Redémarrez le script pour utiliser ce profil"
    exit 0
}

# Supprimer un profil
delete_profile() {
    log_header "Supprimer un profil"

    echo ""
    list_profiles true
    echo ""

    read -p "Numéro ou nom du profil à supprimer: " choice

    if [ -z "$choice" ]; then
        log_error "Choix requis"
        return 1
    fi

    local profile_name=""

    # Si c'est un nombre, récupérer le profil par index
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        # Créer une liste unique de profils (chiffrés et non chiffrés)
        local profiles=()
        for file in "$PROFILES_DIR"/*.env "$PROFILES_DIR"/*.env.encrypted; do
            if [ -f "$file" ]; then
                local name=$(basename "$file" .env.encrypted)
                name=$(basename "$name" .env)
                if [[ ! " ${profiles[@]} " =~ " ${name} " ]]; then
                    profiles+=("$name")
                fi
            fi
        done

        # Récupérer le profil par index
        if [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
            profile_name="${profiles[$((choice-1))]}"
        else
            log_error "Numéro invalide: $choice"
            return 1
        fi
    else
        profile_name="$choice"
    fi

    # Vérifier si le profil existe (chiffré ou non)
    if [ ! -f "$PROFILES_DIR/${profile_name}.env" ] && [ ! -f "$PROFILES_DIR/${profile_name}.env.encrypted" ]; then
        log_error "Profil '$profile_name' non trouvé"
        return 1
    fi

    # Vérifier si c'est le profil actuel
    local current_profile=$(cat "$LAST_PROFILE_FILE" 2>/dev/null || echo "")
    if [ "$profile_name" = "$current_profile" ]; then
        log_warn "Ce profil est actuellement utilisé"
    fi

    read -p "Confirmer la suppression de '$profile_name'? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Suppression annulée"
        return 0
    fi

    rm -f "$PROFILES_DIR/${profile_name}.env"
    rm -f "$PROFILES_DIR/${profile_name}.env.encrypted"
    log_success "Profil '$profile_name' supprimé"

    # Si c'était le profil actuel, le retirer
    if [ "$profile_name" = "$current_profile" ]; then
        rm -f "$LAST_PROFILE_FILE"
        log_warn "Profil actuel retiré - sélectionnez un nouveau profil"
    fi
}

# Éditer un profil existant
edit_profile() {
    log_header "Éditer un profil"

    echo ""
    list_profiles true
    echo ""

    read -p "Numéro ou nom du profil à éditer: " choice

    if [ -z "$choice" ]; then
        log_error "Choix requis"
        return 1
    fi

    local profile_name=""

    # Si c'est un nombre, récupérer le profil par index
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        local profiles=()
        for file in "$PROFILES_DIR"/*.env "$PROFILES_DIR"/*.env.encrypted; do
            if [ -f "$file" ]; then
                local name=$(basename "$file" .env.encrypted)
                name=$(basename "$name" .env)
                # Vérifier si déjà ajouté
                local already_added=false
                for p in "${profiles[@]}"; do
                    if [ "$p" = "$name" ]; then
                        already_added=true
                        break
                    fi
                done
                if [ "$already_added" = false ]; then
                    profiles+=("$name")
                fi
            fi
        done

        if [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
            profile_name="${profiles[$((choice-1))]}"
        else
            log_error "Numéro invalide: $choice"
            return 1
        fi
    else
        profile_name="$choice"
    fi

    # Déchiffrer le profil si nécessaire
    local encrypted_file="$PROFILES_DIR/${profile_name}.env.encrypted"
    local profile_file="$PROFILES_DIR/${profile_name}.env"
    local was_encrypted=false

    if [ -f "$encrypted_file" ] && [ ! -f "$profile_file" ]; then
        log_info "Déchiffrement du profil..."

        local encrypt_script="$SCRIPT_DIR/env-encrypt.py"
        local python_cmd="python3"
        if [ -f "$DEPLOYMENT_DIR/../.venv/bin/python3" ]; then
            python_cmd="$DEPLOYMENT_DIR/../.venv/bin/python3"
        fi

        if ! $python_cmd "$encrypt_script" decrypt "$encrypted_file" >/dev/null 2>&1; then
            log_error "Échec du déchiffrement"
            return 1
        fi
        was_encrypted=true
    fi

    if [ ! -f "$profile_file" ]; then
        log_error "Profil '$profile_name' non trouvé"
        return 1
    fi

    # Charger les valeurs actuelles
    source "$profile_file"

    # Menu d'édition
    while true; do
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}     ${WHITE}Édition du profil: ${YELLOW}${profile_name}${NC}${CYAN}              ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${WHITE}Paramètres actuels:${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} REGISTRY_TYPE      = ${GREEN}${REGISTRY_TYPE}${NC}"
        echo -e "  ${CYAN}2)${NC} REGISTRY_URL       = ${GREEN}${REGISTRY_URL}${NC}"
        echo -e "  ${CYAN}3)${NC} REGISTRY_USERNAME  = ${GREEN}${REGISTRY_USERNAME}${NC}"
        echo -e "  ${CYAN}4)${NC} REGISTRY_TOKEN     = ${GREEN}${REGISTRY_TOKEN:+[***défini***]}${REGISTRY_TOKEN:-[vide]}${NC}"
        echo -e "  ${CYAN}5)${NC} REGISTRY_PASSWORD  = ${GREEN}${REGISTRY_PASSWORD:+[***défini***]}${REGISTRY_PASSWORD:-[vide]}${NC}"
        echo -e "  ${CYAN}6)${NC} IMAGE_NAME         = ${GREEN}${IMAGE_NAME}${NC}"
        echo ""
        echo -e "${WHITE}Paramètres Git:${NC}"
        echo ""
        echo -e "  ${CYAN}7)${NC} GIT_REPO           = ${GREEN}${GIT_REPO:-[vide]}${NC}"
        echo -e "  ${CYAN}8)${NC} GITHUB_TOKEN       = ${GREEN}${GITHUB_TOKEN:+[***défini***]}${GITHUB_TOKEN:-[vide]}${NC}"
        echo -e "  ${CYAN}9)${NC} DEV_BRANCH         = ${GREEN}${DEV_BRANCH:-dev}${NC}"
        echo -e "  ${CYAN}10)${NC} STAGING_BRANCH     = ${GREEN}${STAGING_BRANCH:-staging}${NC}"
        echo -e "  ${CYAN}11)${NC} PROD_BRANCH        = ${GREEN}${PROD_BRANCH:-prod}${NC}"
        echo ""
        echo -e "  ${GREEN}s)${NC} Sauvegarder et quitter"
        echo -e "  ${RED}0)${NC} Annuler (sans sauvegarder)"
        echo ""

        read -p "Modifier le paramètre (1-11, s=sauvegarder, 0=annuler): " param_choice

        case "$param_choice" in
            1)
                read -p "REGISTRY_TYPE [$REGISTRY_TYPE]: " new_value
                REGISTRY_TYPE=${new_value:-$REGISTRY_TYPE}
                ;;
            2)
                read -p "REGISTRY_URL [$REGISTRY_URL]: " new_value
                REGISTRY_URL=${new_value:-$REGISTRY_URL}
                ;;
            3)
                read -p "REGISTRY_USERNAME [$REGISTRY_USERNAME]: " new_value
                REGISTRY_USERNAME=${new_value:-$REGISTRY_USERNAME}
                ;;
            4)
                read -p "REGISTRY_TOKEN (laisser vide pour ne pas changer): " new_value
                if [ -n "$new_value" ]; then
                    REGISTRY_TOKEN="$new_value"
                fi
                ;;
            5)
                read -sp "REGISTRY_PASSWORD (laisser vide pour ne pas changer): " new_value
                echo ""
                if [ -n "$new_value" ]; then
                    REGISTRY_PASSWORD="$new_value"
                fi
                ;;
            6)
                read -p "IMAGE_NAME [$IMAGE_NAME]: " new_value
                IMAGE_NAME=${new_value:-$IMAGE_NAME}
                ;;
            7)
                read -p "GIT_REPO [$GIT_REPO]: " new_value
                GIT_REPO=${new_value:-$GIT_REPO}
                ;;
            8)
                read -p "GITHUB_TOKEN (laisser vide pour ne pas changer): " new_value
                if [ -n "$new_value" ]; then
                    GITHUB_TOKEN="$new_value"
                fi
                ;;
            9)
                read -p "DEV_BRANCH [${DEV_BRANCH:-dev}]: " new_value
                DEV_BRANCH=${new_value:-${DEV_BRANCH:-dev}}
                ;;
            10)
                read -p "STAGING_BRANCH [${STAGING_BRANCH:-staging}]: " new_value
                STAGING_BRANCH=${new_value:-${STAGING_BRANCH:-staging}}
                ;;
            11)
                read -p "PROD_BRANCH [${PROD_BRANCH:-prod}]: " new_value
                PROD_BRANCH=${new_value:-${PROD_BRANCH:-prod}}
                ;;
            s|S)
                # Sauvegarder les modifications
                local current_date=$(date)
                cat > "$profile_file" <<EOF
# Profil Registry: ${profile_name}
# Type: ${REGISTRY_TYPE} (${REGISTRY_URL})
# Modifié le: ${current_date}

REGISTRY_TYPE=${REGISTRY_TYPE}
REGISTRY_URL=${REGISTRY_URL}
REGISTRY_USERNAME=${REGISTRY_USERNAME}
REGISTRY_TOKEN=${REGISTRY_TOKEN}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD}
IMAGE_NAME=${IMAGE_NAME}
GIT_REPO=${GIT_REPO}
GITHUB_TOKEN=${GITHUB_TOKEN}
DEV_BRANCH=${DEV_BRANCH:-dev}
STAGING_BRANCH=${STAGING_BRANCH:-staging}
PROD_BRANCH=${PROD_BRANCH:-prod}
EOF

                log_success "Profil '$profile_name' sauvegardé"

                # Chiffrer automatiquement
                if [ "$was_encrypted" = true ]; then
                    log_info "Chiffrement du profil..."
                    if encrypt_profile "$profile_name"; then
                        log_success "Profil chiffré automatiquement"
                    else
                        log_warn "Le profil a été sauvegardé mais le chiffrement a échoué"
                    fi
                else
                    read -p "Voulez-vous chiffrer ce profil? (y/N): " encrypt_choice
                    if [[ "$encrypt_choice" =~ ^[Yy]$ ]]; then
                        encrypt_profile "$profile_name"
                    fi
                fi

                return 0
                ;;
            0)
                log_info "Modifications annulées"
                # Supprimer le fichier déchiffré temporaire si nécessaire
                if [ "$was_encrypted" = true ]; then
                    rm -f "$profile_file"
                fi
                return 0
                ;;
            *)
                log_error "Choix invalide"
                ;;
        esac
    done
}

# Chiffrer un profil existant
encrypt_existing_profile() {
    log_header "Chiffrer un profil"

    echo ""
    echo -e "${CYAN}Profils disponibles (non chiffrés):${NC}"

    # Lister uniquement les profils non chiffrés
    local profiles=()
    local index=1
    if [ -d "$PROFILES_DIR" ]; then
        for file in "$PROFILES_DIR"/*.env; do
            if [ -f "$file" ]; then
                local name=$(basename "$file" .env)
                # Vérifier qu'il n'existe pas déjà en version chiffrée
                if [ ! -f "$PROFILES_DIR/${name}.env.encrypted" ]; then
                    profiles+=("$name")
                    echo -e "  ${WHITE}${index})${NC} $name"
                    ((index++))
                fi
            fi
        done
    fi
    echo ""

    if [ ${#profiles[@]} -eq 0 ]; then
        log_info "Tous les profils sont déjà chiffrés"
        return 0
    fi

    read -p "Numéro ou nom du profil à chiffrer: " choice

    if [ -z "$choice" ]; then
        log_error "Choix requis"
        return 1
    fi

    local profile_name=""

    # Si c'est un nombre, récupérer le profil par index
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
            profile_name="${profiles[$((choice-1))]}"
        else
            log_error "Numéro invalide: $choice"
            return 1
        fi
    else
        profile_name="$choice"
    fi

    # Vérifier que le profil existe et n'est pas déjà chiffré
    if [ ! -f "$PROFILES_DIR/${profile_name}.env" ]; then
        log_error "Profil '$profile_name' non trouvé"
        return 1
    fi

    if [ -f "$PROFILES_DIR/${profile_name}.env.encrypted" ]; then
        log_warn "Le profil '$profile_name' est déjà chiffré"
        return 0
    fi

    # Chiffrer le profil
    if encrypt_profile "$profile_name"; then
        log_success "Profil '$profile_name' chiffré avec succès!"
    else
        log_error "Échec du chiffrement du profil"
        return 1
    fi
}

# Menu principal interactif
interactive_menu() {
    while true; do
        log_header "${PROJECT_NAME:-DevOps} - Déploiement Registry (Mode Interactif)"

        echo -e "${CYAN}Configuration actuelle:${NC}"
        echo "  Registry: ${REGISTRY_TYPE} (${REGISTRY_URL})"
        echo "  Image: ${REGISTRY_USERNAME}/${IMAGE_NAME}"
        echo ""
        print_separator
        echo -e "${WHITE}DÉPLOIEMENT${NC}"
        echo -e "  ${WHITE}1)${NC} Déployer une image existante"
        echo -e "  ${WHITE}2)${NC} Lister les tags disponibles"
        echo ""
        echo -e "${WHITE}GESTION${NC}"
        echo -e "  ${WHITE}3)${NC} Voir le statut des conteneurs"
        echo -e "  ${WHITE}4)${NC} Voir les logs"
        echo -e "  ${WHITE}5)${NC} Redémarrer les services"
        echo -e "  ${WHITE}6)${NC} Arrêter les services"
        echo -e "  ${WHITE}16)${NC} ${CYAN}Importer les assets Superset${NC}"
        echo ""
        echo -e "${WHITE}AVANCÉ${NC}"
        echo -e "  ${WHITE}7)${NC} Télécharger une image (sans déployer)"
        echo -e "  ${WHITE}8)${NC} ${CYAN}Créer et déployer une nouvelle release${NC} ${YELLOW}(avec versioning)${NC}"
        echo ""
        echo -e "${WHITE}GESTION DES PROFILS${NC}"
        echo -e "  ${WHITE}9)${NC} Créer un nouveau profil"
        echo -e "  ${WHITE}10)${NC} Charger un profil existant"
        echo -e "  ${WHITE}11)${NC} Lister les profils"
        echo -e "  ${WHITE}12)${NC} Afficher le profil actuel"
        echo -e "  ${WHITE}13)${NC} ${YELLOW}Éditer un profil${NC}"
        echo -e "  ${WHITE}14)${NC} Supprimer un profil"
        echo -e "  ${WHITE}15)${NC} Chiffrer un profil existant"
        echo ""
        print_separator
        echo -e "${WHITE}0)${NC} Quitter"
        print_separator
        echo ""

        read -p "Votre choix: " choice

        case "$choice" in
            1)
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""
                    tag=$(choose_tag "$env" "deploy")
                    if [ $? -eq 0 ]; then
                        echo ""
                        print_separator
                        cmd_deploy "$env" "$tag"
                        echo ""
                        read -p "Appuyez sur Entrée pour revenir au menu principal..."
                    fi
                fi
                ;;
            2)
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""
                    list_available_tags "$env"
                    echo ""
                    read -p "Appuyez sur Entrée pour revenir au menu principal..."
                fi
                ;;
            3)
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""
                    cmd_status "$env"
                    echo ""
                    read -p "Appuyez sur Entrée pour revenir au menu principal..."
                fi
                ;;
            4)
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""
                    echo -e "${CYAN}Service:${NC}"
                    echo "  1) ${IMAGE_NAME:-api}"
                    echo "  2) redis"
                    echo ""
                    read -p "Choisissez le service (1-2, défaut: ${IMAGE_NAME:-api}): " service_choice

                    service="${IMAGE_NAME:-api}"
                    case "$service_choice" in
                        2) service="redis" ;;
                    esac

                    echo ""
                    log_info "Appuyez sur Ctrl+C pour revenir au menu principal"
                    sleep 2
                    cmd_logs "$env" "$service"
                fi
                ;;
            5)
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""
                    cmd_restart "$env"
                    echo ""
                    read -p "Appuyez sur Entrée pour revenir au menu principal..."
                fi
                ;;
            6)
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""
                    read -p "Confirmer l'arrêt de l'environnement $env? (yes/n): " confirm
                    if [ "$confirm" == "yes" ]; then
                        cmd_stop "$env"
                    else
                        log_info "Arrêt annulé"
                    fi
                    echo ""
                    read -p "Appuyez sur Entrée pour revenir au menu principal..."
                fi
                ;;
            7)
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""
                    tag=$(choose_tag "$env" "deploy")
                    if [ $? -eq 0 ]; then
                        echo ""
                        print_separator
                        cmd_pull "$env" "$tag"
                        echo ""
                        read -p "Appuyez sur Entrée pour revenir au menu principal..."
                    fi
                fi
                ;;
            8)
                # Nouvelle release avec versioning sémantique
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""

                    log_warn "Cette option nécessite que l'image soit déjà buildée et pushée sur le registry"
                    echo ""
                    echo -e "${CYAN}Workflow recommandé:${NC}"
                    echo "  1. Sur votre machine de build:"
                    echo "     ./deployment/scripts/registry.sh release $env"
                    echo ""
                    echo "  2. Sur ce serveur:"
                    echo "     ./deployment/scripts/deploy-registry.sh deploy $env <version>"
                    echo ""

                    tag=$(choose_tag "$env" "release")
                    if [ $? -eq 0 ]; then
                        echo ""

                        log_info "Tag sélectionné: ${WHITE}${tag}${NC}"
                        echo ""

                        read -p "Voulez-vous déployer cette version maintenant? (yes/n): " confirm_deploy
                        if [ "$confirm_deploy" == "yes" ]; then
                            print_separator
                            cmd_deploy "$env" "$tag"
                        else
                            log_info "Pour déployer cette version plus tard:"
                            echo "  ./deployment/scripts/deploy-registry.sh deploy $env $tag"
                        fi
                        echo ""
                        read -p "Appuyez sur Entrée pour revenir au menu principal..."
                    fi
                fi
                ;;
            9)
                # Créer un nouveau profil
                create_profile
                echo ""
                read -p "Appuyez sur Entrée pour revenir au menu principal..."
                ;;
            10)
                # Charger un profil existant
                switch_profile
                ;;
            11)
                # Lister les profils
                echo ""
                list_profiles
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            12)
                # Afficher le profil actuel
                echo ""
                show_current_profile
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            13)
                # Éditer un profil
                edit_profile
                echo ""
                read -p "Appuyez sur Entrée pour revenir au menu principal..."
                ;;
            14)
                # Supprimer un profil
                delete_profile
                echo ""
                read -p "Appuyez sur Entrée pour revenir au menu principal..."
                ;;
            15)
                # Chiffrer un profil existant
                encrypt_existing_profile
                echo ""
                read -p "Appuyez sur Entrée pour revenir au menu principal..."
                ;;
            16)
                # Importer les assets Superset
                env=$(choose_environment)
                if [ $? -eq 0 ]; then
                    echo ""
                    cmd_superset_import "$env"
                    echo ""
                    read -p "Appuyez sur Entrée pour revenir au menu principal..."
                fi
                ;;
            0)
                log_info "Au revoir!"
                exit 0
                ;;
            *)
                log_error "Choix invalide"
                echo ""
                read -p "Appuyez sur Entrée pour revenir au menu principal..."
                ;;
        esac
    done
}

# ============================================================================
# COMMANDES
# ============================================================================

# Déployer une image
cmd_deploy() {
    local env=$1
    local tag=${2:-${env}-latest}
    local env_file=""
    local cleanup_needed=false

    # Fonction de nettoyage en cas d'erreur
    cleanup_on_error() {
        if [ "$cleanup_needed" = true ]; then
            log_info "Nettoyage des fichiers temporaires..."
            # Nettoyer le fichier temporaire déchiffré
            if [ -n "$env_file" ]; then
                cleanup_temp_env "$env_file"
            fi
            # Nettoyer le fichier copié à la racine du projet si c'était un fichier temporaire
            if [[ "$env_file" == /tmp/.env.* ]] && [ -f "$PROJECT_ROOT/.env.$env" ]; then
                rm -f "$PROJECT_ROOT/.env.$env"
                log_info "Fichier .env.$env temporaire supprimé de la racine du projet"
            fi
        fi
    }

    # Configurer le trap pour nettoyer en cas d'erreur ou d'interruption
    trap cleanup_on_error EXIT INT TERM

    log_header "DÉPLOIEMENT - Environnement: $env"

    # Construire le nom complet de l'image
    local image_full=$(build_image_full "$env" "$tag")

    log_info "Image: $image_full"
    log_info "Environnement: $env"
    log_info "Tag: $tag"

    # Vérifier que l'image existe
    if ! check_image_exists "$image_full"; then
        log_error "L'image n'existe pas dans le registry"
        log_info "Tags disponibles:"
        list_available_tags "$env"
        exit 1
    fi

    print_separator

    # Obtenir le fichier .env (chiffré sur serveur, clair en local)
    env_file=$(get_env_file "$env")
    if [ $? -ne 0 ] || [ -z "$env_file" ]; then
        log_error "Impossible de récupérer le fichier .env.$env"
        exit 1
    fi

    # Marquer pour nettoyage si c'est un fichier temporaire
    if [[ "$env_file" == /tmp/.env.* ]]; then
        cleanup_needed=true
    fi

    # Exporter les variables pour docker-compose (substitution YAML)
    # ENV est utilisé dans docker-compose.yml pour ${ENV}
    export ENV=$env
    export ENVIRONMENT=$env
    # docker-compose.registry.yml utilise ${ENV}-${IMAGE_TAG}
    # Si le tag contient déjà le prefix env (ex: dev-latest), éviter dev-dev-latest
    local image_tag_for_compose="$tag"
    if [[ "$tag" == "${env}-"* ]]; then
        image_tag_for_compose="${tag#${env}-}"
    fi
    export IMAGE_TAG=$image_tag_for_compose
    export IMAGE_FULL=$image_full
    export COMPOSE_PROJECT_NAME="${PROJECT_NAME:-app}-${env}"

    # Exporter les variables de .devops.yml pour docker-compose
    export PROJECT_NAME="${PROJECT_NAME}"
    export REGISTRY_URL="${REGISTRY_URL}"
    export REGISTRY_USERNAME="${REGISTRY_USERNAME}"
    export IMAGE_NAME="${IMAGE_NAME}"
    export APP_SOURCE_DIR="${APP_SOURCE_DIR}"
    export APP_DEST_DIR="${APP_DEST_DIR}"
    export APP_ENTRYPOINT="${APP_ENTRYPOINT}"
    export APP_PYTHON_PATH="${APP_PYTHON_PATH}"
    export WORKDIR="${WORKDIR}"

    # Exporter le chemin du fichier .env pour docker-compose
    # Sur le serveur déployé (sans deployment/), le fichier est dans le répertoire courant
    export ENV_FILE_PATH=".env.$env"

    # Exporter les chemins pour les volumes (clé et fichier chiffré)
    export ENV_KEY_PATH="$PROJECT_ROOT/.env.key"
    export ENV_ENCRYPTED_PATH="$PROJECT_ROOT/.env.${env}.encrypted"

    # S'assurer que le fichier .env est accessible pour docker-compose
    # Docker-compose s'attend à trouver ../.env.<env> depuis le répertoire deployment/

    # Construire le chemin absolu de manière plus robuste
    local target_env_file
    if [ -n "$PROJECT_ROOT" ] && [ "$PROJECT_ROOT" != "/" ]; then
        target_env_file="$PROJECT_ROOT/.env.$env"
    else
        # Fallback: utiliser le chemin absolu depuis DEPLOYMENT_DIR
        target_env_file="$(cd "$DEPLOYMENT_DIR/.." && pwd)/.env.$env"
    fi

    log_info "Vérification du fichier .env pour docker-compose..."
    log_info "Fichier source: $env_file"
    log_info "Cible pour docker-compose: $target_env_file"
    log_info "PROJECT_ROOT détecté: $PROJECT_ROOT"

    # Si le fichier n'est pas déjà au bon endroit, copier
    if [ "$env_file" != "$target_env_file" ]; then
        # Créer le répertoire parent si nécessaire
        local target_dir=$(dirname "$target_env_file")
        mkdir -p "$target_dir"

        log_info "Copie du fichier .env vers $target_env_file..."
        cp -f "$env_file" "$target_env_file"

        # Si c'était un fichier temporaire, marquer pour suppression
        if [[ "$env_file" == /tmp/.env.* ]]; then
            cleanup_needed=true
        fi

        log_success "Fichier copié avec succès"
    else
        log_info "Fichier déjà au bon endroit"
    fi

    # Vérifier que le fichier existe bien
    if [ ! -f "$target_env_file" ]; then
        log_error "Le fichier .env.$env n'est pas accessible à $target_env_file"
        log_error "Vérifiez les chemins de débogage ci-dessus"
        exit 1
    fi

    log_success "Fichier .env.$env prêt pour docker-compose"

    # Note: Les variables du fichier .env sont chargées par docker compose via --env-file
    # (pas besoin de sourcer le fichier dans le shell)

    cd "$DEPLOYMENT_DIR"

    # Uniformiser le nom de projet Compose (local + registry)
    local base_compose_name="${COMPOSE_PROJECT_NAME:-${PROJECT_NAME:-app}}"
    if [[ "$base_compose_name" == *"-${env}" ]]; then
        export COMPOSE_PROJECT_NAME="$base_compose_name"
    else
        export COMPOSE_PROJECT_NAME="${base_compose_name}-${env}"
    fi

    # Auto-clean optionnel: arrêter un éventuel déploiement local pour éviter les conflits
    echo ""
    read -p "Nettoyer le déploiement local avant le deploy registry? (y/N): " clean_local
    if [[ "$clean_local" =~ ^[Yy]$ ]]; then
        log_info "Nettoyage du déploiement local (si présent)..."
        docker compose -f docker-compose.yml -f docker-compose.$env.yml down -v 2>/dev/null || true
        local network_name="${PROJECT_NAME}-${env}-network"

        case "${STACK_TYPE}" in
            monitoring)
                local containers=(
                    "${PROJECT_NAME}-prometheus-${env}"
                    "${PROJECT_NAME}-grafana-${env}"
                    "${PROJECT_NAME}-cadvisor-${env}"
                    "${PROJECT_NAME}-node-exporter-${env}"
                    "${PROJECT_NAME}-postgres-${env}"
                    "${PROJECT_NAME}-postgres-exporter-${env}"
                )
                docker rm -f "${containers[@]}" 2>/dev/null || true
                docker network rm "$network_name" 2>/dev/null || true
                docker volume rm "${PROJECT_NAME}-prometheus-${env}-data" "${PROJECT_NAME}-grafana-${env}-data" 2>/dev/null || true
                ;;
            *)
                local volume_name="${PROJECT_NAME}-redis-${env}-data"
                local api_container="${PROJECT_NAME}-api-${env}"
                local redis_container="${PROJECT_NAME}-redis-${env}"
                docker rm -f "$api_container" "$redis_container" 2>/dev/null || true
                docker network rm "$network_name" 2>/dev/null || true
                docker volume rm "$volume_name" 2>/dev/null || true
                ;;
        esac
    else
        log_info "Nettoyage local ignoré"
    fi

    # Arrêter les conteneurs existants
    log_info "Arrêt des conteneurs existants..."
    docker compose $(get_compose_files "$env") down || true

    # Télécharger l'image (sauf pour monitoring qui utilise des images officielles)
    if [ "${STACK_TYPE}" = "monitoring" ]; then
        log_info "Stack monitoring: les images officielles seront téléchargées par docker compose"
        log_info "Le postgres-exporter sera buildé localement"
    else
        log_info "Téléchargement de l'image..."
        docker pull "$image_full"
    fi

    # Démarrer les services
    log_info "Démarrage des services..."
    if [ "${STACK_TYPE}" = "monitoring" ]; then
        docker compose $(get_compose_files "$env") up -d --build
    else
        docker compose $(get_compose_files "$env") up -d
    fi

    print_separator

    # Afficher le statut
    sleep 2
    docker compose $(get_compose_files "$env") ps

    echo ""
    log_success "Déploiement terminé!"
    log_info "Commandes utiles:"
    echo "  - Logs:    ./deploy-registry.sh logs $env"
    echo "  - Status:  ./deploy-registry.sh status $env"
    echo "  - Stop:    ./deploy-registry.sh stop $env"

    # Nettoyer les fichiers temporaires
    cleanup_on_error

    # Désactiver le trap
    trap - EXIT INT TERM
}

# Télécharger une image sans déployer
cmd_pull() {
    local env=$1
    local tag=${2:-${env}-latest}

    local image_full=$(build_image_full "$env" "$tag")

    log_header "TÉLÉCHARGEMENT - $image_full"

    docker pull "$image_full"

    log_success "Image téléchargée"
    docker images "$image_full"
}

# Exporter toutes les variables nécessaires pour docker-compose
export_compose_vars() {
    local env=$1

    # Variables pour substitution YAML dans docker-compose
    # Ces variables sont définies dans .devops.yml et doivent être exportées
    # pour que docker compose puisse les utiliser dans le fichier YAML
    export ENV=$env
    export ENVIRONMENT=$env
    export PROJECT_NAME="${PROJECT_NAME}"
    export REGISTRY_URL="${REGISTRY_URL}"
    export REGISTRY_USERNAME="${REGISTRY_USERNAME}"
    export IMAGE_NAME="${IMAGE_NAME}"
    export COMPOSE_PROJECT_NAME="${PROJECT_NAME:-app}-${env}"
    export APP_SOURCE_DIR="${APP_SOURCE_DIR}"
    export APP_DEST_DIR="${APP_DEST_DIR}"
    export APP_ENTRYPOINT="${APP_ENTRYPOINT}"
    export APP_PYTHON_PATH="${APP_PYTHON_PATH}"
    export WORKDIR="${WORKDIR}"

    # Note: Les variables du fichier .env sont chargées par docker compose via --env-file
    # (pas besoin de sourcer le fichier dans le shell)
}

# Afficher le statut des conteneurs
cmd_status() {
    local env=$1

    export_compose_vars "$env"

    log_header "STATUS - Environnement: $env"

    cd "$DEPLOYMENT_DIR"
    docker compose $(get_compose_files "$env") ps
}

# Afficher les logs
cmd_logs() {
    local env=$1
    local service=${2:-${IMAGE_NAME:-api}}

    export_compose_vars "$env"

    log_header "LOGS - $service ($env)"

    cd "$DEPLOYMENT_DIR"
    docker compose $(get_compose_files "$env") logs -f "$service"
}

# Arrêter les services
cmd_stop() {
    local env=$1

    export_compose_vars "$env"

    log_header "ARRÊT - Environnement: $env"

    cd "$DEPLOYMENT_DIR"
    docker compose $(get_compose_files "$env") down

    log_success "Services arrêtés"
}

# Redémarrer les services
cmd_restart() {
    local env=$1

    export_compose_vars "$env"

    log_header "REDÉMARRAGE - Environnement: $env"

    cd "$DEPLOYMENT_DIR"
    docker compose $(get_compose_files "$env") restart

    log_success "Services redémarrés"
}

# Importer les assets Superset
cmd_superset_import() {
    local env=$1

    log_header "IMPORT SUPERSET - Environnement: $env"

    # Verifier que le script superset-import.sh existe
    local import_script="$SCRIPT_DIR/superset-import.sh"
    if [ ! -f "$import_script" ]; then
        log_error "Script superset-import.sh non trouve: $import_script"
        log_info "Ce script est inclus dans le package de deploiement."
        log_info "Assurez-vous d'utiliser un package a jour."
        return 1
    fi

    # Lancer l'import
    bash "$import_script" --env "$env"
}

# ============================================================================
# MENU D'AIDE
# ============================================================================

show_help() {
    echo -e "${WHITE}${PROJECT_NAME:-DevOps} - Déploiement depuis Registry${NC}"
    echo ""
    echo -e "${CYAN}USAGE:${NC}"
    echo "    $0 <command> <env> [options]"
    echo ""
    echo -e "${CYAN}COMMANDES:${NC}"
    echo ""
    echo -e "${WHITE}Déploiement:${NC}"
    echo "    deploy <env> [tag]        Déployer une image depuis le registry"
    echo "    pull <env> [tag]          Télécharger une image sans déployer"
    echo ""
    echo -e "${WHITE}Gestion:${NC}"
    echo "    list-tags <env>           Lister les tags disponibles dans le registry"
    echo "    status <env>              Afficher le statut des conteneurs"
    echo "    logs <env> [service]      Voir les logs (défaut: ${IMAGE_NAME:-api})"
    echo "    stop <env>                Arrêter les services"
    echo "    restart <env>             Redémarrer les services"
    echo "    superset-import <env>     Importer les assets Superset (dashboards, charts, etc.)"
    echo ""
    echo -e "${CYAN}ENVIRONNEMENTS:${NC}"
    echo "    dev                       Environnement de développement"
    echo "    prod                      Environnement de production"
    echo ""
    echo -e "${CYAN}EXEMPLES:${NC}"
    echo ""
    echo -e "    ${WHITE}Déployer la dernière version dev:${NC}"
    echo "    $0 deploy dev"
    echo ""
    echo -e "    ${WHITE}Déployer une version spécifique:${NC}"
    echo "    $0 deploy dev dev-v20251216-163525-3be7822"
    echo "    $0 deploy prod prod-v1.2.3"
    echo ""
    echo -e "    ${WHITE}Lister les tags disponibles:${NC}"
    echo "    $0 list-tags dev"
    echo "    $0 list-tags prod"
    echo ""
    echo -e "    ${WHITE}Voir les logs:${NC}"
    echo "    $0 logs dev"
    echo "    $0 logs prod ${IMAGE_NAME:-api}"
    echo "    $0 logs dev redis"
    echo ""
    echo -e "    ${WHITE}Gestion des services:${NC}"
    echo "    $0 status dev"
    echo "    $0 stop dev"
    echo "    $0 restart prod"
    echo ""
    echo -e "${CYAN}CONFIGURATION:${NC}"
    echo -e "    Le fichier ${WHITE}.env.registry${NC} doit exister dans deployment/"
    echo ""
    echo "    Copier le fichier d'exemple:"
    echo -e "    ${CYAN}cp deployment/.env.registry.example deployment/.env.registry${NC}"
    echo ""
    echo "    Puis éditer:"
    echo -e "    ${CYAN}nano deployment/.env.registry${NC}"
    echo ""
    echo -e "${CYAN}REGISTRY ACTUEL:${NC}"
    echo "    Type: ${REGISTRY_TYPE:-non configuré}"
    echo "    URL: ${REGISTRY_URL:-non configuré}"
    echo "    Username: ${REGISTRY_USERNAME:-non configuré}"
    echo "    Image: ${IMAGE_NAME:-non configuré}"
    echo ""
}

# ============================================================================
# POINT D'ENTRÉE
# ============================================================================

# Si aucun argument, lancer le mode interactif
if [ $# -eq 0 ]; then
    interactive_menu
    exit 0
fi

COMMAND=$1
shift

case "$COMMAND" in
    interactive)
        interactive_menu
        ;;

    deploy)
        if [ $# -lt 1 ]; then
            log_error "Usage: $0 deploy <env> [tag]"
            exit 1
        fi
        cmd_deploy "$@"
        ;;

    list-tags)
        if [ $# -lt 1 ]; then
            log_error "Usage: $0 list-tags <env>"
            exit 1
        fi
        list_available_tags "$@"
        ;;

    pull)
        if [ $# -lt 1 ]; then
            log_error "Usage: $0 pull <env> [tag]"
            exit 1
        fi
        cmd_pull "$@"
        ;;

    status)
        if [ $# -lt 1 ]; then
            log_error "Usage: $0 status <env>"
            exit 1
        fi
        cmd_status "$@"
        ;;

    logs)
        if [ $# -lt 1 ]; then
            log_error "Usage: $0 logs <env> [service]"
            exit 1
        fi
        cmd_logs "$@"
        ;;

    stop)
        if [ $# -lt 1 ]; then
            log_error "Usage: $0 stop <env>"
            exit 1
        fi
        cmd_stop "$@"
        ;;

    restart)
        if [ $# -lt 1 ]; then
            log_error "Usage: $0 restart <env>"
            exit 1
        fi
        cmd_restart "$@"
        ;;

    superset-import)
        if [ $# -lt 1 ]; then
            log_error "Usage: $0 superset-import <env>"
            exit 1
        fi
        cmd_superset_import "$@"
        ;;

    help|--help|-h)
        show_help
        ;;

    *)
        log_error "Commande inconnue: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac
