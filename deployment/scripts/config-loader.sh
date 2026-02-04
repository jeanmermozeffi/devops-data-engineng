#!/bin/bash

# ============================================================================
# Configuration Loader - Charge les variables depuis .devops.yml
# ============================================================================
#
# Ce script est sourcé par tous les scripts de déploiement pour charger
# dynamiquement la configuration depuis le fichier .devops.yml du projet.
#
# Usage:
#   source "$(dirname "$0")/config-loader.sh"
#   load_devops_config
#
# ============================================================================

# ============================================================================
# DÉTECTION AUTOMATIQUE DU PROJET
# ============================================================================

detect_project_root() {
    local current_dir="$1"

    # Remonter jusqu'à trouver .devops.yml ou atteindre la racine
    while [ "$current_dir" != "/" ]; do
        if [ -f "$current_dir/.devops.yml" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done

    # Si PROJECT_ROOT est défini (par le CLI devops), l'utiliser
    if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.devops.yml" ]; then
        echo "$PROJECT_ROOT"
        return 0
    fi

    return 1
}

# ============================================================================
# CHARGEMENT DE LA CONFIGURATION
# ============================================================================

load_devops_config() {
    # Déterminer le PROJECT_ROOT
    if [ -z "$PROJECT_ROOT" ]; then
        # Essayer de détecter automatiquement
        PROJECT_ROOT=$(detect_project_root "$(pwd)")

        if [ -z "$PROJECT_ROOT" ]; then
            # Échec de détection, utiliser le répertoire courant
            PROJECT_ROOT="$(pwd)"
        fi
    fi

    export PROJECT_ROOT

    local config_file="$PROJECT_ROOT/.devops.yml"

    # Vérifier si le fichier existe
    if [ ! -f "$config_file" ]; then
        # Mode legacy : ne pas échouer, utiliser les valeurs par défaut
        log_warn "Fichier .devops.yml non trouvé, utilisation des valeurs par défaut" 2>/dev/null || \
            echo "[WARN] Fichier .devops.yml non trouvé, utilisation des valeurs par défaut" >&2
        return 1
    fi

    # Parser le fichier YAML (simple, supporte uniquement clés: valeur)
    while IFS=': ' read -r key value || [ -n "$key" ]; do
        # Ignorer commentaires et lignes vides
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        [[ $key =~ ^[[:space:]]*$ ]] && continue

        # Nettoyer la valeur (supprimer espaces, quotes, commentaires inline)
        value=$(echo "$value" | sed 's/#.*//' | xargs | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")

        # Ignorer les valeurs vides
        [[ -z "$value" ]] && continue

        # Export des variables connues
        case "$key" in
            # Informations du projet
            project_name)
                export PROJECT_NAME="$value"
                ;;
            compose_project_name)
                export COMPOSE_PROJECT_NAME="$value"
                ;;

            # Docker Registry
            registry_username)
                export REGISTRY_USERNAME="$value"
                ;;
            registry_url)
                export REGISTRY_URL="$value"
                ;;
            image_name)
                export IMAGE_NAME="$value"
                ;;
            registry_token)
                export REGISTRY_TOKEN="$value"
                ;;
            registry_type)
                export REGISTRY_TYPE="$value"
                ;;

            # Git configuration
            git_repo)
                export GIT_REPO="$value"
                ;;
            git_username)
                export GIT_USERNAME="$value"
                ;;
            github_token)
                export GITHUB_TOKEN="$value"
                ;;

            # Branches par environnement
            dev_branch)
                export DEV_BRANCH="$value"
                ;;
            staging_branch)
                export STAGING_BRANCH="$value"
                ;;
            prod_branch)
                export PROD_BRANCH="$value"
                ;;

            # Ports
            dev_port)
                export DEV_PORT="$value"
                ;;
            staging_port)
                export STAGING_PORT="$value"
                ;;
            prod_port)
                export PROD_PORT="$value"
                ;;
            redis_dev_port)
                export REDIS_DEV_PORT="$value"
                ;;
            redis_staging_port)
                export REDIS_STAGING_PORT="$value"
                ;;
            redis_prod_port)
                export REDIS_PROD_PORT="$value"
                ;;

            # PostgreSQL (si présent)
            postgres_user)
                export POSTGRES_USER="$value"
                ;;
            postgres_password)
                export POSTGRES_PASSWORD="$value"
                ;;
            postgres_db)
                export POSTGRES_DB="$value"
                ;;
            postgres_dev_port)
                export POSTGRES_DEV_PORT="$value"
                ;;
            postgres_staging_port)
                export POSTGRES_STAGING_PORT="$value"
                ;;
            postgres_prod_port)
                export POSTGRES_PROD_PORT="$value"
                ;;

            # Structure du projet
            deployment_dir)
                export DEPLOYMENT_DIR="$value"
                ;;
            dockerfile_dir)
                export DOCKERFILE_DIR="$value"
                ;;

            # SSH (pour create-deployment-package.sh)
            ssh_host)
                export SSH_HOST="$value"
                ;;
            ssh_user)
                export SSH_USER="$value"
                ;;
            ssh_port)
                export SSH_PORT="$value"
                ;;
            ssh_path)
                export SSH_PATH="$value"
                ;;
            ssh_identity_file)
                export SSH_IDENTITY_FILE="$value"
                ;;

            # Ignorer les sections et sous-clés YAML
            compose_files|compose_files_registry)
                # Ces sections seront traitées séparément si nécessaire
                ;;

            *)
                # Variables personnalisées : les exporter automatiquement
                # Convertir en MAJUSCULES avec underscores
                local var_name=$(echo "$key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                export "$var_name=$value"
                ;;
        esac
    done < "$config_file"

    # ========================================================================
    # DÉFINIR LES VALEURS PAR DÉFAUT
    # ========================================================================

    # Nom du projet
    export PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_ROOT")}"
    export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$PROJECT_NAME}"
    export IMAGE_NAME="${IMAGE_NAME:-$PROJECT_NAME}"

    # Registry
    export REGISTRY_TYPE="${REGISTRY_TYPE:-dockerhub}"
    export REGISTRY_URL="${REGISTRY_URL:-docker.io}"
    export REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"

    # Branches
    export DEV_BRANCH="${DEV_BRANCH:-dev}"
    export STAGING_BRANCH="${STAGING_BRANCH:-staging}"
    export PROD_BRANCH="${PROD_BRANCH:-main}"

    # Ports
    export DEV_PORT="${DEV_PORT:-8001}"
    export STAGING_PORT="${STAGING_PORT:-8002}"
    export PROD_PORT="${PROD_PORT:-8000}"
    export REDIS_DEV_PORT="${REDIS_DEV_PORT:-6379}"
    export REDIS_STAGING_PORT="${REDIS_STAGING_PORT:-6381}"
    export REDIS_PROD_PORT="${REDIS_PROD_PORT:-6380}"

    # Structure du projet
    export DEPLOYMENT_DIR="${DEPLOYMENT_DIR:-deployment}"
    export DOCKERFILE_DIR="${DOCKERFILE_DIR:-docker}"

    # SSH
    export SSH_USER="${SSH_USER:-root}"
    export SSH_PORT="${SSH_PORT:-22}"
    export SSH_PATH="${SSH_PATH:-/srv/$PROJECT_NAME}"

    # Variables calculées
    export DEPLOYMENT_PATH="$PROJECT_ROOT/$DEPLOYMENT_DIR"
    export DOCKERFILE_PATH="$DEPLOYMENT_PATH/$DOCKERFILE_DIR"

    return 0
}

# ============================================================================
# FONCTION UTILITAIRE : Obtenir la branche Git pour un environnement
# ============================================================================

get_branch_for_env() {
    local env=$1
    case "$env" in
        dev)
            echo "${DEV_BRANCH:-dev}"
            ;;
        staging)
            echo "${STAGING_BRANCH:-staging}"
            ;;
        prod)
            echo "${PROD_BRANCH:-main}"
            ;;
        *)
            echo "main"
            ;;
    esac
}

# ============================================================================
# FONCTION UTILITAIRE : Obtenir le port pour un environnement
# ============================================================================

get_port_for_env() {
    local env=$1
    local service=${2:-api}

    case "$service" in
        api)
            case "$env" in
                dev) echo "${DEV_PORT:-8001}" ;;
                staging) echo "${STAGING_PORT:-8002}" ;;
                prod) echo "${PROD_PORT:-8000}" ;;
                *) echo "8000" ;;
            esac
            ;;
        redis)
            case "$env" in
                dev) echo "${REDIS_DEV_PORT:-6379}" ;;
                staging) echo "${REDIS_STAGING_PORT:-6381}" ;;
                prod) echo "${REDIS_PROD_PORT:-6380}" ;;
                *) echo "6379" ;;
            esac
            ;;
        postgres)
            case "$env" in
                dev) echo "${POSTGRES_DEV_PORT:-5432}" ;;
                staging) echo "${POSTGRES_STAGING_PORT:-5433}" ;;
                prod) echo "${POSTGRES_PROD_PORT:-5434}" ;;
                *) echo "5432" ;;
            esac
            ;;
        *)
            echo "8000"
            ;;
    esac
}

# ============================================================================
# FONCTION UTILITAIRE : Construire le nom de conteneur
# ============================================================================

get_container_name() {
    local env=$1
    local service=$2
    echo "${COMPOSE_PROJECT_NAME:-$PROJECT_NAME}-${service}-${env}"
}

# ============================================================================
# FONCTION UTILITAIRE : Afficher la configuration (debug)
# ============================================================================

show_config() {
    echo "========================================" >&2
    echo "Configuration chargée depuis .devops.yml" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "Projet:" >&2
    echo "  PROJECT_NAME          = $PROJECT_NAME" >&2
    echo "  COMPOSE_PROJECT_NAME  = $COMPOSE_PROJECT_NAME" >&2
    echo "  PROJECT_ROOT          = $PROJECT_ROOT" >&2
    echo "" >&2
    echo "Registry:" >&2
    echo "  REGISTRY_TYPE         = $REGISTRY_TYPE" >&2
    echo "  REGISTRY_URL          = $REGISTRY_URL" >&2
    echo "  REGISTRY_USERNAME     = $REGISTRY_USERNAME" >&2
    echo "  IMAGE_NAME            = $IMAGE_NAME" >&2
    echo "" >&2
    echo "Git:" >&2
    echo "  GIT_REPO              = $GIT_REPO" >&2
    echo "  DEV_BRANCH            = $DEV_BRANCH" >&2
    echo "  STAGING_BRANCH        = $STAGING_BRANCH" >&2
    echo "  PROD_BRANCH           = $PROD_BRANCH" >&2
    echo "" >&2
    echo "Ports:" >&2
    echo "  DEV_PORT              = $DEV_PORT" >&2
    echo "  STAGING_PORT          = $STAGING_PORT" >&2
    echo "  PROD_PORT             = $PROD_PORT" >&2
    echo "" >&2
    echo "Structure:" >&2
    echo "  DEPLOYMENT_DIR        = $DEPLOYMENT_DIR" >&2
    echo "  DOCKERFILE_DIR        = $DOCKERFILE_DIR" >&2
    echo "  DEPLOYMENT_PATH       = $DEPLOYMENT_PATH" >&2
    echo "  DOCKERFILE_PATH       = $DOCKERFILE_PATH" >&2
    echo "========================================" >&2
}

# Export des fonctions pour qu'elles soient disponibles dans les scripts
export -f get_branch_for_env 2>/dev/null || true
export -f get_port_for_env 2>/dev/null || true
export -f get_container_name 2>/dev/null || true
export -f show_config 2>/dev/null || true
