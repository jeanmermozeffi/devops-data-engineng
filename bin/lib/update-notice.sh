#!/usr/bin/env bash
# ============================================================================
# lib/update-notice.sh — Notification de mise à jour du framework
# ----------------------------------------------------------------------------
# Bibliothèque *sourcée* par devops-manager, devops et git-deploy pour signaler
# qu'une nouvelle version du framework devops-enginering est disponible, avec
# des informations enrichies : dates, nombre de commits de retard et un court
# changelog des nouveautés.
#
# ⚠️  Ne pas exécuter directement — ce fichier est destiné à être sourcé.
# Toutes les fonctions sont NON FATALES : elles retournent toujours 0 et ne
# doivent jamais interrompre le script appelant, même sous `set -euo pipefail`.
#
# Variables d'environnement reconnues :
#   DEVOPS_UPDATE_CHECK=0|no|false|off  -> désactive complètement la vérif auto
#   DEVOPS_UPDATE_CHECK=force           -> ignore le throttle (vérifie à chaque appel)
#   DEVOPS_UPDATE_INTERVAL=<secondes>   -> intervalle mini entre 2 vérifs (défaut 10800 = 3h)
#   DEVOPS_APP_ID=<id>                  -> identifiant d'app (défaut: devops-enginering)
#   NO_COLOR / sortie non-TTY           -> désactive la couleur
# ============================================================================

# Garde anti-double-source
if [ -n "${__DEVOPS_UPDATE_NOTICE_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
__DEVOPS_UPDATE_NOTICE_LOADED=1

: "${DEVOPS_APP_ID:=devops-enginering}"

__devops_state_dir() {
    printf '%s/%s' "${XDG_STATE_HOME:-$HOME/.local/state}" "${DEVOPS_APP_ID}"
}

__devops_manifest_file() {
    printf '%s/install.env' "$(__devops_state_dir)"
}

# Lit une clé du manifeste (écrit via printf %q) sans polluer l'environnement.
__devops_manifest_get() {
    local key="${1:-}" manifest
    manifest="$(__devops_manifest_file)"
    [ -n "$key" ] && [ -f "$manifest" ] || return 0
    (
        set +u 2>/dev/null || true
        # shellcheck disable=SC1090
        . "$manifest" >/dev/null 2>&1 || true
        printf '%s' "${!key:-}"
    )
}

# Couleurs uniquement sur un vrai terminal et si NO_COLOR n'est pas défini.
__devops_set_colors() {
    if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
        __C_RESET="\033[0m"; __C_YELLOW="\033[0;33m"; __C_GREEN="\033[0;32m"
        __C_CYAN="\033[0;36m"; __C_DIM="\033[2m"; __C_BOLD="\033[1m"
    else
        __C_RESET=""; __C_YELLOW=""; __C_GREEN=""; __C_CYAN=""; __C_DIM=""; __C_BOLD=""
    fi
}

# Exécute une commande avec un timeout si `timeout`/`gtimeout` existe.
__devops_with_timeout() {
    local secs="${1:-8}"; shift || true
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
    else
        "$@"
    fi
}

__devops_trunc() {
    local s="${1:-}" max="${2:-88}"
    if [ "${#s}" -gt "$max" ]; then
        printf '%s…' "${s:0:$((max - 1))}"
    else
        printf '%s' "$s"
    fi
}

# Relative « à la française » à partir d'un nombre de secondes écoulées.
# (git %cr n'est pas traduit ; on le calcule nous-mêmes pour rester cohérent.)
__devops_rel_fr() {
    local secs="${1:-}"
    case "$secs" in ''|*[!0-9]*) return 0 ;; esac
    local d=$((secs / 86400)) h=$((secs / 3600)) m=$((secs / 60))
    if   [ "$d" -ge 2 ]; then printf 'il y a %s jours' "$d"
    elif [ "$d" -eq 1 ]; then printf 'hier'
    elif [ "$h" -ge 1 ]; then printf 'il y a %sh' "$h"
    elif [ "$m" -ge 1 ]; then printf 'il y a %s min' "$m"
    else                      printf "à l'instant"
    fi
}

# ----------------------------------------------------------------------------
# Cœur : compare <repo_dir>@HEAD à origin/<track_ref> et affiche une notice.
#   $1 repo_dir        Dépôt git managé
#   $2 track_ref       Réf suivie (ex: dev, main)
#   $3 show_up_to_date 1 = afficher aussi le message « à jour » (défaut 0)
#   $4 do_fetch        1 = git fetch avant comparaison (défaut 1)
# Retourne toujours 0. Écrit sur STDERR.
# ----------------------------------------------------------------------------
devops_render_update_notice() {
    local repo_dir="${1:-}" track_ref="${2:-}" show_up_to_date="${3:-0}" do_fetch="${4:-1}"

    [ -n "$repo_dir" ] && [ -n "$track_ref" ] || return 0
    [ -d "$repo_dir/.git" ] || return 0
    command -v git >/dev/null 2>&1 || return 0

    if [ "$do_fetch" = "1" ]; then
        if ! __devops_with_timeout 8 git -C "$repo_dir" fetch --quiet origin "$track_ref" --tags >/dev/null 2>&1; then
            if [ "$show_up_to_date" = "1" ]; then
                printf '[MAJ] Impossible de vérifier les mises à jour distantes pour « %s ».\n' "$track_ref" >&2
            fi
            return 0
        fi
    fi

    local local_commit remote_commit
    local_commit="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
    remote_commit="$(git -C "$repo_dir" rev-parse "origin/$track_ref" 2>/dev/null || true)"
    [ -n "$local_commit" ] && [ -n "$remote_commit" ] || return 0

    __devops_set_colors

    if [ "$local_commit" = "$remote_commit" ]; then
        if [ "$show_up_to_date" = "1" ]; then
            printf '%b[✓]%b Framework à jour sur %b%s%b (%s).\n' \
                "$__C_GREEN" "$__C_RESET" "$__C_BOLD" "$track_ref" "$__C_RESET" "${local_commit:0:7}" >&2
        fi
        return 0
    fi

    local behind ahead
    behind="$(git -C "$repo_dir" rev-list --count "HEAD..origin/$track_ref" 2>/dev/null || echo 0)"
    ahead="$(git -C "$repo_dir" rev-list --count "origin/$track_ref..HEAD" 2>/dev/null || echo 0)"
    behind="${behind//[^0-9]/}"; behind="${behind:-0}"
    ahead="${ahead//[^0-9]/}"; ahead="${ahead:-0}"

    # Aucune nouveauté distante : la copie locale est en avance (dev du framework).
    if [ "$behind" -eq 0 ]; then
        if [ "$show_up_to_date" = "1" ]; then
            printf '%b[✓]%b %s : copie locale en avance de %s commit(s) sur origin.\n' \
                "$__C_GREEN" "$__C_RESET" "$track_ref" "$ahead" >&2
        fi
        return 0
    fi

    local ldate rdate rrel rct now
    ldate="$(git -C "$repo_dir" show -s --format='%cd' --date=format:'%Y-%m-%d %H:%M' "$local_commit" 2>/dev/null || true)"
    rdate="$(git -C "$repo_dir" show -s --format='%cd' --date=format:'%Y-%m-%d %H:%M' "$remote_commit" 2>/dev/null || true)"
    rct="$(git -C "$repo_dir" show -s --format='%ct' "$remote_commit" 2>/dev/null || echo 0)"
    now="$(date +%s 2>/dev/null || echo 0)"
    rrel=""
    if [ "${now//[^0-9]/}" -gt 0 ] 2>/dev/null && [ "${rct//[^0-9]/}" -gt 0 ] 2>/dev/null && [ "$now" -ge "$rct" ] 2>/dev/null; then
        rrel="$(__devops_rel_fr "$((now - rct))")"
    fi

    {
        printf '%b[MAJ]%b Mise à jour du framework %b%s%b disponible sur %b%s%b — %b%s commit(s)%b de retard.\n' \
            "$__C_YELLOW" "$__C_RESET" "$__C_BOLD" "$DEVOPS_APP_ID" "$__C_RESET" \
            "$__C_BOLD" "$track_ref" "$__C_RESET" "$__C_BOLD" "$behind" "$__C_RESET"
        printf '      %bLocal  %b : %s  %b(%s)%b\n' \
            "$__C_DIM" "$__C_RESET" "${local_commit:0:7}" "$__C_DIM" "${ldate:-?}" "$__C_RESET"
        printf '      %bDistant%b : %s  %b(%s%s)%b\n' \
            "$__C_DIM" "$__C_RESET" "${remote_commit:0:7}" "$__C_DIM" "${rdate:-?}" "${rrel:+ · $rrel}" "$__C_RESET"

        printf '      %bNouveautés :%b\n' "$__C_CYAN" "$__C_RESET"
        local shown=0 line
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            printf '        • %s\n' "$(__devops_trunc "$line" 90)"
            shown=$((shown + 1))
        done < <(git -C "$repo_dir" log -n 5 --format='%h  %cd  %s' --date=format:'%Y-%m-%d' "HEAD..origin/$track_ref" 2>/dev/null || true)
        if [ "$behind" -gt "$shown" ]; then
            printf '        %b… et %s commit(s) de plus%b\n' "$__C_DIM" "$((behind - shown))" "$__C_RESET"
        fi

        printf '      %bMettre à jour :%b devops-manager update --latest\n' "$__C_GREEN" "$__C_RESET"
    } >&2

    return 0
}

# ----------------------------------------------------------------------------
# Point d'entrée pour devops / git-deploy : lit le manifeste, applique un
# throttle, et affiche une notice enrichie si une mise à jour existe.
# Silencieux si : désactivé, non installé, source non-managed, throttlé,
# hors-ligne, ou déjà à jour. Retourne toujours 0.
# ----------------------------------------------------------------------------
devops_check_updates_auto() {
    case "${DEVOPS_UPDATE_CHECK:-1}" in
        0|no|false|off) return 0 ;;
    esac

    local manifest; manifest="$(__devops_manifest_file)"
    [ -f "$manifest" ] || return 0

    local source_mode repo_dir track_ref
    source_mode="$(__devops_manifest_get SOURCE_MODE)"
    [ "$source_mode" = "managed" ] || return 0

    repo_dir="$(__devops_manifest_get SOURCE_DIR)"
    [ -n "$repo_dir" ] || repo_dir="$(__devops_manifest_get MANAGED_REPO_DIR)"
    track_ref="$(__devops_manifest_get TRACK_REF)"
    [ -n "$track_ref" ] || track_ref="main"
    [ -n "$repo_dir" ] && [ -d "$repo_dir/.git" ] || return 0

    # Throttle : au plus une vérif réseau toutes les DEVOPS_UPDATE_INTERVAL sec.
    local interval="${DEVOPS_UPDATE_INTERVAL:-10800}"
    interval="${interval//[^0-9]/}"; interval="${interval:-10800}"
    local stamp now last
    stamp="$(__devops_state_dir)/last-update-check"
    now="$(date +%s 2>/dev/null || echo 0)"
    if [ "${DEVOPS_UPDATE_CHECK:-1}" != "force" ] && [ -f "$stamp" ] && [ "$now" -gt 0 ]; then
        last="$(cat "$stamp" 2>/dev/null || echo 0)"; last="${last//[^0-9]/}"; last="${last:-0}"
        if [ "$last" -gt 0 ] && [ "$((now - last))" -lt "$interval" ]; then
            return 0
        fi
    fi
    # Horodater AVANT le fetch : respecte le throttle même hors-ligne/lent.
    mkdir -p "$(__devops_state_dir)" 2>/dev/null || true
    printf '%s' "$now" > "$stamp" 2>/dev/null || true

    devops_render_update_notice "$repo_dir" "$track_ref" 0 1
    return 0
}
