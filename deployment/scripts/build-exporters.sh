#!/bin/bash

# ============================================================================
# Build et push des images custom d'un stack monitoring
# Lit la section custom_images de .devops.yml du projet courant
#
# Usage:
#   ./build-exporters.sh [env] [options]
#   ./build-exporters.sh               Mode interactif
#
# Options:
#   --no-cache                Construire sans cache Docker
#   --all                     Inclure les services avec enabled: false
#   --service <nom>           Builder un service spécifique uniquement
#   --dry-run                 Afficher les commandes sans les exécuter
#   --push-only               Push sans rebuild (image doit exister localement)
#   --parallel                Builder tous les services en parallèle
#   --version <tag>           Tag de version (ex: v1.2.3, latest)
#   --description <texte>     Description des repos Docker Hub
#
# Exemples:
#   ./build-exporters.sh dev
#   ./build-exporters.sh dev --service debezium-exporter
#   ./build-exporters.sh dev --all --no-cache --parallel
#   ./build-exporters.sh prod --dry-run
#   ./build-exporters.sh dev --version v1.2.3 --description "Mon exporter"
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_header()  {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}
print_separator() { echo -e "${CYAN}----------------------------------------${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Charger la configuration du projet
source "$SCRIPT_DIR/config-loader.sh"
load_devops_config

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
DEVOPS_YML="$PROJECT_ROOT/.devops.yml"

# ============================================================================
# Vérifications
# ============================================================================
if [ ! -f "$DEVOPS_YML" ]; then
    log_error ".devops.yml introuvable: $DEVOPS_YML"
    log_info "Lancez ce script depuis le répertoire d'un projet avec .devops.yml"
    exit 1
fi

if ! grep -q "^custom_images:" "$DEVOPS_YML"; then
    log_error "Section 'custom_images' absente de .devops.yml"
    log_info "Ce projet ne définit pas d'images custom à builder."
    log_info "Ajoutez une section 'custom_images' dans .devops.yml pour activer cette commande."
    exit 1
fi

# ============================================================================
# Lire .devops.yml
# ============================================================================
REGISTRY_USERNAME="${REGISTRY_USERNAME:-$(grep "^registry_username:" "$DEVOPS_YML" | head -1 | awk '{print $2}' | tr -d '"'"'")}"
REGISTRY_TOKEN="${REGISTRY_TOKEN:-$(grep "^registry_token:" "$DEVOPS_YML" | head -1 | awk '{print $2}' | tr -d '"'"'")}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-$(grep "^registry_password:" "$DEVOPS_YML" | head -1 | awk '{print $2}' | tr -d '"'"'")}"
REGISTRY_URL="${REGISTRY_URL:-$(grep "^registry_url:" "$DEVOPS_YML" | head -1 | awk '{print $2}' | tr -d '"'"'")}"
REGISTRY_URL="${REGISTRY_URL:-docker.io}"

if [ -z "$REGISTRY_USERNAME" ]; then
    log_error "registry_username non défini dans .devops.yml"
    exit 1
fi

# ============================================================================
# VERSIONING SÉMANTIQUE
# ============================================================================

# Générer un tag de version basé sur la date et le commit
generate_version_tag() {
    local env=$1
    local date_tag
    date_tag=$(date +%Y%m%d-%H%M%S)
    local git_hash
    git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
    echo "${env}-v${date_tag}-${git_hash}"
}

# Extraire la dernière version depuis les tags Docker Hub pour une image donnée
get_latest_version() {
    local env=$1
    local image_name=$2
    local api_url="https://hub.docker.com/v2/repositories/${REGISTRY_USERNAME}/${image_name}/tags?page_size=100"

    local tags
    tags=$(curl -s "$api_url" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 \
        | grep "^${env}-v[0-9]\+\.[0-9]\+\.[0-9]\+$" \
        | sed "s/^${env}-//" | sort -rV)

    if [ -z "$tags" ]; then
        echo "v0.0.0"
        return 0
    fi

    echo "$tags" | head -n1
}

# Incrémenter une version (PATCH, MINOR, MAJOR)
increment_version() {
    local version=$1
    local type=$2

    version=${version#v}

    local major minor patch
    IFS='.' read -r major minor patch <<< "$version"

    case "$type" in
        PATCH) ((patch++)) ;;
        MINOR) ((minor++)); patch=0 ;;
        MAJOR) ((major++)); minor=0; patch=0 ;;
        *)
            echo "Type invalide: $type" >&2
            return 1
            ;;
    esac

    echo "v${major}.${minor}.${patch}"
}

# Menu interactif de sélection de version
# Arg1: env, Arg2: image de référence pour récupérer la dernière version
choose_version() {
    local env=$1
    local ref_image=$2

    echo "" >&2
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}║      Gestion de Version (Semantic Versioning)     ║${NC}" >&2
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2

    local current_version
    if [ -n "$ref_image" ]; then
        log_info "Récupération de la dernière version depuis Docker Hub..." >&2
        current_version=$(get_latest_version "$env" "$ref_image")
    else
        current_version="v0.0.0"
    fi

    echo -e "${WHITE}ℹ️  Dernière version: ${GREEN}${current_version}${NC}" >&2
    echo "" >&2
    echo -e "${CYAN}Type de version (Versioning Sémantique):${NC}" >&2
    echo "" >&2

    local patch_version minor_version major_version
    patch_version=$(increment_version "$current_version" "PATCH")
    minor_version=$(increment_version "$current_version" "MINOR")
    major_version=$(increment_version "$current_version" "MAJOR")

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
    echo -e "  ${GREEN}5.${NC} ${WHITE}Date+Hash${NC} - Format: ${env}-v$(date +%Y%m%d)-abc123 (ancien style)" >&2
    echo -e "  ${GREEN}6.${NC} ${WHITE}Latest${NC} - Utiliser ${env}-latest" >&2
    echo -e "  ${GREEN}0.${NC} Annuler" >&2
    echo "" >&2

    local version_choice
    read -p "Choisissez le type de version (0-6): " version_choice

    case "$version_choice" in
        1) echo "$patch_version" ;;
        2) echo "$minor_version" ;;
        3) echo "$major_version" ;;
        4)
            echo "" >&2
            local custom_version
            read -p "Entrez la version (format: vX.Y.Z): " custom_version
            if [[ "$custom_version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                custom_version=${custom_version#v}
                echo "v${custom_version}"
            else
                log_error "Format invalide. Utilisez vX.Y.Z (ex: v1.2.3)" >&2
                return 1
            fi
            ;;
        5) generate_version_tag "$env" ;;
        6) echo "latest" ;;
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
# Créer un repo Docker Hub s'il n'existe pas encore
# L'API Hub requiert un JWT obtenu via /v2/users/login (pas le PAT directement)
# ============================================================================

DOCKERHUB_JWT=""  # JWT global, initialisé une seule fois

get_dockerhub_jwt() {
    local username="$1"
    local pat="$2"

    [ -z "$pat" ] && return 0

    local resp curl_rc
    resp=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${username}\",\"password\":\"${pat}\"}" \
        "https://hub.docker.com/v2/users/login")
    curl_rc=$?

    if [ "$curl_rc" -ne 0 ]; then
        log_warn "  Impossible d'obtenir le JWT Docker Hub (erreur réseau/curl) — création de repo désactivée"
        return 0
    fi

    local code body
    code=$(printf '%s\n' "$resp" | tail -n 1)
    body=$(printf '%s\n' "$resp" | sed '$d')

    if [ "$code" = "200" ]; then
        DOCKERHUB_JWT=$(echo "$body" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    else
        log_warn "  Impossible d'obtenir le JWT Docker Hub (code $code) — création de repo désactivée"
    fi
}

ensure_dockerhub_repo_exists() {
    local image_name="$1"
    local username="$2"
    local description="${3:-Custom image - ${image_name}}"

    [ -z "$DOCKERHUB_JWT" ] && return 0

    local repo_url="https://hub.docker.com/v2/repositories/${username}/${image_name}/"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: JWT ${DOCKERHUB_JWT}" \
        "$repo_url")

    if [ "$http_code" = "200" ]; then
        log_info "  Repo Docker Hub existant: ${username}/${image_name}"
        return 0
    fi

    log_info "  Création du repo Docker Hub: ${username}/${image_name} ..."
    local create_resp
    create_resp=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: JWT ${DOCKERHUB_JWT}" \
        -d "{\"name\":\"${image_name}\",\"namespace\":\"${username}\",\"is_private\":false,\"description\":\"${description}\"}" \
        "https://hub.docker.com/v2/repositories/")

    local create_code
    create_code=$(echo "$create_resp" | tail -1)

    if [ "$create_code" = "201" ]; then
        log_success "  Repo créé: ${username}/${image_name}"
    elif [ "$create_code" = "200" ]; then
        log_success "  Repo existant (race condition): ${username}/${image_name}"
    else
        log_warn "  Impossible de créer le repo via API (code $create_code) — le push tentera quand même"
    fi
}

is_registry_logged_in() {
    docker info 2>/dev/null | grep -q "Username: ${REGISTRY_USERNAME}"
}

# ============================================================================
# Parser custom_images depuis .devops.yml
# Retourne des lignes: SERVICE=x IMAGE=y DOCKERFILE=z CONTEXT=w ENABLED=true/false
# ============================================================================
parse_custom_images() {
    awk '
    /^custom_images:/ { in_block=1; next }
    in_block && /^[a-zA-Z_]/ { in_block=0 }
    !in_block { next }

    /^[[:space:]]*-[[:space:]]+service:/ {
        if (service != "") {
            printf "SERVICE=%s IMAGE=%s DOCKERFILE=%s CONTEXT=%s ENABLED=%s\n",
                service, image_name, dockerfile, context, (enabled=="" ? "true" : enabled)
        }
        gsub(/.*service:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, ""); service=$0
        gsub(/^["'"'"']|["'"'"']$/, "", service)
        image_name=""; dockerfile=""; context=""; enabled=""
        next
    }
    /^[[:space:]]+image_name:/ {
        gsub(/.*image_name:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
        gsub(/^["'"'"']|["'"'"']$/, ""); image_name=$0; next
    }
    /^[[:space:]]+dockerfile:/ {
        gsub(/.*dockerfile:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
        gsub(/^["'"'"']|["'"'"']$/, ""); dockerfile=$0; next
    }
    /^[[:space:]]+context:/ {
        gsub(/.*context:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
        gsub(/^["'"'"']|["'"'"']$/, ""); context=$0; next
    }
    /^[[:space:]]+enabled:/ {
        gsub(/.*enabled:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
        gsub(/^["'"'"']|["'"'"']$/, ""); enabled=$0; next
    }
    END {
        if (service != "") {
            printf "SERVICE=%s IMAGE=%s DOCKERFILE=%s CONTEXT=%s ENABLED=%s\n",
                service, image_name, dockerfile, context, (enabled=="" ? "true" : enabled)
        }
    }
    ' "$DEVOPS_YML"
}

# Collecter tous les services en tableau associatif
declare -a ALL_SERVICES=()
declare -a ALL_IMAGES=()
declare -a ALL_DOCKERFILES=()
declare -a ALL_CONTEXTS=()
declare -a ALL_ENABLED=()

while IFS= read -r entry; do
    eval "$entry"
    ALL_SERVICES+=("$SERVICE")
    ALL_IMAGES+=("$IMAGE")
    ALL_DOCKERFILES+=("$DOCKERFILE")
    ALL_CONTEXTS+=("$CONTEXT")
    ALL_ENABLED+=("$ENABLED")
done < <(parse_custom_images)

if [ ${#ALL_SERVICES[@]} -eq 0 ]; then
    log_warn "Aucun service trouvé dans custom_images de .devops.yml"
    exit 0
fi

# ============================================================================
# Mode interactif (aucun argument)
# ============================================================================
interactive_mode() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${WHITE}Build Exporters - ${PROJECT_NAME:-$(basename "$PROJECT_ROOT")}${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Choisir l'environnement
    echo -e "${CYAN}Environnement:${NC}"
    echo -e "  ${CYAN}1)${NC} dev"
    echo -e "  ${CYAN}2)${NC} staging"
    echo -e "  ${CYAN}3)${NC} prod"
    echo ""
    read -p "Choisissez (1-3) [1]: " env_choice
    case "${env_choice:-1}" in
        2) ENV="staging" ;;
        3) ENV="prod" ;;
        *) ENV="dev" ;;
    esac
    echo ""

    # Afficher les services disponibles
    echo -e "${CYAN}Services disponibles:${NC}"
    print_separator
    for i in "${!ALL_SERVICES[@]}"; do
        local svc="${ALL_SERVICES[$i]}"
        local enabled="${ALL_ENABLED[$i]}"
        local img="${ALL_IMAGES[$i]}"
        local status_label=""
        if [ "$enabled" = "true" ]; then
            status_label="${GREEN}[actif]${NC}"
        else
            status_label="${YELLOW}[inactif]${NC}"
        fi
        printf "  ${CYAN}%2d)${NC} %-35s %b  → %s/%s:%s-latest\n" \
            "$((i+1))" "$svc" "$status_label" "${REGISTRY_USERNAME}" "${img}" "$ENV"
    done
    print_separator
    echo ""
    echo -e "  ${CYAN} a)${NC} Tous les actifs (enabled: true)"
    echo -e "  ${CYAN} A)${NC} Absolument tous (enabled: false inclus)"
    echo -e "  ${CYAN} 0)${NC} Annuler"
    echo ""

    read -p "Votre choix: " svc_choice

    case "$svc_choice" in
        0) log_info "Annulé."; exit 0 ;;
        a) FILTER_SERVICE=""; INCLUDE_ALL=false ;;
        A) FILTER_SERVICE=""; INCLUDE_ALL=true ;;
        *)
            if [[ "$svc_choice" =~ ^[0-9]+$ ]] && [ "$svc_choice" -ge 1 ] && [ "$svc_choice" -le "${#ALL_SERVICES[@]}" ]; then
                FILTER_SERVICE="${ALL_SERVICES[$((svc_choice-1))]}"
                INCLUDE_ALL=true
            else
                log_error "Choix invalide: $svc_choice"
                exit 1
            fi
            ;;
    esac
    echo ""

    # Déterminer l'image de référence pour la version (premier service sélectionné actif)
    local ref_image=""
    for i in "${!ALL_SERVICES[@]}"; do
        local svc="${ALL_SERVICES[$i]}"
        local enabled="${ALL_ENABLED[$i]}"
        if [ -n "$FILTER_SERVICE" ] && [ "$svc" != "$FILTER_SERVICE" ]; then continue; fi
        if [ "$enabled" != "true" ] && ! $INCLUDE_ALL; then continue; fi
        ref_image="${ALL_IMAGES[$i]}"
        break
    done

    # Menu de version
    local raw_version
    raw_version=$(choose_version "$ENV" "$ref_image") || exit 0

    # Construire le tag final
    if [ "$raw_version" = "latest" ]; then
        VERSION_TAG="${ENV}-latest"
    else
        VERSION_TAG="${ENV}-${raw_version}"
    fi

    echo ""
    log_info "Tag sélectionné: ${WHITE}${VERSION_TAG}${NC}"
    echo ""

    # Description des repos Docker Hub
    echo -e "${CYAN}Description des repos Docker Hub:${NC}"
    echo -e "  (Laissez vide pour utiliser la description par défaut)"
    read -p "Description: " desc_input
    if [ -n "$desc_input" ]; then
        DESCRIPTION="$desc_input"
    fi
    echo ""

    # Plateformes cibles
    echo -e "${CYAN}Plateformes cibles:${NC}"
    echo -e "  ${CYAN}1)${NC} linux/amd64 seulement       ${GREEN}[rapide]${NC}"
    echo -e "  ${CYAN}2)${NC} linux/amd64 + linux/arm64   ${YELLOW}[lent — QEMU]${NC}"
    read -p "Choisissez (1-2) [1]: " plat_choice
    case "${plat_choice:-1}" in
        2) PLATFORMS="linux/amd64,linux/arm64" ;;
        *) PLATFORMS="linux/amd64" ;;
    esac
    echo ""

    # Options de build
    read -p "Sans cache (--no-cache)? [y/N]: " nc_choice
    [[ "$nc_choice" =~ ^[Yy]$ ]] && NO_CACHE=true || NO_CACHE=false

    # Compter les services qui seront buildés
    local selected_count=0
    for i in "${!ALL_SERVICES[@]}"; do
        local s="${ALL_SERVICES[$i]}" e="${ALL_ENABLED[$i]}"
        if [ -n "$FILTER_SERVICE" ] && [ "$s" != "$FILTER_SERVICE" ]; then continue; fi
        if [ "$e" != "true" ] && ! $INCLUDE_ALL; then continue; fi
        selected_count=$((selected_count+1))
    done

    if [ "$selected_count" -gt 1 ]; then
        read -p "Parallèle (builder tous simultanément)? [y/N]: " par_choice
        if [[ "$par_choice" =~ ^[Yy]$ ]]; then
            PARALLEL=true
            read -p "Max builds simultanés [3]: " mp_choice
            MAX_PARALLEL="${mp_choice:-3}"
        else
            PARALLEL=false
        fi
    else
        PARALLEL=false
    fi

    read -p "Dry-run (afficher sans exécuter)? [y/N]: " dr_choice
    [[ "$dr_choice" =~ ^[Yy]$ ]] && DRY_RUN=true || DRY_RUN=false

    echo ""
}

# ============================================================================
# Arguments CLI
# ============================================================================
ENV=""
NO_CACHE=false
INCLUDE_ALL=false
FILTER_SERVICE=""
DRY_RUN=false
PUSH_ONLY=false
PARALLEL=false
MAX_PARALLEL=3
DESCRIPTION=""
VERSION_TAG=""
PLATFORMS="linux/amd64,linux/arm64"
INTERACTIVE=false

if [ $# -eq 0 ]; then
    INTERACTIVE=true
else
    # Premier arg = env s'il ne commence pas par --
    if [[ "${1:-}" != --* ]]; then
        ENV="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cache)          NO_CACHE=true ;;
            --all)               INCLUDE_ALL=true ;;
            --service)           FILTER_SERVICE="$2"; INCLUDE_ALL=true; shift ;;
            --dry-run)           DRY_RUN=true ;;
            --push-only)         PUSH_ONLY=true ;;
            --parallel)          PARALLEL=true ;;
            --max-parallel)      MAX_PARALLEL="$2"; shift ;;
            --version)           VERSION_TAG="$2"; shift ;;
            --description)       DESCRIPTION="$2"; shift ;;
            --platform)          PLATFORMS="$2"; shift ;;
            --amd64-only)        PLATFORMS="linux/amd64" ;;
            *) log_warn "Argument inconnu: $1" ;;
        esac
        shift
    done
fi

if $INTERACTIVE; then
    interactive_mode
fi

ENV="${ENV:-dev}"

# Résoudre le tag de version si non défini (mode CLI sans --version)
if [ -z "$VERSION_TAG" ]; then
    VERSION_TAG="${ENV}-latest"
fi

# ============================================================================
# Login Docker Hub
# ============================================================================
if ! $DRY_RUN; then
    if is_registry_logged_in; then
        log_success "Session Docker déjà authentifiée pour '$REGISTRY_USERNAME' (login ignoré)"
    else
        log_info "Login Docker Hub ($REGISTRY_USERNAME)..."

        local_auth_secret=""
        if [ -n "$REGISTRY_TOKEN" ]; then
            local_auth_secret="$REGISTRY_TOKEN"
            if ! printf '%s' "$REGISTRY_TOKEN" | docker login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" --password-stdin; then
                log_error "Échec de l'authentification Docker Hub pour l'utilisateur '$REGISTRY_USERNAME'. Vérifiez registry_username/registry_token."
                exit 1
            fi
        elif [ -n "$REGISTRY_PASSWORD" ]; then
            local_auth_secret="$REGISTRY_PASSWORD"
            if ! printf '%s' "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" --password-stdin; then
                log_error "Échec de l'authentification Docker Hub pour l'utilisateur '$REGISTRY_USERNAME'. Vérifiez registry_username/registry_password."
                exit 1
            fi
        else
            log_error "Aucun credential Docker Hub détecté (registry_token/registry_password) et aucune session active."
            exit 1
        fi

        log_success "Authentifié sur Docker Hub"
        log_info "Obtention du JWT Docker Hub pour l'API..."
        get_dockerhub_jwt "$REGISTRY_USERNAME" "$local_auth_secret"
        [ -n "$DOCKERHUB_JWT" ] && log_success "JWT Docker Hub obtenu" || true
    fi
fi

# ============================================================================
# Construire la liste des services à traiter
# ============================================================================
declare -a BUILD_SERVICES=()
declare -a BUILD_IMAGES=()
declare -a BUILD_DOCKERFILES=()
declare -a BUILD_CONTEXTS=()
declare -a BUILD_ENABLED=()

for i in "${!ALL_SERVICES[@]}"; do
    SVC="${ALL_SERVICES[$i]}"
    IMG="${ALL_IMAGES[$i]}"
    DFILE="${ALL_DOCKERFILES[$i]}"
    CTX="${ALL_CONTEXTS[$i]}"
    ENABLED="${ALL_ENABLED[$i]}"

    if [ -n "$FILTER_SERVICE" ] && [ "$SVC" != "$FILTER_SERVICE" ]; then
        continue
    fi

    if [ "$ENABLED" != "true" ] && ! $INCLUDE_ALL; then
        continue
    fi

    BUILD_SERVICES+=("$SVC")
    BUILD_IMAGES+=("$IMG")
    BUILD_DOCKERFILES+=("$DFILE")
    BUILD_CONTEXTS+=("$CTX")
    BUILD_ENABLED+=("$ENABLED")
done

# ============================================================================
# Fonction de build d'un service (utilisée en séquentiel et en parallèle)
# Sortie vers stdout/stderr du contexte appelant ou vers un fichier log.
# Retourne 0 (succès) ou 1 (échec).
# ============================================================================
build_one_service() {
    local SVC="$1"
    local IMG="$2"
    local DFILE="$3"
    local CTX="$4"
    local ENABLED="$5"

    local FULL_IMAGE="${REGISTRY_USERNAME}/${IMG}:${VERSION_TAG}"
    local DOCKERFILE_ABS="$PROJECT_ROOT/$DFILE"
    local CONTEXT_ABS="$PROJECT_ROOT/$CTX"

    echo ""
    print_separator
    log_info "Service    : $SVC"
    log_info "Image      : $FULL_IMAGE"
    log_info "Dockerfile : $DFILE"
    log_info "Context    : $CTX"
    [ "$ENABLED" != "true" ] && log_warn "  (enabled: false — buildé car --all ou --service)"
    print_separator

    if [ ! -f "$DOCKERFILE_ABS" ]; then
        log_warn "⚠ Dockerfile introuvable: $DOCKERFILE_ABS — ignoré"
        return 2  # code 2 = skipped
    fi
    if [ ! -d "$CONTEXT_ABS" ]; then
        log_warn "⚠ Contexte introuvable: $CONTEXT_ABS — ignoré"
        return 2
    fi

    # Créer le repo Docker Hub si nécessaire
    if ! $DRY_RUN; then
        local repo_desc="${DESCRIPTION:-Custom exporter - ${IMG}}"
        ensure_dockerhub_repo_exists "$IMG" "$REGISTRY_USERNAME" "$repo_desc"
    fi

    if $DRY_RUN; then
        if $PUSH_ONLY; then
            echo "  [DRY-RUN] docker push $FULL_IMAGE"
        else
            local CACHE_FLAG=""
            $NO_CACHE && CACHE_FLAG="--no-cache"
            echo "  [DRY-RUN] docker buildx build --platform ${PLATFORMS} \\"
            echo "              -f $DOCKERFILE_ABS $CACHE_FLAG \\"
            echo "              -t $FULL_IMAGE --push \\"
            echo "              $CONTEXT_ABS"
        fi
        return 0
    fi

    if $PUSH_ONLY; then
        if docker push "$FULL_IMAGE"; then
            log_success "Pushed: $FULL_IMAGE"
            return 0
        else
            log_error "Échec push: $SVC"
            return 1
        fi
    else
        local BUILD_ARGS=(buildx build --platform "${PLATFORMS}"
            --file "$DOCKERFILE_ABS"
            --tag "$FULL_IMAGE"
            --push)
        $NO_CACHE && BUILD_ARGS+=(--no-cache)
        BUILD_ARGS+=("$CONTEXT_ABS")

        if docker "${BUILD_ARGS[@]}"; then
            log_success "✓ Built & pushed: $FULL_IMAGE"
            return 0
        else
            log_error "✗ Échec build: $SVC"
            return 1
        fi
    fi
}

# ============================================================================
# Build & Push — Séquentiel
# ============================================================================
run_sequential() {
    local BUILT=0 SKIPPED=0 FAILED=0

    for i in "${!BUILD_SERVICES[@]}"; do
        local rc=0
        build_one_service \
            "${BUILD_SERVICES[$i]}" \
            "${BUILD_IMAGES[$i]}" \
            "${BUILD_DOCKERFILES[$i]}" \
            "${BUILD_CONTEXTS[$i]}" \
            "${BUILD_ENABLED[$i]}" || rc=$?

        case $rc in
            0) BUILT=$((BUILT+1)) ;;
            2) SKIPPED=$((SKIPPED+1)) ;;
            *) FAILED=$((FAILED+1)) ;;
        esac
    done

    print_summary "$BUILT" "$SKIPPED" "$FAILED"
    [ "$FAILED" -gt 0 ] && exit 1 || exit 0
}

# ============================================================================
# Build & Push — Parallèle
# ============================================================================
run_parallel() {
    local TMPDIR_LOGS
    TMPDIR_LOGS=$(mktemp -d)
    trap 'rm -rf "$TMPDIR_LOGS"' EXIT

    declare -a PIDS=()
    declare -a SVC_NAMES=()
    declare -a SHOWN=()

    local total=${#BUILD_SERVICES[@]}
    # Limiter la concurrence pour éviter de saturer BuildKit (défaut: 3)
    local max_parallel="${MAX_PARALLEL:-3}"
    [ "$max_parallel" -gt "$total" ] && max_parallel=$total

    log_info "Lancement en parallèle de ${total} service(s) (max ${max_parallel} simultanés)..."
    echo ""

    local launched=0
    local i=0

    # Lancer les builds avec un semaphore sur max_parallel slots
    while [ "$i" -lt "$total" ]; do
        # Compter les slots actifs (jobs lancés mais pas encore terminés)
        local active=0
        for j in "${!PIDS[@]}"; do
            [ "${SHOWN[$j]:-0}" = "0" ] && [ -n "${PIDS[$j]:-}" ] && \
                kill -0 "${PIDS[$j]}" 2>/dev/null && active=$((active+1))
        done

        if [ "$active" -lt "$max_parallel" ]; then
            local svc="${BUILD_SERVICES[$i]}"
            local log_file="$TMPDIR_LOGS/${i}.log"
            local rc_file="$TMPDIR_LOGS/${i}.rc"

            (
                build_one_service \
                    "${BUILD_SERVICES[$i]}" \
                    "${BUILD_IMAGES[$i]}" \
                    "${BUILD_DOCKERFILES[$i]}" \
                    "${BUILD_CONTEXTS[$i]}" \
                    "${BUILD_ENABLED[$i]}"
                echo $? > "$rc_file"
            ) > "$log_file" 2>&1 &

            PIDS+=($!)
            SVC_NAMES+=("$svc")
            SHOWN+=(0)
            log_info "▶  [$((launched+1))/${total}] ${svc} démarré (PID $!)"
            launched=$((launched+1))
            i=$((i+1))
        else
            sleep 1
        fi
    done

    echo ""

    local BUILT=0 SKIPPED=0 FAILED=0
    local completed=0

    # Polling loop : affiche les logs dès qu'un service termine, dans l'ordre de complétion
    while [ "$completed" -lt "$total" ]; do
        for i in "${!PIDS[@]}"; do
            [ "${SHOWN[$i]}" = "1" ] && continue

            local rc_file="$TMPDIR_LOGS/${i}.rc"
            local log_file="$TMPDIR_LOGS/${i}.log"
            local svc="${SVC_NAMES[$i]}"

            # Le service a terminé dès que son rc_file apparaît
            if [ -f "$rc_file" ]; then
                local rc
                rc=$(cat "$rc_file")
                SHOWN[$i]=1
                completed=$((completed+1))

                echo ""
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${WHITE}[${completed}/${total}] ${svc}${NC}"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                cat "$log_file"

                case $rc in
                    0)
                        log_success "✓ ${svc} — succès"
                        BUILT=$((BUILT+1))
                        ;;
                    2)
                        log_warn "⊘ ${svc} — ignoré (Dockerfile/contexte introuvable)"
                        SKIPPED=$((SKIPPED+1))
                        ;;
                    *)
                        log_error "✗ ${svc} — ÉCHEC (code ${rc})"
                        FAILED=$((FAILED+1))
                        ;;
                esac

                # Afficher les services encore en cours
                if [ "$completed" -lt "$total" ]; then
                    local still=()
                    for j in "${!SVC_NAMES[@]}"; do
                        [ "${SHOWN[$j]}" = "0" ] && still+=("${SVC_NAMES[$j]}")
                    done
                    [ ${#still[@]} -gt 0 ] && \
                        echo -e "  ${YELLOW}⏳ En cours : ${still[*]}${NC}"
                fi
            fi
        done

        [ "$completed" -lt "$total" ] && sleep 1
    done

    # Nettoyage des jobs background
    for pid in "${PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    print_summary "$BUILT" "$SKIPPED" "$FAILED"
    [ "$FAILED" -gt 0 ] && exit 1 || exit 0
}

# ============================================================================
# Résumé
# ============================================================================
print_summary() {
    local BUILT=$1 SKIPPED=$2 FAILED=$3
    echo ""
    log_header "Résumé"
    log_info  "Tag         : ${VERSION_TAG}"
    log_info  "Plateformes : ${PLATFORMS}"
    [ -n "$DESCRIPTION" ] && log_info "Description : ${DESCRIPTION}"
    [ "$BUILT"   -gt 0 ] && log_success "Built/pushed : $BUILT"
    [ "$SKIPPED" -gt 0 ] && log_warn    "Ignorés      : $SKIPPED"
    [ "$FAILED"  -gt 0 ] && log_error   "Échoués      : $FAILED"
    echo ""
    if [ "$FAILED" -gt 0 ]; then
        log_error "Des erreurs sont survenues."
    else
        log_success "Terminé."
    fi
}

# ============================================================================
# Point d'entrée
# ============================================================================
if [ ${#BUILD_SERVICES[@]} -eq 0 ]; then
    # Afficher les ignorés
    for i in "${!ALL_SERVICES[@]}"; do
        SVC="${ALL_SERVICES[$i]}"
        if [ -n "$FILTER_SERVICE" ] && [ "$SVC" != "$FILTER_SERVICE" ]; then continue; fi
        log_info "⊘  $SVC — ignoré (enabled: false). Utilisez --all pour forcer."
    done
    log_warn "Aucun service à builder."
    exit 0
fi

log_header "Build & Push Exporters — ${PROJECT_NAME:-$(basename "$PROJECT_ROOT")} [${ENV}] — ${VERSION_TAG}"

if $PARALLEL && [ ${#BUILD_SERVICES[@]} -gt 1 ]; then
    run_parallel
else
    [ ${#BUILD_SERVICES[@]} -eq 1 ] && $PARALLEL && \
        log_info "Un seul service sélectionné — mode séquentiel."
    run_sequential
fi
