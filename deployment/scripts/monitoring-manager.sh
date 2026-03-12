#!/usr/bin/env bash

# ============================================================================
# DevOps - Monitoring Manager
# Gestion centralisee des serveurs monitoring + orchestration agent par serveur
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

trim() {
    local value="$1"
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    echo "$value"
}


yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

expand_home_path() {
    local path="$1"
    if [[ "$path" == ~/* ]]; then
        echo "${HOME}/${path#~/}"
    else
        echo "$path"
    fi
}

resolve_project_root() {
    if [ -n "${PROJECT_ROOT:-}" ] && [ -d "${PROJECT_ROOT}" ]; then
        echo "$PROJECT_ROOT"
        return 0
    fi

    local dir="$(pwd)"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.devops.yml" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    echo "$(pwd)"
}

PROJECT_ROOT="$(resolve_project_root)"
CONFIG_FILE="$PROJECT_ROOT/.devops.yml"

read_top_level_key() {
    local key="$1"
    local file="$2"

    if [ ! -f "$file" ]; then
        return 0
    fi

    awk -v key="$key" '
        function trim(s) {
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            return s
        }
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            line=$0
            sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            line=trim(line)
            gsub(/^"|"$/, "", line)
            gsub(/^\047|\047$/, "", line)
            print line
            exit
        }
    ' "$file"
}

PROJECT_NAME="${PROJECT_NAME:-$(read_top_level_key "project_name" "$CONFIG_FILE")}" 
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="$(basename "$PROJECT_ROOT")"
fi

SERVER_DEPLOY_PATH="${SERVER_DEPLOY_PATH:-$(read_top_level_key "server_deploy_path" "$CONFIG_FILE")}" 
SERVER_SSH_KEY="${SERVER_SSH_KEY:-$(read_top_level_key "server_ssh_key" "$CONFIG_FILE")}" 
SERVER_PORT="${SERVER_PORT:-$(read_top_level_key "server_port" "$CONFIG_FILE")}" 

MONITORING_SERVERS_FILE="${MONITORING_SERVERS_FILE:-$(read_top_level_key "monitoring_servers_file" "$CONFIG_FILE")}" 
if [ -z "$MONITORING_SERVERS_FILE" ]; then
    MONITORING_SERVERS_FILE="$PROJECT_ROOT/.devops.monitoring-servers.yml"
elif [[ "$MONITORING_SERVERS_FILE" != /* ]]; then
    MONITORING_SERVERS_FILE="$PROJECT_ROOT/$MONITORING_SERVERS_FILE"
fi

if [ -z "$SERVER_PORT" ]; then
    SERVER_PORT="22"
fi

default_deploy_path_for_user() {
    local user="$1"
    if [ -n "$SERVER_DEPLOY_PATH" ]; then
        local cleaned="${SERVER_DEPLOY_PATH%/}"
        if [[ "$cleaned" == */"$PROJECT_NAME" ]]; then
            echo "$cleaned"
        else
            echo "$cleaned/$PROJECT_NAME"
        fi
    else
        echo "/home/${user}/apps/${PROJECT_NAME}"
    fi
}

normalize_deploy_path() {
    local candidate="$1"
    local user="$2"

    if [ -z "$candidate" ]; then
        default_deploy_path_for_user "$user"
        return 0
    fi

    candidate="${candidate%/}"
    if [[ "$candidate" == */"$PROJECT_NAME" ]]; then
        echo "$candidate"
    else
        echo "$candidate/$PROJECT_NAME"
    fi
}

ensure_servers_file() {
    local file="$MONITORING_SERVERS_FILE"
    local parent
    parent="$(dirname "$file")"

    mkdir -p "$parent"

    if [ ! -f "$file" ]; then
        cat > "$file" <<YAML
# Serveurs monitoring geres par DevOps CLI
# Ce fichier est genere/maintenu par: devops monitoring servers ...
monitoring_servers:
YAML
        log_success "Fichier cree: $file"
    fi
}

parse_servers() {
    local file="$MONITORING_SERVERS_FILE"

    if [ ! -f "$file" ]; then
        return 0
    fi

    awk '
        function trim(s) {
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            return s
        }
        function normalize(v) {
            v=trim(v)
            gsub(/^"|"$/, "", v)
            gsub(/^\047|\047$/, "", v)
            return v
        }
        function flush() {
            if (name != "") {
                if (port == "") {
                    port="22"
                }
                print name "|" host "|" port "|" user "|" ssh_key "|" deploy_path
            }
        }
        /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            flush()
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            name=normalize(line)
            host=""
            port=""
            user=""
            ssh_key=""
            deploy_path=""
            next
        }
        name != "" && /^[[:space:]]*host:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*host:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            host=normalize(line)
            next
        }
        name != "" && /^[[:space:]]*port:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*port:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            port=normalize(line)
            next
        }
        name != "" && /^[[:space:]]*user:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*user:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            user=normalize(line)
            next
        }
        name != "" && /^[[:space:]]*ssh_key:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*ssh_key:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            ssh_key=normalize(line)
            next
        }
        name != "" && /^[[:space:]]*deploy_path:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*deploy_path:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            deploy_path=normalize(line)
            next
        }
        END {
            flush()
        }
    ' "$file"
}

server_exists() {
    local target="$1"
    parse_servers | awk -F'|' -v target="$target" '$1 == target { found=1 } END { exit(found ? 0 : 1) }'
}

write_servers_from_lines() {
    local lines=()
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        lines+=("$row")
    done

    ensure_servers_file

    {
        echo "# Serveurs monitoring geres par DevOps CLI"
        echo "# Ce fichier est genere/maintenu par: devops monitoring servers ..."
        echo "monitoring_servers:"

        local row name host port user ssh_key deploy_path
        for row in "${lines[@]}"; do
            IFS='|' read -r name host port user ssh_key deploy_path <<< "$row"
            [ -z "$name" ] && continue
            [ -z "$port" ] && port="22"
            [ -z "$ssh_key" ] && ssh_key="~/.ssh/id_rsa"
            [ -z "$deploy_path" ] && deploy_path="$(default_deploy_path_for_user "$user")"

            printf "  - name: %s\n" "$(yaml_quote "$name")"
            printf "    host: %s\n" "$(yaml_quote "$host")"
            printf "    port: %s\n" "$(yaml_quote "$port")"
            printf "    user: %s\n" "$(yaml_quote "$user")"
            printf "    ssh_key: %s\n" "$(yaml_quote "$ssh_key")"
            printf "    deploy_path: %s\n" "$(yaml_quote "$deploy_path")"
        done
    } > "$MONITORING_SERVERS_FILE"
}

bootstrap_from_single_server() {
    ensure_servers_file

    if [ -n "$(parse_servers)" ]; then
        return 0
    fi

    local legacy_name legacy_host legacy_user legacy_port legacy_key legacy_path
    legacy_name="${SERVER_NAME:-$(read_top_level_key "server_name" "$CONFIG_FILE")}" 
    legacy_host="${SERVER_HOST:-$(read_top_level_key "server_host" "$CONFIG_FILE")}" 
    legacy_user="${SERVER_USER:-$(read_top_level_key "server_user" "$CONFIG_FILE")}" 
    legacy_port="${SERVER_PORT:-$(read_top_level_key "server_port" "$CONFIG_FILE")}" 
    legacy_key="${SERVER_SSH_KEY:-$(read_top_level_key "server_ssh_key" "$CONFIG_FILE")}" 
    legacy_path="${SERVER_DEPLOY_PATH:-$(read_top_level_key "server_deploy_path" "$CONFIG_FILE")}" 

    if [ -z "$legacy_host" ] || [ -z "$legacy_user" ]; then
        return 0
    fi

    if [ -z "$legacy_name" ]; then
        legacy_name="${PROJECT_NAME}-primary"
    fi
    if [ -z "$legacy_port" ]; then
        legacy_port="22"
    fi
    if [ -z "$legacy_key" ]; then
        legacy_key="~/.ssh/id_rsa"
    fi
    legacy_path="$(normalize_deploy_path "$legacy_path" "$legacy_user")"

    local line
    line="$legacy_name|$legacy_host|$legacy_port|$legacy_user|$legacy_key|$legacy_path"
    write_servers_from_lines <<< "$line"
    log_info "Serveur legacy importe dans: $MONITORING_SERVERS_FILE"
}

cmd_servers_list() {
    ensure_servers_file
    bootstrap_from_single_server

    local lines=()
    local row
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        lines+=("$row")
    done < <(parse_servers)

    if [ ${#lines[@]} -eq 0 ]; then
        log_warn "Aucun serveur monitoring configure"
        echo "Ajoutez un serveur avec:"
        echo "  devops monitoring servers add <name> <host> <user> [port] [deploy_path] [ssh_key]"
        return 0
    fi

    printf "%-22s %-16s %-12s %-6s %-44s %s\n" "NAME" "HOST" "USER" "PORT" "DEPLOY_PATH" "SSH_KEY"
    printf "%-22s %-16s %-12s %-6s %-44s %s\n" "----------------------" "----------------" "------------" "------" "--------------------------------------------" "--------------------------"

    local name host port user ssh_key deploy_path
    for row in "${lines[@]}"; do
        IFS='|' read -r name host port user ssh_key deploy_path <<< "$row"
        printf "%-22s %-16s %-12s %-6s %-44s %s\n" "$name" "$host" "$user" "$port" "$deploy_path" "$ssh_key"
    done
}

cmd_servers_add() {
    ensure_servers_file

    local name="${1:-}"
    local host="${2:-}"
    local user="${3:-}"
    local port="${4:-$SERVER_PORT}"
    local deploy_path="${5:-}"
    local ssh_key="${6:-${SERVER_SSH_KEY:-~/.ssh/id_rsa}}"

    if [ -z "$name" ] || [ -z "$host" ] || [ -z "$user" ]; then
        if [ -t 0 ]; then
            [ -z "$name" ] && read -r -p "Nom serveur: " name
            [ -z "$host" ] && read -r -p "Host/IP serveur: " host
            [ -z "$user" ] && read -r -p "Utilisateur SSH: " user
        fi
        if [ -z "$name" ] || [ -z "$host" ] || [ -z "$user" ]; then
            log_error "Usage: devops monitoring servers add <name> <host> <user> [port] [deploy_path] [ssh_key]"
            return 1
        fi
    fi

    if [ -z "$port" ]; then
        port="22"
    fi

    if [ -z "$deploy_path" ]; then
        deploy_path="$(default_deploy_path_for_user "$user")"
    fi

    if server_exists "$name"; then
        log_error "Serveur deja existant: $name"
        log_info "Utilisez 'devops monitoring servers set ...' pour mettre a jour"
        return 1
    fi

    local lines=()
    local row
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        lines+=("$row")
    done < <(parse_servers)

    lines+=("$name|$host|$port|$user|$ssh_key|$deploy_path")

    printf '%s\n' "${lines[@]}" | write_servers_from_lines
    log_success "Serveur ajoute: $name"
}

cmd_servers_set() {
    ensure_servers_file

    local name="${1:-}"
    local host="${2:-}"
    local user="${3:-}"
    local port="${4:-$SERVER_PORT}"
    local deploy_path="${5:-}"
    local ssh_key="${6:-${SERVER_SSH_KEY:-~/.ssh/id_rsa}}"

    if [ -z "$name" ] || [ -z "$host" ] || [ -z "$user" ]; then
        if [ -t 0 ]; then
            [ -z "$name" ] && read -r -p "Nom serveur: " name
            [ -z "$host" ] && read -r -p "Host/IP serveur: " host
            [ -z "$user" ] && read -r -p "Utilisateur SSH: " user
        fi
        if [ -z "$name" ] || [ -z "$host" ] || [ -z "$user" ]; then
            log_error "Usage: devops monitoring servers set <name> <host> <user> [port] [deploy_path] [ssh_key]"
            return 1
        fi
    fi

    if [ -z "$port" ]; then
        port="22"
    fi
    if [ -z "$deploy_path" ]; then
        deploy_path="$(default_deploy_path_for_user "$user")"
    fi

    local lines=()
    local row current_name
    local replaced=false

    while IFS= read -r row; do
        [ -z "$row" ] && continue
        IFS='|' read -r current_name _ <<< "$row"
        if [ "$current_name" = "$name" ]; then
            lines+=("$name|$host|$port|$user|$ssh_key|$deploy_path")
            replaced=true
        else
            lines+=("$row")
        fi
    done < <(parse_servers)

    if [ "$replaced" = false ]; then
        lines+=("$name|$host|$port|$user|$ssh_key|$deploy_path")
        log_info "Serveur inexistant, creation: $name"
    fi

    printf '%s\n' "${lines[@]}" | write_servers_from_lines
    log_success "Serveur enregistre: $name"
}

cmd_servers_remove() {
    ensure_servers_file

    local target="${1:-}"
    if [ -z "$target" ]; then
        if [ -t 0 ]; then
            read -r -p "Nom serveur à supprimer: " target
        fi
        if [ -z "$target" ]; then
            log_error "Usage: devops monitoring servers remove <name>"
            return 1
        fi
    fi

    if ! server_exists "$target"; then
        log_error "Serveur non trouve: $target"
        return 1
    fi

    local lines=()
    local row current_name
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        IFS='|' read -r current_name _ <<< "$row"
        if [ "$current_name" != "$target" ]; then
            lines+=("$row")
        fi
    done < <(parse_servers)

    if [ ${#lines[@]} -eq 0 ]; then
        write_servers_from_lines < /dev/null
    else
        printf '%s
' "${lines[@]}" | write_servers_from_lines
    fi

    log_success "Serveur supprime: $target"
}

find_server_by_name() {
    local target="$1"
    parse_servers | awk -F'|' -v target="$target" '$1 == target { print; exit }'
}

run_remote_agent() {
    local row="$1"
    local env="$2"
    local action="$3"
    local extra="$4"
    local dry_run="$5"

    local name host port user ssh_key deploy_path
    IFS='|' read -r name host port user ssh_key deploy_path <<< "$row"

    if [ -z "$host" ] || [ -z "$user" ] || [ -z "$deploy_path" ]; then
        log_error "Configuration incomplete pour serveur: $name"
        return 1
    fi

    local remote_cmd
    remote_cmd=$(printf "cd %q && ./deployment/scripts/deploy-registry.sh monitoring-agent %q %q" "$deploy_path" "$env" "$action")
    if [ -n "$extra" ]; then
        remote_cmd+=" $(printf %q "$extra")"
    fi

    local expanded_ssh_key=""
    if [ -n "$ssh_key" ]; then
        expanded_ssh_key="$(expand_home_path "$ssh_key")"
    fi

    local -a ssh_cmd=(ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=8)
    if [ -n "$expanded_ssh_key" ]; then
        ssh_cmd+=( -i "$expanded_ssh_key" )
    fi
    ssh_cmd+=("${user}@${host}" "$remote_cmd")

    log_header "MONITORING AGENT [$name] ${action} (${env})"
    log_info "Target: ${user}@${host}:${port}"
    log_info "Remote path: $deploy_path"

    if [ "$dry_run" = true ]; then
        printf '[DRY-RUN] '
        printf '%q ' "${ssh_cmd[@]}"
        printf '\n'
        return 0
    fi

    "${ssh_cmd[@]}"
}

cmd_agent() {
    ensure_servers_file
    bootstrap_from_single_server

    local env="${1:-}"
    if [ -z "$env" ]; then
        if [ -t 0 ]; then
            read -r -p "Environnement (dev/staging/prod) [prod]: " env
            env="${env:-prod}"
        fi
        if [ -z "$env" ]; then
            log_error "Usage: devops monitoring agent <env> [up|down|restart|status|logs] [profiles_csv|service] [--all|--server <name>] [--dry-run]"
            return 1
        fi
    fi
    shift || true

    local action="status"
    local extra=""

    if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
        action="$1"
        shift
    fi

    if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
        extra="$1"
        shift
    fi

    local target_mode="one"
    local target_name="${SERVER_NAME:-}"
    local dry_run=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                target_mode="all"
                ;;
            --server)
                shift
                if [ -z "${1:-}" ]; then
                    log_error "Option --server requiert un nom"
                    return 1
                fi
                target_mode="one"
                target_name="$1"
                ;;
            --dry-run)
                dry_run=true
                ;;
            *)
                log_error "Option inconnue: $1"
                return 1
                ;;
        esac
        shift
    done

    local rows=()
    local row

    if [ "$target_mode" = "all" ]; then
        while IFS= read -r row; do
            [ -z "$row" ] && continue
            rows+=("$row")
        done < <(parse_servers)
    else
        if [ -z "$target_name" ]; then
            log_error "Aucun serveur cible. Utilisez --server <name> ou --all"
            return 1
        fi
        row="$(find_server_by_name "$target_name")"
        if [ -z "$row" ]; then
            log_error "Serveur non trouve: $target_name"
            return 1
        fi
        rows+=("$row")
    fi

    if [ ${#rows[@]} -eq 0 ]; then
        log_error "Aucun serveur monitoring configure"
        return 1
    fi

    local failures=0
    for row in "${rows[@]}"; do
        if ! run_remote_agent "$row" "$env" "$action" "$extra" "$dry_run"; then
            failures=$((failures + 1))
        fi
    done

    if [ "$failures" -gt 0 ]; then
        log_error "$failures serveur(s) en erreur"
        return 1
    fi

    log_success "Commande agent executee sur ${#rows[@]} serveur(s)"
}

cmd_inventory_render() {
    ensure_servers_file
    bootstrap_from_single_server

    local output_file="${1:-$PROJECT_ROOT/deployment/monitoring/ansible/inventory.monitoring-agents.yml}"
    if [[ "$output_file" != /* ]]; then
        output_file="$PROJECT_ROOT/$output_file"
    fi

    local rows=()
    local row
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        rows+=("$row")
    done < <(parse_servers)

    if [ ${#rows[@]} -eq 0 ]; then
        log_error "Aucun serveur configure, impossible de generer l'inventory"
        return 1
    fi

    mkdir -p "$(dirname "$output_file")"

    {
        echo "all:"
        echo "  children:"
        echo "    monitoring_agents:"
        echo "      hosts:"

        local name host port user ssh_key deploy_path
        for row in "${rows[@]}"; do
            IFS='|' read -r name host port user ssh_key deploy_path <<< "$row"
            echo "        $name:"
            echo "          ansible_host: $host"
            echo "          ansible_user: $user"
            echo "          ansible_port: $port"
            echo "          ansible_ssh_private_key_file: $(expand_home_path "$ssh_key")"
            echo "          monitoring_agent_project_path: $deploy_path"
        done
    } > "$output_file"

    log_success "Inventory genere: $output_file"
}

wait_for_enter() {
    if [ -t 0 ]; then
        echo ""
        read -r -p "Appuyez sur Entrée pour continuer..." _
    fi
}

select_env_numbered_mm() {
    echo ""
    echo "Environnement:"
    echo "  1) dev"
    echo "  2) staging"
    echo "  3) prod"
    echo "  0) annuler"
    read -r -p "Choix [3]: " env_choice
    env_choice="${env_choice:-3}"

    case "$env_choice" in
        1|dev)
            MM_SELECTED_ENV="dev"
            ;;
        2|staging)
            MM_SELECTED_ENV="staging"
            ;;
        3|prod)
            MM_SELECTED_ENV="prod"
            ;;
        0|cancel|annuler|q|Q)
            return 1
            ;;
        *)
            log_warn "Choix invalide, utilisation de 'prod'"
            MM_SELECTED_ENV="prod"
            ;;
    esac
}

set_target_opts_interactive() {
    TARGET_OPTS=(--all)

    if ! [ -t 0 ]; then
        return 0
    fi

    echo ""
    echo "Cible:"
    echo "  1) all"
    echo "  2) server"
    echo "  0) annuler"
    read -r -p "Choix [1]: " target_mode_choice
    target_mode_choice="${target_mode_choice:-1}"

    case "$target_mode_choice" in
        1|all)
            TARGET_OPTS=(--all)
            ;;
        2|server|one)
            read -r -p "Nom serveur: " target_server
            if [ -z "$target_server" ]; then
                log_warn "Nom serveur vide, fallback sur --all"
                TARGET_OPTS=(--all)
            else
                TARGET_OPTS=(--server "$target_server")
            fi
            ;;
        0|cancel|annuler|q|Q)
            return 1
            ;;
        *)
            log_warn "Mode cible inconnu ($target_mode_choice), fallback sur --all"
            TARGET_OPTS=(--all)
            ;;
    esac
}

interactive_menu() {
    ensure_servers_file
    bootstrap_from_single_server

    while true; do
        if [ -n "${TERM:-}" ]; then
            clear || true
        fi
        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${WHITE}Monitoring Manager - ${PROJECT_NAME}${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} ${GREEN}servers list${NC}"
        echo -e "  ${CYAN}2)${NC} ${GREEN}servers add${NC}"
        echo -e "  ${CYAN}3)${NC} ${GREEN}servers set${NC}"
        echo -e "  ${CYAN}4)${NC} ${GREEN}servers remove${NC}"
        echo -e "  ${CYAN}5)${NC} ${GREEN}agent status${NC}"
        echo -e "  ${CYAN}6)${NC} ${GREEN}agent up${NC}"
        echo -e "  ${CYAN}7)${NC} ${GREEN}agent restart${NC}"
        echo -e "  ${CYAN}8)${NC} ${GREEN}agent down${NC}"
        echo -e "  ${CYAN}9)${NC} ${GREEN}agent logs${NC}"
        echo -e "  ${CYAN}10)${NC} ${GREEN}inventory render${NC}"
        echo ""
        echo -e "  ${CYAN}h)${NC} ${GREEN}help${NC}"
        echo -e "  ${CYAN}0)${NC} ${RED}Quitter${NC}"
        echo ""

        read -r -p "Votre choix: " choice

        case "$choice" in
            1)
                cmd_servers_list
                wait_for_enter
                ;;
            2)
                read -r -p "Nom serveur: " name
                read -r -p "Host/IP: " host
                read -r -p "Utilisateur SSH: " user
                read -r -p "Port SSH [${SERVER_PORT:-22}]: " port
                port="${port:-${SERVER_PORT:-22}}"
                read -r -p "Deploy path [/home/${user}/apps/${PROJECT_NAME}]: " deploy_path
                deploy_path="${deploy_path:-/home/${user}/apps/${PROJECT_NAME}}"
                read -r -p "Clé SSH [${SERVER_SSH_KEY:-~/.ssh/id_rsa}]: " ssh_key
                ssh_key="${ssh_key:-${SERVER_SSH_KEY:-~/.ssh/id_rsa}}"
                cmd_servers_add "$name" "$host" "$user" "$port" "$deploy_path" "$ssh_key"
                wait_for_enter
                ;;
            3)
                read -r -p "Nom serveur: " name
                read -r -p "Host/IP: " host
                read -r -p "Utilisateur SSH: " user
                read -r -p "Port SSH [${SERVER_PORT:-22}]: " port
                port="${port:-${SERVER_PORT:-22}}"
                read -r -p "Deploy path [/home/${user}/apps/${PROJECT_NAME}]: " deploy_path
                deploy_path="${deploy_path:-/home/${user}/apps/${PROJECT_NAME}}"
                read -r -p "Clé SSH [${SERVER_SSH_KEY:-~/.ssh/id_rsa}]: " ssh_key
                ssh_key="${ssh_key:-${SERVER_SSH_KEY:-~/.ssh/id_rsa}}"
                cmd_servers_set "$name" "$host" "$user" "$port" "$deploy_path" "$ssh_key"
                wait_for_enter
                ;;
            4)
                read -r -p "Nom serveur à supprimer: " name
                cmd_servers_remove "$name"
                wait_for_enter
                ;;
            5)
                if ! select_env_numbered_mm; then
                    log_info "Action annulée"
                    continue
                fi
                env="$MM_SELECTED_ENV"
                if ! set_target_opts_interactive; then
                    log_info "Action annulée"
                    continue
                fi
                cmd_agent "$env" status "${TARGET_OPTS[@]}"
                wait_for_enter
                ;;
            6)
                if ! select_env_numbered_mm; then
                    log_info "Action annulée"
                    continue
                fi
                env="$MM_SELECTED_ENV"
                read -r -p "Profiles CSV (ex: kafka,jmx,node) [kafka,jmx,node]: " profiles
                profiles="${profiles:-kafka,jmx,node}"
                if ! set_target_opts_interactive; then
                    log_info "Action annulée"
                    continue
                fi
                cmd_agent "$env" up "$profiles" "${TARGET_OPTS[@]}"
                wait_for_enter
                ;;
            7)
                if ! select_env_numbered_mm; then
                    log_info "Action annulée"
                    continue
                fi
                env="$MM_SELECTED_ENV"
                if ! set_target_opts_interactive; then
                    log_info "Action annulée"
                    continue
                fi
                cmd_agent "$env" restart "${TARGET_OPTS[@]}"
                wait_for_enter
                ;;
            8)
                if ! select_env_numbered_mm; then
                    log_info "Action annulée"
                    continue
                fi
                env="$MM_SELECTED_ENV"
                if ! set_target_opts_interactive; then
                    log_info "Action annulée"
                    continue
                fi
                cmd_agent "$env" down "${TARGET_OPTS[@]}"
                wait_for_enter
                ;;
            9)
                if ! select_env_numbered_mm; then
                    log_info "Action annulée"
                    continue
                fi
                env="$MM_SELECTED_ENV"
                read -r -p "Service logs (vide=tous): " service
                if ! set_target_opts_interactive; then
                    log_info "Action annulée"
                    continue
                fi
                if [ -n "$service" ]; then
                    cmd_agent "$env" logs "$service" "${TARGET_OPTS[@]}"
                else
                    cmd_agent "$env" logs "${TARGET_OPTS[@]}"
                fi
                ;;
            10)
                read -r -p "Fichier inventory [deployment/monitoring/ansible/inventory.monitoring-agents.yml]: " out
                out="${out:-deployment/monitoring/ansible/inventory.monitoring-agents.yml}"
                cmd_inventory_render "$out"
                wait_for_enter
                ;;
            h|H)
                show_help
                wait_for_enter
                ;;
            0|q|Q)
                exit 0
                ;;
            *)
                log_error "Option invalide"
                sleep 1
                ;;
        esac
    done
}

show_help() {
    cat <<HELP
Usage:
  devops monitoring <subcommand> [options]

Subcommands:
  servers list
  servers add <name> <host> <user> [port] [deploy_path] [ssh_key]
  servers set <name> <host> <user> [port] [deploy_path] [ssh_key]
  servers remove <name>

  agent <env> [up|down|restart|status|logs] [profiles_csv|service] [--all|--server <name>] [--dry-run]
  inventory render [output_file]

Exemples:
  devops monitoring servers list
  devops monitoring servers add srvbi-pro-elk 51.79.8.117 cicbi 22 /home/cicbi/apps/cicbi-kafka-platform ~/.ssh/id_rsa
  devops monitoring servers set srvbi-pro-kafka-1 51.79.8.114 cicbi 22 /home/cicbi/apps/cicbi-kafka-platform ~/.ssh/id_rsa
  devops monitoring agent prod status --all
  devops monitoring agent prod up kafka,jmx,node --server srvbi-pro-kafka-1
  devops monitoring inventory render
HELP
}

main() {
    if [ $# -eq 0 ]; then
        if [ -t 0 ]; then
            interactive_menu
        else
            show_help
        fi
        return 0
    fi

    local command="$1"
    shift || true

    case "$command" in
        servers)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list)
                    cmd_servers_list "$@"
                    ;;
                add)
                    cmd_servers_add "$@"
                    ;;
                set|update)
                    cmd_servers_set "$@"
                    ;;
                remove|rm|delete)
                    cmd_servers_remove "$@"
                    ;;
                *)
                    log_error "Action servers inconnue: $action"
                    show_help
                    return 1
                    ;;
            esac
            ;;
        agent)
            cmd_agent "$@"
            ;;
        inventory)
            local action="${1:-render}"
            shift || true
            case "$action" in
                render)
                    cmd_inventory_render "$@"
                    ;;
                *)
                    log_error "Action inventory inconnue: $action"
                    show_help
                    return 1
                    ;;
            esac
            ;;
        interactive|menu)
            interactive_menu
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Commande monitoring inconnue: $command"
            show_help
            return 1
            ;;
    esac
}

main "$@"
