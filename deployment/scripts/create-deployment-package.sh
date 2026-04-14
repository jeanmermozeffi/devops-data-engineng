#!/bin/bash

# ============================================================================
# Création du package de déploiement minimal pour VPS
# ============================================================================
#
# Ce script crée un package contenant UNIQUEMENT les fichiers nécessaires
# pour déployer depuis Docker Hub (pas le code source)
#
# Mode interactif avec option de copie SSH automatique
#
# ============================================================================

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

# Fonctions d'affichage
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║$(printf "%52s" " " | tr ' ' ' ')║${NC}"
    echo -e "${CYAN}║  ${WHITE}$1${CYAN}$(printf "%$((50-${#1}))s" " ")║${NC}"
    echo -e "${CYAN}║$(printf "%52s" " " | tr ' ' ' ')║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
}

print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
}

sed_inplace() {
    local expr="$1"
    local file="$2"

    if sed --version >/dev/null 2>&1; then
        sed -i "$expr" "$file"
    else
        sed -i "" "$expr" "$file"
    fi
}


# ============================================================================
# CHARGEMENT DE LA CONFIGURATION
# ============================================================================

# Déterminer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Charger la configuration depuis .devops.yml
source "$SCRIPT_DIR/config-loader.sh"
load_devops_config

# Configuration par défaut (peut être surchargée par .devops.yml ou .env.deployment)
PROJECT_DIR="${PROJECT_ROOT:-$(pwd)}"
# Dossier packages dans devops-enginering (non versionné)
PACKAGES_BASE_DIR="$(dirname "$SCRIPT_DIR")/../packages"
mkdir -p "$PACKAGES_BASE_DIR"
DEPLOYMENT_SUBDIR="${DEPLOYMENT_DIR:-deployment}"

# Identité projet (source de vérité pour le nom du package local)
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

# Déterminer le suffixe d'environnement (dev/staging/prod) depuis ENV ou server_deploy_path
detect_deploy_env_suffix() {
    local env_candidate="${ENV:-}"
    local path_basename=""

    if [ -z "$env_candidate" ] && [ -n "${SERVER_DEPLOY_PATH:-}" ]; then
        path_basename="$(basename "$SERVER_DEPLOY_PATH")"
        if [[ "$path_basename" =~ -(dev|staging|prod)$ ]]; then
            env_candidate="${BASH_REMATCH[1]}"
        fi
    fi

    case "$env_candidate" in
        dev|staging|prod) echo "$env_candidate" ;;
        *) echo "" ;;
    esac
}

resolve_ssh_path_for_env() {
    local target_env="$1"
    local source_path="${SERVER_DEPLOY_PATH:-${SSH_PATH:-/srv/home/${PROJECT_NAME}}}"
    local path_basename
    local path_parent
    local path_prefix

    path_basename="$(basename "$source_path")"
    path_parent="$(dirname "$source_path")"

    if [[ "$path_basename" =~ ^(.+)-(dev|staging|prod)$ ]]; then
        path_prefix="${BASH_REMATCH[1]}"
        echo "${path_parent}/${path_prefix}-${target_env}"
    else
        echo "$source_path"
    fi
}

# Déterminer un stack_type fiable, y compris quand .devops.yml est imbriqué.
detect_effective_stack_type() {
    local stack="${STACK_TYPE:-}"
    local config_file="${PROJECT_DIR}/.devops.yml"
    local detected=""

    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        detected="$(sed -nE 's/^[[:space:]]*stack_type:[[:space:]]*["'\'']?([^"'\''#[:space:]]+)["'\'']?.*$/\1/p' "$config_file" | head -n1)"
    fi

    if [ -n "$detected" ]; then
        stack="$detected"
    fi

    echo "${stack:-fastapi-redis}"
}

# Construire le chemin package local.
# PACKAGE_NAME_MODE:
# - fixed   : toujours PROJECT_NAME
# - derived : PROJECT_NAME-<env> si env détecté
# - auto    : comme derived, sauf streaming-kafka => fixed
resolve_package_dir() {
    local mode="${PACKAGE_NAME_MODE:-auto}"
    local effective_stack=""
    local env_suffix=""
    local package_name="$PROJECT_NAME"
    effective_stack="$(detect_effective_stack_type)"

    if [ "$mode" = "auto" ] && [ "$effective_stack" = "streaming-kafka" ]; then
        mode="fixed"
    fi

    if [ "$mode" = "derived" ] || [ "$mode" = "auto" ]; then
        env_suffix="$(detect_deploy_env_suffix)"
        if [ -n "$env_suffix" ] && [[ "$package_name" != *"-${env_suffix}" ]]; then
            package_name="${package_name}-${env_suffix}"
        fi
    fi

    echo "${PACKAGES_BASE_DIR}/${package_name}"
}

# Mapper les variables SSH depuis .devops.yml (SERVER_*) vers les variables du script (SSH_*)
SSH_TRANSFER=false
SSH_HOST="${SERVER_HOST:-${SSH_HOST:-}}"
SSH_USER="${SERVER_USER:-${SSH_USER:-root}}"
SSH_PORT="${SERVER_PORT:-${SSH_PORT:-22}}"
SSH_PATH="${SERVER_DEPLOY_PATH:-${SSH_PATH:-/srv/home/${PROJECT_NAME}}}"
SSH_USE_PASSWORD=false
SSH_IDENTITY_FILE="${SERVER_SSH_KEY:-${SSH_IDENTITY_FILE:-}}"

# Nom du package local (dynamique selon mode + stack)
PACKAGE_DIR="${PACKAGE_DIR:-$(resolve_package_dir)}"

# Registry depuis .devops.yml (avec fallback)
REGISTRY_TYPE="${REGISTRY_TYPE:-dockerhub}"
REGISTRY_URL="${REGISTRY_URL:-docker.io}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"
IMAGE_NAME="${IMAGE_NAME:-$(basename "$PROJECT_DIR")}"

# Option de chiffrement (désactivé par défaut)
ENCRYPT_ENV_FILES="${ENCRYPT_ENV_FILES:-false}"
# Inclure les outils Superset et les agents monitoring.
# Valeurs: true|false|auto|required
# Vide = sera défini par configure_stack_assets() selon le stack_type.
# Surchargeable via variable d'environnement ou .env.deployment avant l'appel.
INCLUDE_SUPERSET_ASSETS="${INCLUDE_SUPERSET_ASSETS:-}"
INCLUDE_MONITORING="${INCLUDE_MONITORING:-}"

# Configurer les assets selon le stack_type.
# Respecte les surcharges explicites (env ou .env.deployment) si déjà définies.
# Appelé au début de create_package().
configure_stack_assets() {
    local stack="${STACK_TYPE:-}"
    log_info "Stack type: ${stack:-non défini}"

    case "$stack" in
        orchestrator)
            # Airflow + Talend: agents monitoring obligatoires
            [ -z "${INCLUDE_MONITORING}" ]      && INCLUDE_MONITORING="required"
            [ -z "${INCLUDE_SUPERSET_ASSETS}" ] && INCLUDE_SUPERSET_ASSETS="false"
            log_info "  → Agents monitoring : requis | Superset : non"
            ;;
        streaming-kafka)
            # Kafka: agents monitoring obligatoires
            [ -z "${INCLUDE_MONITORING}" ]      && INCLUDE_MONITORING="required"
            [ -z "${INCLUDE_SUPERSET_ASSETS}" ] && INCLUDE_SUPERSET_ASSETS="false"
            log_info "  → Agents monitoring : requis | Superset : non"
            ;;
        reporting-superset)
            # Superset BI: assets Superset obligatoires, monitoring optionnel
            [ -z "${INCLUDE_MONITORING}" ]      && INCLUDE_MONITORING="auto"
            [ -z "${INCLUDE_SUPERSET_ASSETS}" ] && INCLUDE_SUPERSET_ASSETS="true"
            log_info "  → Agents monitoring : optionnel | Superset : requis"
            ;;
        monitoring)
            # Stack monitoring central: pas d'agents secondaires (il EST le monitoring)
            [ -z "${INCLUDE_MONITORING}" ]      && INCLUDE_MONITORING="false"
            [ -z "${INCLUDE_SUPERSET_ASSETS}" ] && INCLUDE_SUPERSET_ASSETS="false"
            log_info "  → Stack monitoring central (agents secondaires non inclus)"
            ;;
        *)
            # fastapi-redis, api, etc.: tout optionnel (inclus si présent)
            [ -z "${INCLUDE_MONITORING}" ]      && INCLUDE_MONITORING="auto"
            [ -z "${INCLUDE_SUPERSET_ASSETS}" ] && INCLUDE_SUPERSET_ASSETS="auto"
            log_info "  → Agents monitoring : optionnel | Superset : optionnel"
            ;;
    esac
}

resolve_monitoring_dir_for_package() {
    local candidate
    local candidates=()

    candidates+=("$PROJECT_DIR/$DEPLOYMENT_SUBDIR/monitoring")
    if [ -n "${DEVOPS_MONITORING_SOURCE:-}" ]; then
        candidates+=("${DEVOPS_MONITORING_SOURCE}")
    fi
    candidates+=("$SCRIPT_DIR/../monitoring")
    # Chemins communs selon l'OS (Linux / macOS)
    candidates+=("$HOME/PycharmProjects/cicbi-monitoring-platform/deployment/monitoring")
    candidates+=("/home/jeeff/PycharmProjects/cicbi-monitoring-platform/deployment/monitoring")

    for candidate in "${candidates[@]}"; do
        if [ -d "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

load_env_config() {
    local env_file="$PROJECT_DIR/deployment/.env.deployment"
    local example_file="$PROJECT_DIR/deployment/.env.deployment.example"

    if [ -f "$env_file" ]; then
        log_info "Chargement de la configuration supplémentaire depuis: $env_file"

        # Charger les variables sans exporter dans l'environnement
        set -a
        source "$env_file"
        set +a

        log_success "Configuration supplémentaire chargée"
    else
        log_info "Fichier .env.deployment non trouvé (optionnel)"
        if [ -f "$example_file" ]; then
            log_info "Pour personnaliser, copiez:"
            echo "  cp deployment/.env.deployment.example deployment/.env.deployment"
            echo ""
        fi
    fi
}

# Charger la configuration personnalisée si elle existe
load_env_config

# Fonction pour préparer les options SSH
prepare_ssh_options() {
    SSH_OPTIONS=""
    if [ -n "$SSH_IDENTITY_FILE" ]; then
        # Expand tilde in path
        local expanded_path="${SSH_IDENTITY_FILE/#\~/$HOME}"
        if [ -f "$expanded_path" ]; then
            SSH_OPTIONS="-i $expanded_path"
            SSH_IDENTITY_FILE="$expanded_path"
        else
            log_warn "Fichier de clé SSH non trouvé: $SSH_IDENTITY_FILE"
            SSH_IDENTITY_FILE=""
        fi
    fi
}

# Préparer les options SSH initiales
prepare_ssh_options

# ============================================================================
# FONCTIONS INTERACTIVES
# ============================================================================

ask_yes_no() {
    local question=$1
    local default=${2:-n}

    if [ "$default" == "y" ]; then
        read -p "$question (Y/n): " response
        response=${response:-y}
    else
        read -p "$question (y/N): " response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

ask_input() {
    local prompt=$1
    local default=$2
    local var_name=$3

    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " response
        response=${response:-$default}
    else
        read -p "$prompt: " response
    fi

    eval "$var_name=\"$response\""
}

rotate_env_secrets_if_required() {
    local target_env="$1"
    local should_rotate="false"
    local ask_rotation="false"

    if [ -z "$target_env" ]; then
        log_warn "Rotation des secrets ignorée: environnement non détecté"
        return 0
    fi

    case "$target_env" in
        staging|prod)
            should_rotate="true"
            ;;
        dev)
            ask_rotation="true"
            ;;
        *)
            log_warn "Rotation des secrets ignorée: environnement invalide '$target_env'"
            return 0
            ;;
    esac

    if [ "$ask_rotation" = "true" ]; then
        if ask_yes_no "Rotation des variables sensibles pour '${target_env}'" "n"; then
            should_rotate="true"
        fi
    fi

    if [ "$should_rotate" != "true" ]; then
        log_info "Rotation des secrets non demandée pour '${target_env}'"
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        log_error "python3 est requis pour la rotation des secrets"
        return 1
    fi

    local rotation_script="$SCRIPT_DIR/rotate-env-secrets.py"
    if [ ! -f "$rotation_script" ]; then
        log_error "Script de rotation introuvable: $rotation_script"
        return 1
    fi

    log_info "Rotation des secrets pour '${target_env}' en cours..."
    if ! python3 "$rotation_script" --project-dir "$PROJECT_DIR" --env "$target_env"; then
        log_error "Échec de la rotation des secrets pour '${target_env}'"
        log_info "Configuration attendue dans ${PROJECT_DIR}/.env.rotation.yml ou ${PROJECT_DIR}/.devops.yml"
        return 1
    fi

    log_success "✓ Rotation des secrets terminée pour '${target_env}'"
    return 0
}

configure_ssh() {
    echo ""
    print_header "Configuration SSH"
    echo ""
    local env_default=""

    env_default="${ENV:-$(detect_deploy_env_suffix)}"
    if [ -z "$env_default" ]; then
        env_default="dev"
    fi

    while true; do
        ask_input "Environnement cible (dev/staging/prod)" "$env_default" ENV
        ENV="$(printf '%s' "$ENV" | tr '[:upper:]' '[:lower:]')"
        case "$ENV" in
            dev|staging|prod) break ;;
            *)
                log_warn "Environnement invalide: '$ENV' (attendu: dev, staging ou prod)"
                ;;
        esac
    done

    # Ajuster le chemin distant selon l'environnement choisi
    SSH_PATH="$(resolve_ssh_path_for_env "$ENV")"

    # Vérifier si une configuration existe déjà
    if [ -n "$SSH_HOST" ]; then
        log_info "Configuration serveur détectée depuis .devops.yml:"
        echo ""
        print_separator
        echo -e "${WHITE}Configuration actuelle:${NC}"
        echo -e "  Environnement: ${CYAN}${ENV}${NC}"
        echo -e "  Serveur    : ${CYAN}${SSH_USER}@${SSH_HOST}:${SSH_PORT}${NC}"
        echo -e "  Destination: ${CYAN}${SSH_PATH}${NC}"
        if [ -n "$SSH_IDENTITY_FILE" ]; then
            echo -e "  Clé SSH    : ${CYAN}${SSH_IDENTITY_FILE}${NC}"
        fi
        echo -e "  Auth       : ${CYAN}$([ "$SSH_USE_PASSWORD" == "true" ] && echo "Mot de passe" || echo "Clé SSH")${NC}"
        print_separator
        echo ""

        if ask_yes_no "Utiliser cette configuration" "y"; then
            return 0
        fi
        echo ""
        log_info "Modification de la configuration..."
        echo ""
    else
        log_info "Configuration de la connexion au serveur distant"
        echo ""
    fi

    # Hôte
    ask_input "Adresse IP ou hostname du serveur" "$SSH_HOST" SSH_HOST

    # Utilisateur
    ask_input "Nom d'utilisateur SSH" "${SSH_USER:-cicbi}" SSH_USER

    # Port
    ask_input "Port SSH" "${SSH_PORT:-22}" SSH_PORT

    # Chemin destination
    ask_input "Chemin de destination sur le serveur" "${SSH_PATH:-/srv/home/${PROJECT_NAME}}" SSH_PATH

    # Méthode d'authentification
    echo ""
    log_info "Méthode d'authentification:"
    echo "  1) Clé SSH (recommandé)"
    echo "  2) Mot de passe"
    echo ""
    ask_input "Votre choix" "1" auth_choice

    if [ "$auth_choice" == "2" ]; then
        SSH_USE_PASSWORD=true
        log_warn "Mode mot de passe sélectionné (sshpass requis)"
    fi

    # Résumé
    echo ""
    print_separator
    echo -e "${WHITE}Récapitulatif SSH:${NC}"
    echo -e "  Environnement: ${CYAN}${ENV}${NC}"
    echo -e "  Serveur    : ${CYAN}${SSH_USER}@${SSH_HOST}:${SSH_PORT}${NC}"
    echo -e "  Destination: ${CYAN}${SSH_PATH}${NC}"
    echo -e "  Auth       : ${CYAN}$([ "$SSH_USE_PASSWORD" == "true" ] && echo "Mot de passe" || echo "Clé SSH")${NC}"
    print_separator
    echo ""

    if ! ask_yes_no "Confirmer cette configuration" "y"; then
        log_warn "Configuration annulée"
        return 1
    fi

    return 0
}

# ============================================================================
# MENU PRINCIPAL
# ============================================================================

show_menu() {
    clear
    print_header "Création du package de déploiement"
    echo ""

    log_info "Projet source: ${CYAN}$PROJECT_DIR${NC}"
    log_info "Package destination: ${CYAN}$PACKAGE_DIR${NC}"
    echo ""

    print_separator
    echo -e "${WHITE}Options de création:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Créer le package uniquement"
    echo -e "  ${CYAN}2)${NC} Créer et copier vers le serveur (SSH)"
    echo -e "  ${CYAN}3)${NC} Configuration avancée"
    echo -e "  ${RED}4)${NC} ${RED}Nettoyer le serveur (DANGER)${NC}"
    echo ""
    echo -e "  ${CYAN}0)${NC} Quitter"
    echo ""
    print_separator
    echo ""
}

# ============================================================================
# CRÉATION DU PACKAGE
# ============================================================================

create_package() {
    print_header "Création du package"
    echo ""
    local target_deploy_env=""
    local copy_all_env_compose="false"

    # Configurer les assets selon le stack_type
    configure_stack_assets

    target_deploy_env="$(detect_deploy_env_suffix)"
    if [ -n "$target_deploy_env" ]; then
        log_info "Environnement cible détecté: ${target_deploy_env}"
    else
        log_warn "Environnement cible non détecté (ENV ou SERVER_DEPLOY_PATH)"
    fi

    if ! rotate_env_secrets_if_required "$target_deploy_env"; then
        return 1
    fi

    # Nettoyer et créer le dossier
    log_info "Préparation du dossier..."
    rm -rf "$PACKAGE_DIR"
    mkdir -p "$PACKAGE_DIR/scripts"

    # Copier les fichiers docker-compose depuis le projet cible
    log_info "Copie des fichiers docker-compose..."
    COMPOSE_SRC="$PROJECT_DIR/$DEPLOYMENT_SUBDIR"

    if ask_yes_no "Copier les docker-compose de tous les environnements" "n"; then
        copy_all_env_compose="true"
    fi

    if [ "$copy_all_env_compose" = "true" ]; then
        # Copier les fichiers docker-compose de tous les environnements
        for compose_file in docker-compose.yml docker-compose.registry.yml \
                            docker-compose.dev.yml docker-compose.dev-registry.yml \
                            docker-compose.staging.yml docker-compose.staging-registry.yml \
                            docker-compose.prod.yml docker-compose.prod-registry.yml; do
            if [ -f "$COMPOSE_SRC/$compose_file" ]; then
                cp "$COMPOSE_SRC/$compose_file" "$PACKAGE_DIR/"
                log_success "✓ $compose_file copié"
            else
                log_warn "⚠️  $compose_file non trouvé (optionnel)"
            fi
        done
    else
        if [ -n "$target_deploy_env" ]; then
            # Par défaut: copier uniquement les compose communs + ceux de l'environnement cible
            for compose_file in docker-compose.yml docker-compose.registry.yml \
                                "docker-compose.${target_deploy_env}.yml" \
                                "docker-compose.${target_deploy_env}-registry.yml"; do
                if [ -f "$COMPOSE_SRC/$compose_file" ]; then
                    cp "$COMPOSE_SRC/$compose_file" "$PACKAGE_DIR/"
                    log_success "✓ $compose_file copié"
                else
                    log_warn "⚠️  $compose_file non trouvé (optionnel)"
                fi
            done
        else
            log_warn "⚠️  Environnement non détecté: copie de tous les docker-compose.*"
            for compose_file in docker-compose.yml docker-compose.registry.yml \
                                docker-compose.dev.yml docker-compose.dev-registry.yml \
                                docker-compose.staging.yml docker-compose.staging-registry.yml \
                                docker-compose.prod.yml docker-compose.prod-registry.yml; do
                if [ -f "$COMPOSE_SRC/$compose_file" ]; then
                    cp "$COMPOSE_SRC/$compose_file" "$PACKAGE_DIR/"
                    log_success "✓ $compose_file copié"
                else
                    log_warn "⚠️  $compose_file non trouvé (optionnel)"
                fi
            done
        fi
    fi

    # Inclure les agents monitoring selon le stack_type
    if [ "${INCLUDE_MONITORING}" != "false" ]; then
        MONITORING_DIR_SRC="$(resolve_monitoring_dir_for_package || true)"
        if [ -n "$MONITORING_DIR_SRC" ] && [ -d "$MONITORING_DIR_SRC" ]; then
            mkdir -p "$PACKAGE_DIR/deployment/monitoring"

            if [ -f "$MONITORING_DIR_SRC/README.md" ]; then
                cp "$MONITORING_DIR_SRC/README.md" "$PACKAGE_DIR/deployment/monitoring/"
            fi
            if [ -f "$MONITORING_DIR_SRC/compose-labels-snippet.yml" ]; then
                cp "$MONITORING_DIR_SRC/compose-labels-snippet.yml" "$PACKAGE_DIR/deployment/monitoring/"
            fi
            if [ -d "$MONITORING_DIR_SRC/agents" ]; then
                cp -r "$MONITORING_DIR_SRC/agents" "$PACKAGE_DIR/deployment/monitoring/"
                log_success "✓ deployment/monitoring/agents copié depuis: $MONITORING_DIR_SRC"
            else
                log_warn "⚠️  Dossier agents/ non trouvé dans $MONITORING_DIR_SRC"
            fi
        else
            if [ "${INCLUDE_MONITORING}" = "required" ]; then
                log_error "Agents monitoring REQUIS pour le stack '${STACK_TYPE}' mais introuvables"
                log_error "Attendu: $PROJECT_DIR/$DEPLOYMENT_SUBDIR/monitoring"
                log_info "Conseil: créez le dossier deployment/monitoring/agents/ dans le projet"
                exit 1
            else
                log_info "Agents monitoring non détectés (optionnel pour ce stack)"
                log_info "Astuce: définissez DEVOPS_MONITORING_SOURCE pour forcer la source"
            fi
        fi
    else
        log_info "Agents monitoring exclus (stack '${STACK_TYPE}')"
    fi

    # Ajuster les chemins relatifs dans les fichiers docker-compose pour le package minimal
    # En développement, les fichiers sont dans deployment/ donc ../.env.* pointe vers la racine
    # Dans le package minimal, tout est à la racine donc il faut ./.env.*
    log_info "Ajustement des chemins relatifs pour le package minimal..."
    for compose_file in "$PACKAGE_DIR"/docker-compose*.yml; do
        if [ -f "$compose_file" ]; then
            # Remplacer ../.env. par ./.env. (chemins relatifs)
            sed_inplace 's|\.\./\.env\.|./.env.|g' "$compose_file"
        fi
    done
    log_success "✓ Chemins .env ajustés"

    # Détecter et copier les ressources locales référencées dans les docker-compose
    # (build contexts, volumes montés avec chemins relatifs ../*)
    # Ex: postgres-exporter (build), prometheus/ (config), grafana/ (dashboards)
    log_info "Détection des ressources locales dans les docker-compose..."
    LOCAL_RESOURCES_COPIED=0
    # Liste des chemins déjà traités (éviter les doublons) compatible Bash 3 (macOS)
    COPIED_PATHS=""
    is_path_already_copied() {
        local path="$1"
        printf '%s\n' "$COPIED_PATHS" | grep -Fxq "$path"
    }
    mark_path_as_copied() {
        local path="$1"
        COPIED_PATHS="${COPIED_PATHS}"$'\n'"$path"
    }

    for compose_file in "$PACKAGE_DIR"/docker-compose*.yml; do
        [ -f "$compose_file" ] || continue

        # Extraire TOUS les chemins ../* des docker-compose :
        #   - build context:  "context: ../exporters/..."
        #   - volume mounts:  "- ../prometheus/prometheus.yml:/etc/..."
        #   - env_file:       "- ../.env.${ENV}" (déjà géré séparément)
        while IFS= read -r raw_path; do
            # Nettoyer : retirer prefixe YAML (context:, - ), suffixe (:ro, :rw, :/dest)
            local clean_path="$raw_path"
            clean_path=$(echo "$clean_path" | sed 's/^[[:space:]]*context:[[:space:]]*//; s/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*$//')
            # Retirer le mapping de destination du volume (tout après le premier : sauf si c'est un chemin Windows)
            clean_path=$(echo "$clean_path" | sed 's/^\([^:]*\):.*/\1/')
            # Retirer quotes
            clean_path=$(echo "$clean_path" | sed 's/^["'"'"']//; s/["'"'"']$//')

            # Ignorer les chemins .env (déjà gérés), les chemins absolus, les chemins vides
            [[ -z "$clean_path" ]] && continue
            [[ "$clean_path" == /* ]] && continue
            [[ "$clean_path" == *".env."* ]] && continue
            # Ne traiter que les chemins ../
            [[ "$clean_path" != ../* ]] && continue

            # Chemin relatif dans le package (sans le ../)
            local pkg_relative="${clean_path#../}"
            # Pour un fichier comme ../prometheus/prometheus.yml, on copie le dossier parent
            # Pour un dossier comme ../prometheus/rules/, on copie le dossier
            local source_path="$PROJECT_DIR/$pkg_relative"

            # Déterminer si c'est un fichier ou un dossier
            # Retirer le trailing slash pour les dossiers
            source_path="${source_path%/}"
            pkg_relative="${pkg_relative%/}"

            # Calculer le dossier à copier (le dossier top-level)
            # Ex: prometheus/prometheus.yml -> on copie prometheus/
            #     grafana/provisioning/ -> on copie grafana/
            local top_dir=$(echo "$pkg_relative" | cut -d'/' -f1)

            # Vérifier si déjà copié
            if is_path_already_copied "$top_dir"; then
                continue
            fi

            local source_top="$PROJECT_DIR/$top_dir"
            local dest_top="$PACKAGE_DIR/$top_dir"

            if [ -d "$source_top" ]; then
                cp -r "$source_top" "$dest_top"
                log_success "✓ Dossier copié: $top_dir/"
                mark_path_as_copied "$top_dir"
                LOCAL_RESOURCES_COPIED=$((LOCAL_RESOURCES_COPIED + 1))
            elif [ -f "$source_path" ]; then
                mkdir -p "$(dirname "$PACKAGE_DIR/$pkg_relative")"
                cp "$source_path" "$PACKAGE_DIR/$pkg_relative"
                log_success "✓ Fichier copié: $pkg_relative"
                mark_path_as_copied "$pkg_relative"
                LOCAL_RESOURCES_COPIED=$((LOCAL_RESOURCES_COPIED + 1))
            else
                log_warn "⚠️  Ressource non trouvée: $source_path"
            fi
        done < <(grep -E '\.\.\/' "$compose_file" 2>/dev/null)
    done

    # Ajuster TOUS les chemins ../ dans les docker-compose
    # En dev: ../prometheus/... (relatif à deployment/)
    # Dans le package: ./prometheus/... (tout est à la racine)
    log_info "Ajustement de tous les chemins relatifs ../ → ./ ..."
    for compose_file in "$PACKAGE_DIR"/docker-compose*.yml; do
        if [ -f "$compose_file" ]; then
            sed_inplace 's|\.\./|./|g' "$compose_file"
            # Cas particulier: certains compose utilisent "context: .." (sans slash).
            # Dans le package, le contexte de build doit pointer sur la racine du package.
            sed_inplace 's|^\([[:space:]]*context:[[:space:]]*\)\.\.$|\1.|g' "$compose_file"
        fi
    done

    if [ "$LOCAL_RESOURCES_COPIED" -gt 0 ]; then
        log_success "✓ $LOCAL_RESOURCES_COPIED ressource(s) locale(s) copiée(s) et chemins ajustés"
    else
        log_info "Aucune ressource locale détectée (images officielles uniquement)"
    fi

    # Garde-fou: ne jamais livrer un package Superset avec des chemins ../config ou ../exports.
    # Sinon Docker crée des dossiers hors projet sur le serveur (ex: /srv/home/config, /srv/home/exports).
    if ls "$PACKAGE_DIR"/docker-compose*.yml >/dev/null 2>&1; then
        if grep -R -nE '\.\./config/|\.\./exports' "$PACKAGE_DIR"/docker-compose*.yml >/dev/null 2>&1; then
            log_error "❌ Le package contient encore des chemins relatifs '../config' ou '../exports' dans les compose."
            log_error "   Cela créerait des dossiers hors projet sur le serveur."
            log_info "   Fichiers concernés:"
            grep -R -nE '\.\./config/|\.\./exports' "$PACKAGE_DIR"/docker-compose*.yml || true
            exit 1
        fi
    fi

    # Copier superset_config.py uniquement pour les stacks Superset
    # (évite le cas où Docker crée un dossier config/superset_config.py si le fichier manque)
    if [ "${INCLUDE_SUPERSET_ASSETS}" != "false" ]; then
        local superset_config_src="$PROJECT_DIR/config/superset_config.py"
        local superset_config_dest_dir="$PACKAGE_DIR/config"
        local superset_config_dest="$superset_config_dest_dir/superset_config.py"
        if [ -f "$superset_config_src" ]; then
            mkdir -p "$superset_config_dest_dir"
            if [ -d "$superset_config_dest" ]; then
                rm -rf "$superset_config_dest"
            fi
            cp "$superset_config_src" "$superset_config_dest"
            log_success "✓ config/superset_config.py copié"
        elif [ "${INCLUDE_SUPERSET_ASSETS}" = "true" ]; then
            log_warn "⚠️  config/superset_config.py introuvable (requis pour stack '${STACK_TYPE}')"
        fi
    fi

    # Copier les vrais fichiers .env depuis la racine du projet
    # Priorité: copier uniquement le .env de l'environnement cible.
    # Fallback: si aucun env n'est détecté, conserver l'ancien comportement (copie des 3 fichiers).
    log_info "📋 Copie des fichiers .env réels (seront auto-chiffrés sur le serveur)..."
    echo ""

    ENV_COPIED=false
    TARGET_DEPLOY_ENV="$target_deploy_env"

    if [ -n "$TARGET_DEPLOY_ENV" ]; then
        TARGET_ENV_FILE="$PROJECT_DIR/.env.${TARGET_DEPLOY_ENV}"
        if [ -f "$TARGET_ENV_FILE" ]; then
            cp "$TARGET_ENV_FILE" "$PACKAGE_DIR/"
            log_success "✓ .env.${TARGET_DEPLOY_ENV} copié (environnement cible)"
            ENV_COPIED=true
        else
            log_warn "⚠️  .env.${TARGET_DEPLOY_ENV} non trouvé"
        fi
    else
        log_warn "⚠️  Environnement non détecté (ENV ou SERVER_DEPLOY_PATH), fallback: copie de tous les .env.*"
        for env_name in dev staging prod; do
            if [ -f "$PROJECT_DIR/.env.${env_name}" ]; then
                cp "$PROJECT_DIR/.env.${env_name}" "$PACKAGE_DIR/"
                log_success "✓ .env.${env_name} copié"
                ENV_COPIED=true
            else
                log_warn "⚠️  .env.${env_name} non trouvé"
            fi
        done
    fi

    # Inclure les outils Superset (optionnel)
    # - scripts/superset_manager.py
    # - scripts/requirements.txt
    # - exports/**/yaml + exports/manifest.json (pas de ZIP)
    # Résolution auto: inclure si superset_manager.py est présent
    if [ "${INCLUDE_SUPERSET_ASSETS:-auto}" = "auto" ]; then
        if [ -f "$PROJECT_DIR/scripts/superset_manager.py" ]; then
            INCLUDE_SUPERSET_ASSETS="true"
        else
            INCLUDE_SUPERSET_ASSETS="false"
        fi
    fi

    if [ "$INCLUDE_SUPERSET_ASSETS" = "true" ]; then
        log_info "➕ Inclusion des outils Superset (imports possibles sur le serveur)..."
        mkdir -p "$PACKAGE_DIR/scripts" "$PACKAGE_DIR/exports"

        if [ -f "$PROJECT_DIR/scripts/superset_manager.py" ]; then
            cp "$PROJECT_DIR/scripts/superset_manager.py" "$PACKAGE_DIR/scripts/"
            log_success "✓ scripts/superset_manager.py copié"
        else
            log_warn "⚠️  scripts/superset_manager.py non trouvé"
        fi

        if [ -f "$PROJECT_DIR/scripts/superset-import.sh" ]; then
            cp "$PROJECT_DIR/scripts/superset-import.sh" "$PACKAGE_DIR/scripts/"
            chmod +x "$PACKAGE_DIR/scripts/superset-import.sh"
            log_success "✓ scripts/superset-import.sh copié"
        fi

        if [ -f "$PROJECT_DIR/scripts/requirements.txt" ]; then
            cp "$PROJECT_DIR/scripts/requirements.txt" "$PACKAGE_DIR/scripts/"
            log_success "✓ scripts/requirements.txt copié"
        else
            log_warn "⚠️  scripts/requirements.txt non trouvé"
        fi

        if [ -f "$PROJECT_DIR/exports/manifest.json" ]; then
            cp "$PROJECT_DIR/exports/manifest.json" "$PACKAGE_DIR/exports/"
            log_success "✓ exports/manifest.json copié"
        else
            log_warn "⚠️  exports/manifest.json non trouvé"
        fi

        if [ -d "$PROJECT_DIR/exports" ]; then
            # Copier uniquement les YAML (source de vérité GitOps), pas les ZIP
            find "$PROJECT_DIR/exports" -type d -name yaml | while read -r yaml_dir; do
                rel_dir="${yaml_dir#$PROJECT_DIR/}"
                mkdir -p "$PACKAGE_DIR/$rel_dir"
                cp -R "$yaml_dir"/. "$PACKAGE_DIR/$rel_dir/"
            done
            log_success "✓ exports/**/yaml copiés"
        else
            log_warn "⚠️  exports/ non trouvé"
        fi
    else
        log_info "Outils Superset non inclus (imports via CI/CD uniquement)"
    fi

    # Inclure le compose RH (base de donnees test) uniquement pour les stacks Superset
    if [ "${STACK_TYPE}" = "reporting-superset" ] || [ "${STACK_TYPE}" = "superset" ]; then
        RH_SOURCE_DIRS=("$COMPOSE_SRC" "$PROJECT_DIR")
        if [ -n "$SUPERSET_PROJECT_DIR" ]; then
            RH_SOURCE_DIRS+=("$SUPERSET_PROJECT_DIR")
            RH_SOURCE_DIRS+=("$SUPERSET_PROJECT_DIR/$DEPLOYMENT_SUBDIR")
        fi

        RH_COMPOSE_SRC=""
        for d in "${RH_SOURCE_DIRS[@]}"; do
            if [ -f "$d/docker-compose.rh.yml" ]; then
                RH_COMPOSE_SRC="$d/docker-compose.rh.yml"
                break
            fi
        done

        if [ -n "$RH_COMPOSE_SRC" ]; then
            cp "$RH_COMPOSE_SRC" "$PACKAGE_DIR/docker-compose.rh.yml"
            log_success "✓ docker-compose.rh.yml copié (source: $RH_COMPOSE_SRC)"

            # Source canonique: database-rh/initdb.
            # Compat legacy: docker/database-rh/initdb en entrée uniquement.
            RH_SQL_SRC_DIR="$(dirname "$RH_COMPOSE_SRC")/database-rh/initdb"
            if [ ! -d "$RH_SQL_SRC_DIR" ]; then
                RH_SQL_SRC_DIR="$(dirname "$RH_COMPOSE_SRC")/docker/database-rh/initdb"
            fi

            if [ -d "$RH_SQL_SRC_DIR" ] && ls "$RH_SQL_SRC_DIR"/*.sql >/dev/null 2>&1; then
                mkdir -p "$PACKAGE_DIR/database-rh/initdb"
                cp "$RH_SQL_SRC_DIR"/*.sql "$PACKAGE_DIR/database-rh/initdb/"
                RH_SQL_COUNT=$(ls -1 "$PACKAGE_DIR/database-rh/initdb/"*.sql 2>/dev/null | wc -l | tr -d ' ')
                log_success "✓ Scripts SQL RH copiés: $RH_SQL_COUNT fichier(s)"
            else
                log_error "❌ Scripts SQL RH introuvables (attendu dans database-rh/initdb, fallback legacy docker/database-rh/initdb)"
                exit 1
            fi

            # Migration package: harmoniser le volume RH vers ./database-rh/initdb.
            if [ -f "$PACKAGE_DIR/docker-compose.rh.yml" ]; then
                sed_inplace 's|\./docker/database-rh/initdb|\./database-rh/initdb|g' "$PACKAGE_DIR/docker-compose.rh.yml"
            fi

            # Script utilitaire explicite pour démarrer la base RH sur le serveur.
            cat > "$PACKAGE_DIR/scripts/start-rh-db.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Préparation des scripts SQL RH..."
if [ -x "$PROJECT_DIR/scripts/project-scripts/prepare-rh-db.sh" ]; then
  bash "$PROJECT_DIR/scripts/project-scripts/prepare-rh-db.sh"
elif [ -x "$PROJECT_DIR/scripts/prepare-rh-db.sh" ]; then
  bash "$PROJECT_DIR/scripts/prepare-rh-db.sh"
else
  echo "Avertissement: prepare-rh-db.sh introuvable, poursuite."
fi

echo "Démarrage de db-rh..."
docker compose -f "$PROJECT_DIR/docker-compose.rh.yml" up -d db-rh

echo ""
docker compose -f "$PROJECT_DIR/docker-compose.rh.yml" ps db-rh
echo ""
echo "Base RH démarrée."
EOF
            chmod +x "$PACKAGE_DIR/scripts/start-rh-db.sh"
            log_success "✓ scripts/start-rh-db.sh généré"
        else
            log_warn "⚠️  docker-compose.rh.yml non trouvé (deployment/, PROJECT_DIR ou SUPERSET_PROJECT_DIR)"
        fi
    else
        log_info "Compose RH ignoré (stack_type=${STACK_TYPE:-non défini}, requis: reporting-superset)"
    fi

    # Copier Makefile si present (utile pour outils/venv locaux)
    if [ -f "$PROJECT_DIR/Makefile" ]; then
        cp "$PROJECT_DIR/Makefile" "$PACKAGE_DIR/"
        log_success "✓ Makefile copié"
    else
        log_warn "⚠️  Makefile non trouvé"
    fi

    if [ "$ENV_COPIED" = false ]; then
        log_error "Aucun fichier .env trouvé à la racine du projet"
        log_info "Création des fichiers depuis .env.example..."
        if [ -f "$PROJECT_DIR/.env.example" ]; then
            if [ -n "$TARGET_DEPLOY_ENV" ]; then
                cp "$PROJECT_DIR/.env.example" "$PACKAGE_DIR/.env.${TARGET_DEPLOY_ENV}"
                log_warn "⚠️  .env.${TARGET_DEPLOY_ENV} créé depuis .env.example - À configurer !"
            else
                cp "$PROJECT_DIR/.env.example" "$PACKAGE_DIR/.env.dev"
                cp "$PROJECT_DIR/.env.example" "$PACKAGE_DIR/.env.staging"
                cp "$PROJECT_DIR/.env.example" "$PACKAGE_DIR/.env.prod"
                log_warn "⚠️  Fichiers .env créés depuis .env.example - À configurer !"
            fi
        fi
    fi

    # Créer .env.registry avec les vraies valeurs (registry + app config)
    log_info "Création de .env.registry..."
    cat > "$PACKAGE_DIR/.env.registry" <<EOF
# Configuration Docker Registry
REGISTRY_TYPE=${REGISTRY_TYPE}
REGISTRY_URL=${REGISTRY_URL}
REGISTRY_USERNAME=${REGISTRY_USERNAME}
REGISTRY_TOKEN=${REGISTRY_TOKEN:-}
IMAGE_NAME=${IMAGE_NAME}

# Configuration projet (depuis .devops.yml)
PROJECT_NAME=${PROJECT_NAME}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-${PROJECT_NAME}}
STACK_TYPE=${STACK_TYPE}
LABEL_NAMESPACE=${LABEL_NAMESPACE}

# Configuration application
APP_ENTRYPOINT=${APP_ENTRYPOINT}
APP_PYTHON_PATH=${APP_PYTHON_PATH}
APP_SOURCE_DIR=${APP_SOURCE_DIR}
APP_DEST_DIR=${APP_DEST_DIR}
WORKDIR=${WORKDIR:-/app}
EOF

    # Pour le stack monitoring : ajouter la liste des images custom dans .env.registry
    if [ "${STACK_TYPE}" = "monitoring" ] && grep -q "^custom_images:" "${PROJECT_DIR}/.devops.yml" 2>/dev/null; then
        log_info "Stack monitoring: ajout des custom_images dans .env.registry..."
        {
            echo ""
            echo "# Images custom du stack monitoring"
            echo "# Format: CUSTOM_IMAGE_<SERVICE>=<image_name>"
            awk '
            /^custom_images:/ { in_block=1; next }
            in_block && /^[a-zA-Z_]/ { in_block=0 }
            !in_block { next }
            /^[[:space:]]*-[[:space:]]+service:/ {
                gsub(/.*service:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
                gsub(/^["'"'"']|["'"'"']$/, ""); service=$0; image=""
            }
            /^[[:space:]]+image_name:/ {
                gsub(/.*image_name:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
                gsub(/^["'"'"']|["'"'"']$/, ""); image=$0
                key=service; gsub(/-/, "_", key); gsub(/[^a-zA-Z0-9_]/, "", key)
                printf "CUSTOM_IMAGE_%s=%s\n", toupper(key), image
            }
            ' "${PROJECT_DIR}/.devops.yml"
        } >> "$PACKAGE_DIR/.env.registry"
        log_success "✓ custom_images ajoutés dans .env.registry"
    fi

    log_info "🔐 Les .env seront automatiquement chiffrés sur le serveur après installation"

    # Fonction locale pour créer des profils de base
    _create_basic_profiles() {
        cat > "$PACKAGE_DIR/scripts/.registry-profiles/dockerhub-dev.env" <<EOFPROFILE
# Profil Docker Hub pour développement
REGISTRY_TYPE=${REGISTRY_TYPE}
REGISTRY_URL=${REGISTRY_URL}
REGISTRY_USERNAME=${REGISTRY_USERNAME}
REGISTRY_TOKEN=${REGISTRY_TOKEN:-}
REGISTRY_PASSWORD=
IMAGE_NAME=${IMAGE_NAME}
GIT_REPO=
GITHUB_TOKEN=
DEV_BRANCH=dev
STAGING_BRANCH=staging
PROD_BRANCH=prod
EOFPROFILE

        cat > "$PACKAGE_DIR/scripts/.registry-profiles/dockerhub-staging.env" <<EOFPROFILE
# Profil Docker Hub pour staging
REGISTRY_TYPE=${REGISTRY_TYPE}
REGISTRY_URL=${REGISTRY_URL}
REGISTRY_USERNAME=${REGISTRY_USERNAME}
REGISTRY_TOKEN=${REGISTRY_TOKEN:-}
REGISTRY_PASSWORD=
IMAGE_NAME=${IMAGE_NAME}
GIT_REPO=
GITHUB_TOKEN=
DEV_BRANCH=dev
STAGING_BRANCH=staging
PROD_BRANCH=prod
EOFPROFILE

        cat > "$PACKAGE_DIR/scripts/.registry-profiles/dockerhub-prod.env" <<EOFPROFILE
# Profil Docker Hub pour production
REGISTRY_TYPE=${REGISTRY_TYPE}
REGISTRY_URL=${REGISTRY_URL}
REGISTRY_USERNAME=${REGISTRY_USERNAME}
REGISTRY_TOKEN=${REGISTRY_TOKEN:-}
REGISTRY_PASSWORD=
IMAGE_NAME=${IMAGE_NAME}
GIT_REPO=
GITHUB_TOKEN=
DEV_BRANCH=dev
STAGING_BRANCH=staging
PROD_BRANCH=prod
EOFPROFILE

        if [ -n "${REGISTRY_TOKEN:-}" ]; then
            log_success "✓ Profils de base créés dans scripts/.registry-profiles/ (token inclus depuis .devops.yml)"
        else
            log_success "✓ Profils de base créés dans scripts/.registry-profiles/"
            log_warn "⚠️  N'oubliez pas de compléter les tokens sur le serveur!"
        fi
    }

    # Copier les profils registry existants
    # Priorité: 1) projet cible  2) répertoire devops-scripts  3) profils de base
    log_info "Copie des profils registry..."
    mkdir -p "$PACKAGE_DIR/scripts/.registry-profiles"

    PROFILES_DIR="$PROJECT_DIR/$DEPLOYMENT_SUBDIR/scripts/.registry-profiles"
    PROFILES_DIR_DEVOPS="$SCRIPT_DIR/.registry-profiles"

    _copy_profiles_from() {
        local src="$1"
        cp -r "$src"/* "$PACKAGE_DIR/scripts/.registry-profiles/" 2>/dev/null || true
        local count
        count=$(find "$PACKAGE_DIR/scripts/.registry-profiles" -type f \( -name "*.env" -o -name "*.env.encrypted" \) | wc -l)
        echo "$count"
    }

    if [ -d "$PROFILES_DIR" ] && [ -n "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]; then
        profile_count=$(_copy_profiles_from "$PROFILES_DIR")
        if [ "$profile_count" -gt 0 ]; then
            log_success "✓ $profile_count profil(s) copié(s) depuis le projet cible"
        else
            log_warn "⚠️  Aucun profil trouvé dans $PROFILES_DIR, tentative depuis devops-scripts..."
            _create_basic_profiles
        fi
    elif [ -d "$PROFILES_DIR_DEVOPS" ] && [ -n "$(ls -A "$PROFILES_DIR_DEVOPS" 2>/dev/null)" ]; then
        # Recréer les profils avec le bon IMAGE_NAME du projet courant,
        # mais en injectant les credentials (tokens) depuis les profils devops-scripts
        _create_basic_profiles
        # Injecter les credentials depuis les profils source
        for src_profile in "$PROFILES_DIR_DEVOPS"/*.env; do
            [ -f "$src_profile" ] || continue
            local bname
            bname=$(basename "$src_profile")
            local dst_profile="$PACKAGE_DIR/scripts/.registry-profiles/$bname"
            [ -f "$dst_profile" ] || continue
            # Extraire les credentials depuis le profil source
            local src_token src_password src_github
            src_token=$(grep "^REGISTRY_TOKEN=" "$src_profile" | cut -d'=' -f2-)
            src_password=$(grep "^REGISTRY_PASSWORD=" "$src_profile" | cut -d'=' -f2-)
            src_github=$(grep "^GITHUB_TOKEN=" "$src_profile" | cut -d'=' -f2-)
            # Injecter dans le profil destination (remplace les lignes vides)
            [ -n "$src_token" ]    && sed_inplace "s|^REGISTRY_TOKEN=.*|REGISTRY_TOKEN=${src_token}|" "$dst_profile"
            [ -n "$src_password" ] && sed_inplace "s|^REGISTRY_PASSWORD=.*|REGISTRY_PASSWORD=${src_password}|" "$dst_profile"
            [ -n "$src_github" ]   && sed_inplace "s|^GITHUB_TOKEN=.*|GITHUB_TOKEN=${src_github}|" "$dst_profile"
        done
        profile_count=$(find "$PACKAGE_DIR/scripts/.registry-profiles" -name "*.env" | wc -l)
        log_success "✓ $profile_count profil(s) générés pour le projet (credentials depuis devops-scripts)"
        log_info "  IMAGE_NAME=${IMAGE_NAME} — tokens préservés"
    else
        log_info "Aucun profil existant détecté, création de profils de base..."
        _create_basic_profiles
    fi

    # Copier les scripts essentiels
    log_info "Copie des scripts..."
    SCRIPTS_SRC_PROJECT="$PROJECT_DIR/$DEPLOYMENT_SUBDIR/scripts"
    SCRIPTS_SRC_DEVOPS="$SCRIPT_DIR"

    SCRIPTS_TO_COPY=(
        "config-loader.sh"
        "deploy-registry.sh"
        "env-encrypt.py"
        "sensitive-vars.yml"
        "auto-encrypt-envs.sh"
        "docker-manage.sh"
    )

    for script in "${SCRIPTS_TO_COPY[@]}"; do
        if [ -f "$SCRIPTS_SRC_PROJECT/$script" ]; then
            cp "$SCRIPTS_SRC_PROJECT/$script" "$PACKAGE_DIR/scripts/"
            log_success "✓ $script copié (depuis projet)"
        elif [ -f "$SCRIPTS_SRC_DEVOPS/$script" ]; then
            cp "$SCRIPTS_SRC_DEVOPS/$script" "$PACKAGE_DIR/scripts/"
            log_success "✓ $script copié (depuis devops-enginering)"
        else
            log_warn "⚠️  $script non trouvé"
        fi
    done

    # Copier les scripts utilitaires du projet (racine scripts/), si présents
    PROJECT_SCRIPTS_DIR="$PROJECT_DIR/scripts"
    if [ -d "$PROJECT_SCRIPTS_DIR" ]; then
        mkdir -p "$PACKAGE_DIR/scripts/project-scripts"
        cp -r "$PROJECT_SCRIPTS_DIR"/. "$PACKAGE_DIR/scripts/project-scripts/"
        # Nettoyage des artefacts locaux non nécessaires dans le package
        rm -rf "$PACKAGE_DIR/scripts/project-scripts/.venv"
        find "$PACKAGE_DIR/scripts/project-scripts" -type d -name "__pycache__" -prune -exec rm -rf {} +
        find "$PACKAGE_DIR/scripts/project-scripts" -type f -name "*.pyc" -delete
        log_success "✓ scripts/ du projet copié vers scripts/project-scripts/ (sans .venv/__pycache__)"
    else
        log_info "Aucun dossier scripts/ à la racine du projet"
    fi

    # Copier le fichier requirements pour l'environnement virtuel
    if [ -f "$PROJECT_DIR/$DEPLOYMENT_SUBDIR/requirements-encryption.txt" ]; then
        cp "$PROJECT_DIR/$DEPLOYMENT_SUBDIR/requirements-encryption.txt" "$PACKAGE_DIR/"
        log_success "✓ requirements-encryption.txt copié (depuis projet)"
    elif [ -f "$SCRIPT_DIR/../requirements-encryption.txt" ]; then
        cp "$SCRIPT_DIR/../requirements-encryption.txt" "$PACKAGE_DIR/"
        log_success "✓ requirements-encryption.txt copié (depuis devops-enginering)"
    else
        log_warn "⚠️  requirements-encryption.txt non trouvé"
    fi

    # Rendre les scripts exécutables
    chmod +x "$PACKAGE_DIR/scripts/"*.sh 2>/dev/null || true

    # Créer README
    log_info "Création du README..."
    cat > "$PACKAGE_DIR/README.md" <<'EOF'
# ${PROJECT_NAME} - Package de Déploiement

Package minimal pour déployer l'application depuis Docker Hub.

## 📦 Contenu

- `docker-compose*.yml` : Configurations Docker pour registry
- `.env.*.example` : Templates de variables d'environnement
- `.env.registry.example` : Template de configuration Docker Hub
- `scripts/` : Scripts de déploiement et diagnostic
  - `deploy-registry.sh` : Script principal de déploiement
  - `env-encrypt.py` : Script de chiffrement des .env
  - `auto-encrypt-envs.sh` : Script d'auto-chiffrement (recommandé)
  - `sensitive-vars.yml` : Configuration des variables sensibles
- `scripts/.registry-profiles/` : Profils de registry par environnement
EOF

    if [ "$INCLUDE_SUPERSET_ASSETS" = "true" ]; then
        cat >> "$PACKAGE_DIR/README.md" <<'EOF'

## 🔁 Superset (optionnel) - Imports sur le serveur

Ce package inclut `scripts/superset_manager.py`, `scripts/superset-import.sh`
et les YAML de `exports/**/yaml`.

### Import automatique (recommandé)

```bash
./scripts/superset-import.sh --env prod
```

Le script gère automatiquement :
- Le déchiffrement du .env
- L'installation des dépendances Python (venv)
- Le health check Superset
- Le lancement de l'import

### Import via deploy-registry.sh

```bash
./scripts/deploy-registry.sh superset-import prod
```

### Import manuel

```bash
pip3 install -r scripts/requirements.txt
python3 scripts/superset_manager.py import --all
```

### Base RH locale au serveur (optionnel)

Pour démarrer la base RH utilisée par certains dashboards:

```bash
./scripts/start-rh-db.sh
```
EOF
    fi

    cat >> "$PACKAGE_DIR/README.md" <<'EOF'

## 🚀 Installation sur VPS

### 1. Transférer le package

```bash
# Sur votre Mac
scp ~/${PROJECT_NAME}.tar.gz cicbi@vps:/srv/
```

### 2. Installer sur le VPS

```bash
# Sur le VPS
cd /srv
tar -xzf ${PROJECT_NAME}.tar.gz
mv ${PROJECT_NAME} ${PROJECT_NAME}
cd ${PROJECT_NAME}
```

### 3. Les fichiers .env sont automatiquement chiffrés

**Le package contient vos fichiers .env réels** (copiés depuis votre machine locale).

**Lors de l'installation, le script :**
1. ✅ Extrait les fichiers .env et profils registry
2. 🔐 Chiffre automatiquement les .env (`.env.dev.encrypted`, etc.)
3. 🔐 Chiffre automatiquement les profils registry (`.registry-profiles/*.env.encrypted`)
4. 🗑️ Supprime toutes les versions non chiffrées
5. 🔑 Génère/préserve la clé `.env.key`
6. 🏷️ Crée le marker `.server-marker` pour la détection automatique
7. 📋 Configure le profil registry par défaut

**Vous n'avez rien à faire !** Les secrets (tokens, passwords) sont automatiquement sécurisés.

### 4. Configurer le registry Docker (optionnel)

Si nécessaire, modifiez la configuration registry :

```bash
# Éditer la config (déjà présente et configurée)
nano .env.registry

# Ou configurer un profil spécifique
nano scripts/.registry-profiles/dockerhub-dev.env
```

### 5. Déchiffrer les fichiers (si nécessaire)

Les fichiers .env ET profils registry sont **déjà chiffrés** automatiquement. Pour les lire :

**Déchiffrer un .env :**
```bash
# Déchiffrer temporairement
python3 scripts/env-encrypt.py decrypt .env.dev.encrypted

# Éditer
nano .env.dev

# Re-chiffrer et supprimer
python3 scripts/env-encrypt.py encrypt .env.dev
rm .env.dev
```

**Déchiffrer un profil registry :**
```bash
# Déchiffrer temporairement
python3 scripts/env-encrypt.py decrypt scripts/.registry-profiles/dockerhub-dev.env.encrypted

# Éditer
nano scripts/.registry-profiles/dockerhub-dev.env

# Re-chiffrer et supprimer
python3 scripts/env-encrypt.py encrypt scripts/.registry-profiles/dockerhub-dev.env
rm scripts/.registry-profiles/dockerhub-dev.env
```

**Ou utilisez le script automatique pour tout re-chiffrer :**
```bash
# Re-chiffrer tous les .env après modifications
./scripts/auto-encrypt-envs.sh --auto-confirm

# Re-chiffrer manuellement les profils registry
for profile in scripts/.registry-profiles/*.env; do
    [ -f "$profile" ] && python3 scripts/env-encrypt.py encrypt "$profile" && rm "$profile"
done
```

**⚠️ IMPORTANT** :
- La clé `.env.key` est générée automatiquement
- **Sauvegardez-la** dans un gestionnaire de secrets sécurisé !
- Sans cette clé, vous ne pourrez pas déchiffrer vos fichiers

### 6. Déployer

```bash
# Dev
./scripts/deploy-registry.sh deploy dev

# Staging
./scripts/deploy-registry.sh deploy staging

# Prod
./scripts/deploy-registry.sh deploy prod
```

## 🔧 Environnements

| Environnement | Port | Utilisation |
|---------------|------|-------------|
| dev | 8001 | Développement/Tests |
| staging | 8002 | Pré-production |
| prod | 8000 | Production |

## 📋 Commandes utiles

### Déploiement

```bash
# Déployer une version spécifique
./scripts/deploy-registry.sh deploy dev dev-v1.0.0

# Déployer latest
./scripts/deploy-registry.sh deploy dev
```

### Status et logs

```bash
# Voir le statut
./scripts/deploy-registry.sh status dev

# Voir les logs
./scripts/deploy-registry.sh logs dev ${PROJECT_NAME}-api

# Arrêter
./scripts/deploy-registry.sh stop dev

# Redémarrer
./scripts/deploy-registry.sh restart dev
```

### Diagnostic

```bash
# Vérifier le statut
./scripts/deploy-registry.sh status dev

# Voir les logs d'un service
./scripts/deploy-registry.sh logs dev ${PROJECT_NAME}-api
```

## 🔐 Sécurité

**IMPORTANT** : Les fichiers `.env.*` contiennent des secrets sensibles !

### Bonnes pratiques

1. **Ne jamais commiter les fichiers .env**
   - Seuls les fichiers `.example` doivent être versionnés
   - Le `.gitignore` est déjà configuré pour ignorer les .env

2. **Protéger les fichiers avec chmod**
   ```bash
   chmod 600 .env.*
   chmod 600 .env.key
   ```

3. **Utiliser le chiffrement pour la production**
   ```bash
   # Chiffrer les .env sensibles
   python3 scripts/env-encrypt.py encrypt .env.prod

   # Supprimer les fichiers non chiffrés
   rm -f .env.prod

   # Sauvegarder .env.key dans un gestionnaire de secrets (Vault, 1Password, etc.)
   ```

4. **Séparer les secrets par environnement**
   - Ne jamais utiliser les mêmes secrets entre dev/staging/prod
   - Rotez régulièrement les clés et tokens

5. **Après chiffrement, supprimer les .env non chiffrés**
   ```bash
   # Vérifier que les fichiers sont chiffrés
   ls -la *.encrypted

   # Supprimer les fichiers sensibles
   rm -f .env.dev .env.staging .env.prod .env.registry
   ```

## 📝 Notes

- Le code source est dans l'image Docker (pas sur le serveur)
- Les builds se font sur votre Mac et sont pushés sur Docker Hub
- Le VPS pull simplement l'image et la démarre
- Taille totale du package : ~100 KB

## 🆘 Support

En cas de problème, consultez les logs :

```bash
docker logs ${PROJECT_NAME}-api-dev -f
```

---

**Version :** 1.0
**Date :** 17 décembre 2025
EOF

    # Créer un script d'installation pour le VPS
    log_info "Création du script d'installation..."
    cat > "$PACKAGE_DIR/install.sh" <<'EOF'
#!/bin/bash

# Script d'installation sur VPS

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Installation du package ${PROJECT_NAME}${NC}"
echo ""

# Rendre les scripts exécutables
chmod +x scripts/*.sh 2>/dev/null || true

# Créer les répertoires nécessaires
mkdir -p logs

# Vérifier la présence du fichier Superset config
if [ -d "config/superset_config.py" ]; then
    echo -e "${YELLOW}Erreur: config/superset_config.py est un dossier (doit être un fichier).${NC}"
    echo -e "${YELLOW}Supprimez ce dossier (sudo) et réinstallez le package.${NC}"
    exit 1
fi
if [ ! -f "config/superset_config.py" ]; then
    echo -e "${YELLOW}Attention: config/superset_config.py manquant.${NC}"
    echo -e "${YELLOW}Le montage Docker créera un dossier et Superset ne démarrera pas.${NC}"
fi

# Préparer l'environnement virtuel pour les outils Superset (si présents)
if [ -f "scripts/superset_manager.py" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${YELLOW}python3 non trouvé, venv non créé${NC}"
    else
        VENV_DIR=".venv"
        if [ ! -f "$VENV_DIR/bin/python3" ]; then
            echo -e "${GREEN}Création venv: $VENV_DIR${NC}"
            python3 -m venv "$VENV_DIR"
        fi
        if [ -f "scripts/requirements.txt" ]; then
            echo -e "${GREEN}Installation des dépendances Python (scripts/requirements.txt)${NC}"
            "$VENV_DIR/bin/pip" install --quiet -r "scripts/requirements.txt"
        else
            echo -e "${YELLOW}requirements.txt manquant, dépendances non installées${NC}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}✓ Installation terminée${NC}"
echo ""
echo "Prochaines étapes:"
echo "  1. Configurer les .env.* selon votre environnement"
echo "  2. Activer le venv: source .venv/bin/activate"
echo "  3. Déployer: ./scripts/deploy-registry.sh deploy dev"
echo ""
EOF

    chmod +x "$PACKAGE_DIR/install.sh"

    # Créer .gitignore
    log_info "Création du .gitignore..."
    cat > "$PACKAGE_DIR/.gitignore" <<EOF
# Fichiers sensibles (ne jamais commiter)
.env.dev
.env.staging
.env.prod
.env.registry

# Fichiers chiffrés et clés
*.encrypted
.env.key
*.key

# Profils registry configurés
scripts/.registry-profiles/*.env
!scripts/.registry-profiles/*.env.example

# Environnement virtuel Python
.venv/
venv/
__pycache__/
*.pyc

# Logs
logs/
*.log

# Docker
.env

# Sauvegardes
*.backup
*.bak
EOF

    # Créer l'archive
    log_info "Création de l'archive..."

    # Utiliser le chemin absolu du package
    PACKAGE_DIR_EXPANDED="${PACKAGE_DIR/#\~/$HOME}"
    PACKAGE_FOLDER=$(basename "$PACKAGE_DIR_EXPANDED")
    PACKAGE_PARENT=$(dirname "$PACKAGE_DIR_EXPANDED")

    # L'archive porte le nom du projet (pas -deployment-package)
    ARCHIVE_NAME="${PROJECT_NAME}.tar.gz"

    cd "$PACKAGE_PARENT"
    # COPYFILE_DISABLE=1 évite les fichiers AppleDouble (._*) sur macOS
    # On archive le contenu du dossier (pas le dossier lui-même) pour éviter
    # un niveau de répertoire supplémentaire à l'extraction côté serveur.
    COPYFILE_DISABLE=1 tar -czf "$ARCHIVE_NAME" -C "$PACKAGE_DIR_EXPANDED" .

    # Statistiques
    ARCHIVE_FILE="$PACKAGE_PARENT/$ARCHIVE_NAME"
    PACKAGE_SIZE=$(du -h "$ARCHIVE_FILE" | cut -f1)
    FILE_COUNT=$(find "$PACKAGE_DIR_EXPANDED" -type f | wc -l)

    echo ""
    log_success "Archive créée: $ARCHIVE_FILE"
    log_success "Taille: $PACKAGE_SIZE"
    log_success "Fichiers: $FILE_COUNT"

    # Nettoyer le dossier source (garder uniquement l'archive)
    rm -rf "$PACKAGE_DIR_EXPANDED"
    log_info "Dossier temporaire nettoyé"

    cd "$PROJECT_DIR"
}

# ============================================================================
# TRANSFERT SSH
# ============================================================================

transfer_via_ssh() {
    print_header "Transfert SSH"
    echo ""

    # Utiliser le chemin absolu du package
    local package_dir_expanded="${PACKAGE_DIR/#\~/$HOME}"
    local package_parent=$(dirname "$package_dir_expanded")
    local archive_name="${PROJECT_NAME}.tar.gz"
    local archive_file="$package_parent/$archive_name"

    if [ ! -f "$archive_file" ]; then
        log_error "Archive non trouvée: $archive_file"
        log_info "Créez d'abord le package avec l'option 1"
        return 1
    fi

    # S'assurer que SSH_OPTIONS est à jour avec la clé SSH
    prepare_ssh_options

    log_info "Transfert vers ${CYAN}${SSH_USER}@${SSH_HOST}:${SSH_PATH}${NC}"
    echo ""

    # Vérifier la connexion SSH
    log_info "Test de connexion SSH..."

    if [ "$SSH_USE_PASSWORD" == "true" ]; then
        # Avec mot de passe
        if ! command -v sshpass &> /dev/null; then
            log_error "sshpass n'est pas installé"
            log_info "Installation:"
            echo "  macOS: brew install hudochenkov/sshpass/sshpass"
            echo "  Linux: sudo apt-get install sshpass"
            return 1
        fi

        read -s -p "Mot de passe SSH: " SSH_PASSWORD
        echo ""

        if ! sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" -o ConnectTimeout=5 \
            "${SSH_USER}@${SSH_HOST}" "exit" 2>/dev/null; then
            log_error "Connexion SSH échouée"
            return 1
        fi

        log_success "Connexion SSH réussie"
        echo ""

        # Créer le répertoire distant (et parents si nécessaire)
        log_info "Création du répertoire distant : ${SSH_PATH}"
        sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" \
            "${SSH_USER}@${SSH_HOST}" "mkdir -p ${SSH_PATH}" || {
            log_error "Impossible de créer le répertoire ${SSH_PATH}"
            return 1
        }

        # Transférer l'archive
        log_info "Transfert de l'archive ($(du -h $archive_file | cut -f1))..."
        if sshpass -p "$SSH_PASSWORD" scp -P "$SSH_PORT" \
            "$archive_file" "${SSH_USER}@${SSH_HOST}:${SSH_PATH}/"; then
            log_success "Archive transférée"
        else
            log_error "Échec du transfert"
            return 1
        fi

        # Décompresser automatiquement sur le serveur (sans question)
        log_info "Extraction de l'archive sur le serveur..."
        local bak="/tmp/.sensitive-${PROJECT_NAME}"

        sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" "
            cd ${SSH_PATH}
            rm -rf ${bak} && mkdir -p ${bak}
            cp -a scripts/.registry-profiles ${bak}/ 2>/dev/null || true
            [ -f .env.key ] && cp .env.key ${bak}/ 2>/dev/null || true
            tar -xzf ${PROJECT_NAME}.tar.gz 2>/dev/null
            rm -f ${PROJECT_NAME}.tar.gz
            find . -name '._*' -delete 2>/dev/null || true
            cp -a ${bak}/.registry-profiles/. scripts/.registry-profiles/ 2>/dev/null || true
            [ -f ${bak}/.env.key ] && cp ${bak}/.env.key .env.key 2>/dev/null || true
            rm -rf ${bak}
            [ -d .env.key ] && rm -rf .env.key
            if [ ! -s .env.key ] && [ -n '${ENV_ENCRYPTION_KEY}' ]; then printf '%s' '${ENV_ENCRYPTION_KEY}' > .env.key && chmod 600 .env.key && echo '🔑 Clé de chiffrement initialisée depuis .devops.yml'; fi
            if [ -s .env.key ] && [ -f .env.prod ]; then echo '🔐 Chiffrement automatique des .env...' && bash scripts/auto-encrypt-envs.sh --auto-confirm 2>&1 || true; fi
            chmod +x install.sh scripts/*.sh 2>/dev/null || true
            echo '✅ Extraction terminée (fichiers sensibles préservés)'"

        log_success "Package installé dans ${SSH_PATH}"

    else
        # Avec clé SSH
        if ! ssh $SSH_OPTIONS -p "$SSH_PORT" -o ConnectTimeout=5 \
            "${SSH_USER}@${SSH_HOST}" "exit" 2>/dev/null; then
            log_error "Connexion SSH échouée"
            log_info "Vérifiez:"
            echo "  - Que votre clé SSH est configurée"
            echo "  - Que l'hôte est accessible"
            echo "  - Que le port $SSH_PORT est correct"
            [ -n "$SSH_IDENTITY_FILE" ] && echo "  - Que le fichier de clé existe: $SSH_IDENTITY_FILE"
            return 1
        fi

        log_success "Connexion SSH réussie"
        echo ""

        # Créer le répertoire distant (et parents si nécessaire)
        log_info "Création du répertoire distant : ${SSH_PATH}"
        ssh $SSH_OPTIONS -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" "mkdir -p ${SSH_PATH}" || {
            log_error "Impossible de créer le répertoire ${SSH_PATH}"
            return 1
        }

        # Transférer l'archive
        log_info "Transfert de l'archive ($(du -h $archive_file | cut -f1))..."
        if scp $SSH_OPTIONS -P "$SSH_PORT" "$archive_file" \
            "${SSH_USER}@${SSH_HOST}:${SSH_PATH}/"; then
            log_success "Archive transférée"
        else
            log_error "Échec du transfert"
            return 1
        fi

        # Décompresser automatiquement sur le serveur (sans question)
        log_info "Extraction de l'archive sur le serveur..."
        local bak="/tmp/.sensitive-${PROJECT_NAME}"

        ssh $SSH_OPTIONS -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" "
            cd ${SSH_PATH}
            rm -rf ${bak} && mkdir -p ${bak}
            cp -a scripts/.registry-profiles ${bak}/ 2>/dev/null || true
            [ -f .env.key ] && cp .env.key ${bak}/ 2>/dev/null || true
            tar -xzf ${PROJECT_NAME}.tar.gz 2>/dev/null
            rm -f ${PROJECT_NAME}.tar.gz
            find . -name '._*' -delete 2>/dev/null || true
            cp -a ${bak}/.registry-profiles/. scripts/.registry-profiles/ 2>/dev/null || true
            [ -f ${bak}/.env.key ] && cp ${bak}/.env.key .env.key 2>/dev/null || true
            rm -rf ${bak}
            [ -d .env.key ] && rm -rf .env.key
            if [ ! -s .env.key ] && [ -n '${ENV_ENCRYPTION_KEY}' ]; then printf '%s' '${ENV_ENCRYPTION_KEY}' > .env.key && chmod 600 .env.key && echo '🔑 Clé de chiffrement initialisée depuis .devops.yml'; fi
            if [ -s .env.key ] && [ -f .env.prod ]; then echo '🔐 Chiffrement automatique des .env...' && bash scripts/auto-encrypt-envs.sh --auto-confirm 2>&1 || true; fi
            chmod +x install.sh scripts/*.sh 2>/dev/null || true
            echo '✅ Extraction terminée (fichiers sensibles préservés)'"

        log_success "Package installé dans ${SSH_PATH}"
    fi

    echo ""
    print_separator
    log_success "Transfert terminé !"
    echo ""
    log_info "Sur le serveur, exécutez:"
    echo -e "  ${CYAN}cd ${SSH_PATH}${NC}"
    echo -e "  ${CYAN}./install.sh${NC}"
    echo -e "  ${CYAN}./scripts/deploy-registry.sh deploy dev${NC}"
    print_separator
    echo ""
}

# ============================================================================
# NETTOYAGE DU SERVEUR
# ============================================================================

clean_server() {
    print_header "Nettoyage du serveur"
    echo ""

    # Vérifier la configuration SSH
    if [ -z "$SSH_HOST" ]; then
        log_error "Configuration SSH non définie"
        log_info "Utilisez l'option 3 (Configuration avancée) pour configurer SSH"
        return 1
    fi

    # Demander explicitement l'environnement cible avant toute action destructive
    local cleanup_env_default
    local cleanup_env
    local cleanup_target_path
    local path_basename
    local path_parent
    local path_prefix

    cleanup_env_default="$(detect_deploy_env_suffix)"
    if [ -z "$cleanup_env_default" ]; then
        cleanup_env_default="dev"
    fi

    while true; do
        ask_input "Environnement à nettoyer (dev/staging/prod)" "$cleanup_env_default" cleanup_env
        cleanup_env="$(printf '%s' "$cleanup_env" | tr '[:upper:]' '[:lower:]')"
        case "$cleanup_env" in
            dev|staging|prod) break ;;
            *)
                log_warn "Environnement invalide: '$cleanup_env' (attendu: dev, staging ou prod)"
                ;;
        esac
    done

    # Aligner ENV avec le choix utilisateur pour cohérence des logs et des scripts appelés
    ENV="$cleanup_env"

    # Construire un chemin cible cohérent avec l'environnement choisi
    cleanup_target_path="$SSH_PATH"
    path_basename="$(basename "$cleanup_target_path")"
    path_parent="$(dirname "$cleanup_target_path")"
    if [[ "$path_basename" =~ ^(.+)-(dev|staging|prod)$ ]]; then
        path_prefix="${BASH_REMATCH[1]}"
        cleanup_target_path="${path_parent}/${path_prefix}-${cleanup_env}"
    fi

    ask_input "Chemin de destination à nettoyer" "$cleanup_target_path" cleanup_target_path

    log_warn "⚠️  ${RED}DANGER${NC} ⚠️"
    echo ""
    echo "Cette opération va ${RED}SUPPRIMER COMPLÈTEMENT${NC} le déploiement sur le serveur :"
    echo ""
    echo -e "  Serveur    : ${CYAN}${SSH_USER}@${SSH_HOST}:${SSH_PORT}${NC}"
    echo -e "  Environnement: ${CYAN}${cleanup_env}${NC}"
    echo -e "  Chemin     : ${CYAN}${cleanup_target_path}${NC}"
    echo ""
    echo -e "${RED}Tout sera supprimé :${NC}"
    echo "  - Fichiers de configuration (.env, docker-compose, etc.)"
    echo "  - Scripts de déploiement"
    echo "  - Environnement virtuel Python (.venv)"
    echo "  - Logs"
    echo "  - Fichiers chiffrés (.env.*.encrypted)"
    echo "  - Clé de chiffrement (.env.key)"
    echo ""
    echo -e "${YELLOW}⚠️  Cette action est IRRÉVERSIBLE !${NC}"
    echo ""

    # Triple confirmation
    if ! ask_yes_no "Êtes-vous SÛR de vouloir nettoyer le serveur" "n"; then
        log_info "Opération annulée"
        return 0
    fi

    echo ""
    log_warn "Confirmation supplémentaire requise"
    echo -e "Tapez exactement: ${RED}SUPPRIMER TOUT${NC}"
    read -p "Confirmation: " confirm

    if [ "$confirm" != "SUPPRIMER TOUT" ]; then
        log_info "Opération annulée (confirmation incorrecte)"
        return 0
    fi

    echo ""
    log_info "Nettoyage du serveur en cours..."

    local remote_cleanup_cmd
    remote_cleanup_cmd=$(cat <<'EOF'
TARGET_PATH="$1"
if [ ! -d "$TARGET_PATH" ]; then
    echo "TARGET_MISSING"
    exit 0
fi

if sudo -n true >/dev/null 2>&1; then
    sudo find "$TARGET_PATH" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
else
    find "$TARGET_PATH" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || true
fi

remaining=$(find "$TARGET_PATH" -mindepth 1 -maxdepth 1 -print 2>/dev/null | head -n 1 || true)
if [ -n "$remaining" ]; then
    echo "CLEANUP_INCOMPLETE"
    find "$TARGET_PATH" -mindepth 1 -maxdepth 1 -ls 2>/dev/null || true
    exit 2
fi

echo "CLEANUP_OK"
EOF
)

    local cleanup_output=""
    local cleanup_rc=0

    # Exécuter le nettoyage
    if [ "$SSH_USE_PASSWORD" == "true" ]; then
        # Avec mot de passe
        if ! command -v sshpass &> /dev/null; then
            log_error "sshpass n'est pas installé"
            return 1
        fi

        read -s -p "Mot de passe SSH: " SSH_PASSWORD
        echo ""

        cleanup_output=$(
            sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" \
                "bash -s -- '$cleanup_target_path'" <<<"$remote_cleanup_cmd"
        ) || cleanup_rc=$?
    else
        # Avec clé SSH
        cleanup_output=$(
            ssh $SSH_OPTIONS -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" \
                "bash -s -- '$cleanup_target_path'" <<<"$remote_cleanup_cmd"
        ) || cleanup_rc=$?
    fi

    echo ""
    if printf '%s\n' "$cleanup_output" | grep -q "^CLEANUP_OK$"; then
        log_success "Serveur nettoyé : ${cleanup_target_path}"
        log_info "Le dossier est maintenant vide"
    elif printf '%s\n' "$cleanup_output" | grep -q "^TARGET_MISSING$"; then
        log_warn "Chemin distant absent : ${cleanup_target_path} (rien à nettoyer)"
    else
        if ask_yes_no "Permissions insuffisantes. Tenter un nettoyage sudo interactif" "y"; then
            log_info "Tentative sudo interactive..."
            cleanup_output=""
            cleanup_rc=0

            if [ "$SSH_USE_PASSWORD" == "true" ]; then
                cleanup_output=$(
                    sshpass -p "$SSH_PASSWORD" ssh -tt -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" \
                        "bash -lc 'TARGET_PATH=\"\$1\"; if [ ! -d \"\$TARGET_PATH\" ]; then echo TARGET_MISSING; exit 0; fi; sudo find \"\$TARGET_PATH\" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; remaining=\$(find \"\$TARGET_PATH\" -mindepth 1 -maxdepth 1 -print 2>/dev/null | head -n 1 || true); if [ -n \"\$remaining\" ]; then echo CLEANUP_INCOMPLETE; find \"\$TARGET_PATH\" -mindepth 1 -maxdepth 1 -ls 2>/dev/null || true; exit 2; fi; echo CLEANUP_OK' _ '$cleanup_target_path'"
                ) || cleanup_rc=$?
            else
                cleanup_output=$(
                    ssh $SSH_OPTIONS -tt -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" \
                        "bash -lc 'TARGET_PATH=\"\$1\"; if [ ! -d \"\$TARGET_PATH\" ]; then echo TARGET_MISSING; exit 0; fi; sudo find \"\$TARGET_PATH\" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; remaining=\$(find \"\$TARGET_PATH\" -mindepth 1 -maxdepth 1 -print 2>/dev/null | head -n 1 || true); if [ -n \"\$remaining\" ]; then echo CLEANUP_INCOMPLETE; find \"\$TARGET_PATH\" -mindepth 1 -maxdepth 1 -ls 2>/dev/null || true; exit 2; fi; echo CLEANUP_OK' _ '$cleanup_target_path'"
                ) || cleanup_rc=$?
            fi

            if printf '%s\n' "$cleanup_output" | grep -q "^CLEANUP_OK$"; then
                log_success "Serveur nettoyé : ${cleanup_target_path}"
                log_info "Le dossier est maintenant vide"
                echo ""
                return 0
            fi
        fi

        log_error "Nettoyage incomplet sur ${cleanup_target_path}"
        log_warn "Des fichiers/répertoires n'ont pas pu être supprimés (permissions)."
        if [ "$cleanup_rc" -ne 0 ]; then
            log_warn "Code retour SSH: $cleanup_rc"
        fi
        echo ""
        echo "$cleanup_output"
        return 1
    fi
    echo ""
}

# ============================================================================
# CONFIGURATION AVANCÉE
# ============================================================================

advanced_config() {
    print_header "Configuration avancée"
    echo ""

    # Mode de nommage du package local
    echo -e "${WHITE}Mode de nommage du package local:${NC}"
    echo -e "  ${CYAN}auto${NC}    : dérive -env sauf stack streaming-kafka"
    echo -e "  ${CYAN}fixed${NC}   : nom fixe (PROJECT_NAME)"
    echo -e "  ${CYAN}derived${NC} : dérive -env si détecté"
    echo ""
    ask_input "Mode (auto/fixed/derived)" "${PACKAGE_NAME_MODE:-auto}" PACKAGE_NAME_MODE

    case "$PACKAGE_NAME_MODE" in
        auto|fixed|derived) ;;
        *)
            log_warn "Mode invalide '${PACKAGE_NAME_MODE}', utilisation de 'auto'"
            PACKAGE_NAME_MODE="auto"
            ;;
    esac

    # Chemin du package (proposé dynamiquement selon le mode)
    local suggested_package_dir
    suggested_package_dir="$(resolve_package_dir)"
    ask_input "Chemin du package" "$suggested_package_dir" PACKAGE_DIR

    echo ""
    log_info "Les fichiers .env réels seront automatiquement:"
    echo "  1. Copiés depuis la racine du projet"
    echo "  2. Chiffrés sur le serveur après installation"
    echo "  3. Supprimés (versions non chiffrées)"
    echo ""

    echo ""
    log_success "Configuration mise à jour"
    sleep 1
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    while true; do
        show_menu

        read -p "Votre choix: " choice

        case $choice in
            1)
                create_package
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            2)
                if configure_ssh; then
                    # Recalculer les options SSH au cas où la config a changé
                    prepare_ssh_options
                    echo ""
                    create_package
                    echo ""
                    transfer_via_ssh
                fi
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            3)
                advanced_config
                ;;
            4)
                if configure_ssh; then
                    clean_server
                fi
                echo ""
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            0)
                echo ""
                log_info "Au revoir !"
                exit 0
                ;;
            *)
                log_error "Option invalide"
                sleep 1
                ;;
        esac
    done
}

# Lancer le programme
main
