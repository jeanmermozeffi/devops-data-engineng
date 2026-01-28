#!/usr/bin/env bash

# ═══════════════════════════════════════════════════════════════════════
# 🚀 Git Deployment Workflow - Interactive Script
# ═══════════════════════════════════════════════════════════════════════
#
# Description:
#   Script interactif pour gérer le workflow Git complet:
#   feature → dev → staging → main → prod
#
# Usage:
#   ./git-deploy.sh              # Mode interactif
#   ./git-deploy.sh --help       # Afficher l'aide
#
# Workflow:
#   1. Développement: feature branches
#   2. Intégration: dev
#   3. Pré-production: staging
#   4. Release: main
#   5. Production: prod
#
# Auteur: Auto-généré
# Version: 1.0
# Date: 2025-11-25
# ═══════════════════════════════════════════════════════════════════════

set -e  # Arrêter en cas d'erreur

# ═══════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════

# Branches principales (modifiable selon votre workflow)
BRANCH_DEV="dev"
BRANCH_DEV_DEPLOY="develop"
BRANCH_STAGING="staging"
BRANCH_MAIN="main"
BRANCH_PROD="prod"

# Préfixe pour les branches de feature
FEATURE_PREFIX="feature/"

# Couleurs pour l'affichage
COLOR_RESET="\033[0m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

# ═══════════════════════════════════════════════════════════════════════
# FONCTIONS UTILITAIRES
# ═══════════════════════════════════════════════════════════════════════

print_header() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_CYAN}═══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}  $1${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}═══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
}

print_success() {
    echo -e "${COLOR_GREEN}✅ $1${COLOR_RESET}"
}

print_error() {
    echo -e "${COLOR_RED}❌ $1${COLOR_RESET}"
}

print_warning() {
    echo -e "${COLOR_YELLOW}⚠️  $1${COLOR_RESET}"
}

print_info() {
    echo -e "${COLOR_BLUE}ℹ️  $1${COLOR_RESET}"
}

print_step() {
    echo -e "${COLOR_BOLD}▶ $1${COLOR_RESET}"
}

confirm() {
    local message="$1"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -p "$(echo -e "${COLOR_YELLOW}❓ ${message} ${prompt}: ${COLOR_RESET}")" -r
    REPLY=${REPLY:-$default}

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════
# VÉRIFICATIONS PRÉLIMINAIRES
# ═══════════════════════════════════════════════════════════════════════

check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Ce répertoire n'est pas un dépôt Git"
        exit 1
    fi

    # Configurer le comportement de pull si non défini
    ensure_pull_config
}

ensure_pull_config() {
    # Vérifier si pull.rebase est configuré
    local pull_config=$(git config --get pull.rebase 2>/dev/null)

    if [[ -z "$pull_config" ]]; then
        # Configurer pull.rebase = false (merge) par défaut pour ce repo
        git config pull.rebase false
        # Désactiver l'avertissement
        git config advice.skippedCherryPicks false
    fi
}

check_clean_working_tree() {
    if ! git diff-index --quiet HEAD --; then
        print_warning "Vous avez des modifications non commitées"
        git status --short
        echo ""

        if ! confirm "Continuer quand même?" "n"; then
            print_info "Opération annulée"
            exit 0
        fi
    fi
}

check_branch_exists() {
    local branch="$1"
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        return 1
    fi
    return 0
}

check_remote_branch_exists() {
    local branch="$1"
    if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        return 1
    fi
    return 0
}

get_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

# ═══════════════════════════════════════════════════════════════════════
# NOUVELLES FONCTIONNALITÉS AVANCÉES
# ═══════════════════════════════════════════════════════════════════════

undo_commit() {
    print_header "↩️  ANNULER UN COMMIT"

    # Vérifier qu'il y a des commits
    if ! git log --oneline -1 > /dev/null 2>&1; then
        print_error "Aucun commit à annuler"
        return
    fi

    # Afficher les derniers commits
    print_step "Derniers commits:"
    echo ""
    git log --oneline --graph --decorate -10
    echo ""

    echo -e "${COLOR_BOLD}Options d'annulation:${COLOR_RESET}"
    echo "  1. Soft reset - Annuler le commit mais garder les changements (staged)"
    echo "  2. Mixed reset - Annuler le commit et unstage les changements"
    echo "  3. Hard reset - Annuler le commit et SUPPRIMER les changements ⚠️"
    echo "  4. Annuler seulement le dernier commit (commit --amend)"
    echo "  5. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez une option (1-5): ${COLOR_RESET}")" choice

    case $choice in
        1)
            print_warning "⚠️  Soft reset: Le commit sera annulé, les changements resteront staged"
            if confirm "Confirmer?" "n"; then
                if git reset --soft HEAD~1; then
                    print_success "Commit annulé (changements toujours stagés)"
                    echo ""
                    git status --short
                else
                    print_error "Échec de l'annulation"
                fi
            fi
            ;;
        2)
            print_warning "⚠️  Mixed reset: Le commit sera annulé, les changements seront unstaged"
            if confirm "Confirmer?" "n"; then
                if git reset HEAD~1; then
                    print_success "Commit annulé (changements unstaged)"
                    echo ""
                    git status --short
                else
                    print_error "Échec de l'annulation"
                fi
            fi
            ;;
        3)
            print_error "⚠️  ATTENTION: Hard reset SUPPRIMERA définitivement vos changements!"
            print_warning "Cette action est IRRÉVERSIBLE!"
            if confirm "ÊTES-VOUS ABSOLUMENT SÛR?" "n"; then
                if confirm "Dernière confirmation - Supprimer définitivement?" "n"; then
                    if git reset --hard HEAD~1; then
                        print_success "Commit annulé et changements supprimés"
                    else
                        print_error "Échec de l'annulation"
                    fi
                else
                    print_info "Annulé (sage décision)"
                fi
            else
                print_info "Annulé"
            fi
            ;;
        4)
            print_info "Amend: Modifier le dernier commit"
            echo ""
            print_step "Fichiers actuellement stagés:"
            git status --short
            echo ""
            if confirm "Voulez-vous ajouter/modifier des fichiers avant d'amend?" "n"; then
                git_add
            fi
            echo ""
            read -p "Nouveau message de commit (vide = garder l'ancien): " new_message
            if [[ -n "$new_message" ]]; then
                git commit --amend -m "$new_message"
            else
                git commit --amend --no-edit
            fi
            print_success "Dernier commit modifié"
            ;;
        5|*)
            print_info "Annulé"
            ;;
    esac
}

reset_to_commit() {
    print_header "⏮️  REVENIR À UN COMMIT SPÉCIFIQUE"

    # Afficher l'historique
    print_step "Historique des commits (20 derniers):"
    echo ""
    git log --oneline --graph --decorate -20
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Hash du commit (ou nombre de commits en arrière): ${COLOR_RESET}")" target

    if [[ -z "$target" ]]; then
        print_info "Annulé"
        return
    fi

    # Déterminer si c'est un nombre ou un hash
    local commit_ref=""
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        commit_ref="HEAD~${target}"
        print_info "Revenir ${target} commit(s) en arrière"
    else
        commit_ref="$target"
        print_info "Revenir au commit: ${target}"
    fi

    # Vérifier que le commit existe
    if ! git rev-parse --quiet --verify "$commit_ref" > /dev/null; then
        print_error "Commit invalide: ${target}"
        return
    fi

    # Afficher le commit cible
    echo ""
    print_step "Commit cible:"
    git log --oneline -1 "$commit_ref"
    echo ""

    echo -e "${COLOR_BOLD}Type de reset:${COLOR_RESET}"
    echo "  1. Soft - Garder tous les changements (staged)"
    echo "  2. Mixed - Garder les changements (unstaged)"
    echo "  3. Hard - SUPPRIMER tous les changements ⚠️"
    echo "  4. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez (1-4): ${COLOR_RESET}")" reset_type

    case $reset_type in
        1)
            if confirm "Reset SOFT vers $commit_ref?" "n"; then
                git reset --soft "$commit_ref"
                print_success "Reset effectué (changements stagés)"
                git status --short
            fi
            ;;
        2)
            if confirm "Reset MIXED vers $commit_ref?" "n"; then
                git reset "$commit_ref"
                print_success "Reset effectué (changements unstaged)"
                git status --short
            fi
            ;;
        3)
            print_error "⚠️  ATTENTION: Cela supprimera DÉFINITIVEMENT tous les changements!"
            if confirm "ÊTES-VOUS ABSOLUMENT SÛR?" "n"; then
                git reset --hard "$commit_ref"
                print_success "Reset HARD effectué"
            else
                print_info "Annulé (sage décision)"
            fi
            ;;
        4|*)
            print_info "Annulé"
            ;;
    esac
}

untrack_file() {
    print_header "🚫 ANNULER LE SUIVI D'UN FICHIER"

    print_info "Cette fonction retire un fichier du suivi Git (tracked → untracked)"
    print_info "Le fichier restera sur votre disque mais ne sera plus versionné"
    echo ""

    # Afficher les fichiers trackés
    print_step "Fichiers actuellement suivis:"
    echo ""
    git ls-files | head -50
    echo ""
    print_warning "⚠️  Ajoutez le fichier à .gitignore pour éviter de le tracker à nouveau"
    echo ""

    echo -e "${COLOR_BOLD}Options:${COLOR_RESET}"
    echo "  1. Untrack un fichier spécifique"
    echo "  2. Untrack un répertoire"
    echo "  3. Untrack en gardant dans le cache (--cached)"
    echo "  4. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez (1-4): ${COLOR_RESET}")" choice

    case $choice in
        1)
            read -p "Chemin du fichier: " filepath
            if [[ -z "$filepath" ]]; then
                print_error "Chemin vide"
                return
            fi

            if confirm "Retirer '$filepath' du suivi Git (fichier conservé sur disque)?" "y"; then
                if git rm --cached "$filepath"; then
                    print_success "Fichier retiré du suivi"
                    print_info "Ajoutez '$filepath' à .gitignore"
                    if confirm "Ouvrir .gitignore pour édition?" "n"; then
                        echo "$filepath" >> .gitignore
                        print_success "Ajouté à .gitignore"
                    fi
                else
                    print_error "Échec"
                fi
            fi
            ;;
        2)
            read -p "Chemin du répertoire: " dirpath
            if [[ -z "$dirpath" ]]; then
                print_error "Chemin vide"
                return
            fi

            if confirm "Retirer '$dirpath/' du suivi Git (répertoire conservé)?" "y"; then
                if git rm -r --cached "$dirpath"; then
                    print_success "Répertoire retiré du suivi"
                    print_info "Ajoutez '$dirpath/' à .gitignore"
                    if confirm "Ouvrir .gitignore pour édition?" "n"; then
                        echo "$dirpath/" >> .gitignore
                        print_success "Ajouté à .gitignore"
                    fi
                else
                    print_error "Échec"
                fi
            fi
            ;;
        3)
            read -p "Pattern ou fichier: " pattern
            if [[ -z "$pattern" ]]; then
                print_error "Pattern vide"
                return
            fi

            if confirm "Retirer '$pattern' du suivi (--cached)?" "y"; then
                if git rm --cached -r "$pattern"; then
                    print_success "Retiré du suivi"
                else
                    print_error "Échec"
                fi
            fi
            ;;
        4|*)
            print_info "Annulé"
            ;;
    esac
}

show_log() {
    print_header "📜 HISTORIQUE DES COMMITS"

    echo -e "${COLOR_BOLD}Options d'affichage:${COLOR_RESET}"
    echo "  1. Log standard (20 derniers commits)"
    echo "  2. Log détaillé avec diff"
    echo "  3. Log graphique complet"
    echo "  4. Log d'un fichier spécifique"
    echo "  5. Log d'un auteur spécifique"
    echo "  6. Log avec recherche"
    echo "  7. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez (1-7): ${COLOR_RESET}")" choice

    case $choice in
        1)
            git log --oneline --graph --decorate -20 --color=always | cat
            ;;
        2)
            read -p "Nombre de commits (défaut: 5): " num
            num=${num:-5}
            git log -p -"$num" --color=always | cat
            ;;
        3)
            git log --all --graph --decorate --oneline --color=always -30 | cat
            ;;
        4)
            read -p "Chemin du fichier: " filepath
            if [[ -n "$filepath" ]]; then
                git log --oneline --decorate --follow -- "$filepath" | cat
            fi
            ;;
        5)
            read -p "Nom de l'auteur: " author
            if [[ -n "$author" ]]; then
                git log --author="$author" --oneline --graph --decorate -20 --color=always | cat
            fi
            ;;
        6)
            read -p "Mot-clé à rechercher dans les commits: " keyword
            if [[ -n "$keyword" ]]; then
                git log --grep="$keyword" --oneline --graph --decorate --color=always | cat
            fi
            ;;
        7|*)
            print_info "Annulé"
            ;;
    esac
}

stash_changes() {
    print_header "💼 STASH - SAUVEGARDER TEMPORAIREMENT"

    echo -e "${COLOR_BOLD}Options de stash:${COLOR_RESET}"
    echo "  1. Stash tous les changements"
    echo "  2. Stash avec message"
    echo "  3. Stash incluant les fichiers non trackés"
    echo "  4. Lister les stash"
    echo "  5. Appliquer le dernier stash"
    echo "  6. Appliquer un stash spécifique"
    echo "  7. Supprimer un stash"
    echo "  8. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez (1-8): ${COLOR_RESET}")" choice

    case $choice in
        1)
            if git stash; then
                print_success "Changements mis en stash"
                git stash list
            fi
            ;;
        2)
            read -p "Message du stash: " message
            if [[ -n "$message" ]]; then
                if git stash save "$message"; then
                    print_success "Stash créé: $message"
                    git stash list
                fi
            else
                print_error "Message vide"
            fi
            ;;
        3)
            if git stash --include-untracked; then
                print_success "Changements (incluant non trackés) mis en stash"
                git stash list
            fi
            ;;
        4)
            print_step "Liste des stash:"
            git stash list
            ;;
        5)
            if confirm "Appliquer le dernier stash?" "y"; then
                if git stash pop; then
                    print_success "Stash appliqué et supprimé"
                else
                    print_error "Échec (peut-être des conflits)"
                    print_info "Utilisez 'git stash apply' pour garder le stash"
                fi
            fi
            ;;
        6)
            git stash list
            echo ""
            read -p "Numéro du stash (ex: 0 pour stash@{0}): " stash_num
            if [[ "$stash_num" =~ ^[0-9]+$ ]]; then
                if confirm "Appliquer stash@{$stash_num}?" "y"; then
                    if git stash apply "stash@{$stash_num}"; then
                        print_success "Stash appliqué"
                        if confirm "Supprimer ce stash?" "n"; then
                            git stash drop "stash@{$stash_num}"
                            print_success "Stash supprimé"
                        fi
                    fi
                fi
            fi
            ;;
        7)
            git stash list
            echo ""
            read -p "Numéro du stash à supprimer: " stash_num
            if [[ "$stash_num" =~ ^[0-9]+$ ]]; then
                if confirm "Supprimer stash@{$stash_num}?" "n"; then
                    git stash drop "stash@{$stash_num}"
                    print_success "Stash supprimé"
                fi
            fi
            ;;
        8|*)
            print_info "Annulé"
            ;;
    esac
}

discard_changes() {
    print_header "🗑️  ANNULER LES MODIFICATIONS"

    print_warning "⚠️  Cette action annule les modifications NON COMMITÉES"
    echo ""

    # Afficher les fichiers modifiés
    print_step "Fichiers modifiés:"
    git status --short
    echo ""

    echo -e "${COLOR_BOLD}Options:${COLOR_RESET}"
    echo "  1. Annuler TOUTES les modifications (git checkout .)"
    echo "  2. Annuler les modifications d'un fichier spécifique"
    echo "  3. Annuler les modifications et nettoyer les fichiers non trackés"
    echo "  4. Restaurer un fichier depuis un commit spécifique"
    echo "  5. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez (1-5): ${COLOR_RESET}")" choice

    case $choice in
        1)
            print_error "⚠️  ATTENTION: Toutes les modifications non commitées seront perdues!"
            if confirm "CONFIRMER l'annulation de TOUTES les modifications?" "n"; then
                git checkout .
                print_success "Modifications annulées"
                git status
            fi
            ;;
        2)
            read -p "Chemin du fichier: " filepath
            if [[ -n "$filepath" ]]; then
                if confirm "Annuler les modifications de '$filepath'?" "y"; then
                    git checkout -- "$filepath"
                    print_success "Modifications annulées pour $filepath"
                fi
            fi
            ;;
        3)
            print_error "⚠️  ATTENTION: Supprimera modifications ET fichiers non trackés!"
            if confirm "CONFIRMER?" "n"; then
                git checkout .
                git clean -fd
                print_success "Modifications annulées et fichiers non trackés supprimés"
                git status
            fi
            ;;
        4)
            git log --oneline -10
            echo ""
            read -p "Hash du commit: " commit_hash
            read -p "Chemin du fichier: " filepath
            if [[ -n "$commit_hash" ]] && [[ -n "$filepath" ]]; then
                if confirm "Restaurer '$filepath' depuis $commit_hash?" "y"; then
                    git checkout "$commit_hash" -- "$filepath"
                    print_success "Fichier restauré"
                fi
            fi
            ;;
        5|*)
            print_info "Annulé"
            ;;
    esac
}

delete_branch() {
    print_header "🗑️  SUPPRIMER UNE BRANCHE"

    local current_branch=$(get_current_branch)

    # Lister les branches
    print_step "Branches locales:"
    git branch
    echo ""

    read -p "Nom de la branche à supprimer: " branch_name

    if [[ -z "$branch_name" ]]; then
        print_error "Nom de branche vide"
        return
    fi

    if [[ "$branch_name" == "$current_branch" ]]; then
        print_error "Impossible de supprimer la branche actuelle"
        print_info "Changez d'abord de branche avec l'option 7"
        return
    fi

    # Vérifier si la branche existe
    if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
        print_error "La branche '$branch_name' n'existe pas"
        return
    fi

    echo ""
    echo -e "${COLOR_BOLD}Options de suppression:${COLOR_RESET}"
    echo "  1. Suppression normale (-d) - Seulement si mergée"
    echo "  2. Suppression forcée (-D) - Même si non mergée ⚠️"
    echo "  3. Supprimer aussi la branche distante"
    echo "  4. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez (1-4): ${COLOR_RESET}")" choice

    case $choice in
        1)
            if confirm "Supprimer la branche locale '$branch_name'?" "n"; then
                if git branch -d "$branch_name"; then
                    print_success "Branche '$branch_name' supprimée"
                else
                    print_error "Échec (peut-être non mergée?)"
                    print_info "Utilisez l'option 2 pour forcer"
                fi
            fi
            ;;
        2)
            print_warning "⚠️  Suppression forcée - Même si non mergée!"
            if confirm "CONFIRMER la suppression forcée de '$branch_name'?" "n"; then
                if git branch -D "$branch_name"; then
                    print_success "Branche '$branch_name' supprimée (forcé)"
                fi
            fi
            ;;
        3)
            if confirm "Supprimer locale ET distante '$branch_name'?" "n"; then
                # Locale
                git branch -D "$branch_name" 2>/dev/null
                print_success "Branche locale supprimée"

                # Distante
                if check_remote_branch_exists "$branch_name"; then
                    if git push origin --delete "$branch_name"; then
                        print_success "Branche distante supprimée"
                    fi
                else
                    print_info "Pas de branche distante à supprimer"
                fi
            fi
            ;;
        4|*)
            print_info "Annulé"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════
# FONCTIONS PRINCIPALES
# ═══════════════════════════════════════════════════════════════════════

show_status() {
    print_header "📊 STATUS GIT"

    local current_branch=$(get_current_branch)
    print_info "Branche actuelle: ${COLOR_BOLD}${current_branch}${COLOR_RESET}"
    echo ""

    print_step "État du dépôt:"
    git status --short
    echo ""

    print_step "Derniers commits:"
    git log --oneline --graph --decorate -10
    echo ""

    print_step "Branches locales:"
    git branch -vv
    echo ""

    print_step "Branches distantes:"
    git branch -r
    echo ""
}

create_feature_branch() {
    print_header "🌟 CRÉER UNE NOUVELLE FEATURE BRANCH"

    # Vérifier qu'on est sur dev
    local current_branch=$(get_current_branch)
    if [[ "$current_branch" != "$BRANCH_DEV" ]]; then
        print_warning "Vous n'êtes pas sur la branche ${BRANCH_DEV}"
        if confirm "Basculer sur ${BRANCH_DEV}?" "y"; then
            git checkout "$BRANCH_DEV"
        else
            print_info "Annulé"
            return
        fi
    fi

    # Pull la dernière version
    print_step "Mise à jour de ${BRANCH_DEV}..."
    git pull origin "$BRANCH_DEV"

    # Demander le nom de la feature
    echo ""
    read -p "$(echo -e "${COLOR_CYAN}Nom de la feature (ex: CICBI-06-gestion-api-v2): ${COLOR_RESET}")" feature_name

    if [[ -z "$feature_name" ]]; then
        print_error "Nom de feature requis"
        return
    fi

    local branch_name="${FEATURE_PREFIX}${feature_name}"

    # Vérifier si la branche existe déjà
    if check_branch_exists "$branch_name"; then
        print_error "La branche ${branch_name} existe déjà"
        return
    fi

    # Créer la branche
    print_step "Création de la branche ${branch_name}..."
    git checkout -b "$branch_name"

    print_success "Branche ${branch_name} créée et activée"
    print_info "Vous pouvez maintenant commencer à développer"
    print_info "Pour pousser: git push -u origin ${branch_name}"
}

merge_feature_to_dev() {
    print_header "🔀 MERGER FEATURE → DEV"

    local current_branch=$(get_current_branch)

    # Vérifier qu'on est sur une feature branch
    if [[ ! "$current_branch" =~ ^${FEATURE_PREFIX} ]]; then
        print_error "Vous devez être sur une feature branch"
        return
    fi

    print_info "Feature branch: ${current_branch}"
    echo ""

    # Variable pour savoir si on a rebasé
    local did_rebase=false

    # Rebase sur dev
    print_step "Synchronisation avec ${BRANCH_DEV}..."
    git fetch origin

    if confirm "Rebaser ${current_branch} sur ${BRANCH_DEV}?" "y"; then
        git rebase "origin/${BRANCH_DEV}" || {
            print_error "Échec du rebase. Résolvez les conflits et exécutez 'git rebase --continue'"
            return
        }
        did_rebase=true
    fi

    # Basculer sur dev
    print_step "Basculement sur ${BRANCH_DEV}..."
    git checkout "$BRANCH_DEV"
    git pull origin "$BRANCH_DEV"

    # Merger
    print_step "Merge de ${current_branch} dans ${BRANCH_DEV}..."
    if git merge --no-ff "$current_branch" -m "Merge ${current_branch} into ${BRANCH_DEV}"; then
        print_success "Merge réussi"

        # Pousser
        if confirm "Pousser ${BRANCH_DEV} vers origin?" "y"; then
            git push origin "$BRANCH_DEV"
            print_success "Changements poussés sur origin/${BRANCH_DEV}"
        fi

        # Supprimer la feature branch
        local branch_deleted=false
        if confirm "Supprimer la branche locale ${current_branch}?" "n"; then
            git branch -d "$current_branch"
            print_success "Branche locale supprimée"
            branch_deleted=true

            if confirm "Supprimer aussi la branche distante?" "n"; then
                git push origin --delete "${current_branch}"
                print_success "Branche distante supprimée"
            fi
        fi

        # Demander où aller après le merge
        echo ""
        if [[ "$branch_deleted" == true ]]; then
            # Si la branche source est supprimée, rester sur dev ou aller ailleurs
            print_info "La branche ${current_branch} a été supprimée"
            print_info "Vous êtes maintenant sur ${BRANCH_DEV}"
            echo ""
            if confirm "Voulez-vous basculer sur une autre branche?" "n"; then
                switch_branch
            fi
        else
            # Si la branche source existe encore, proposer d'y retourner
            local choice=$(ask_branch_switch "$current_branch" "$BRANCH_DEV")

            # Si on retourne sur la feature branch et qu'on a rebasé
            if [[ "$choice" == "1" ]] && [[ "$did_rebase" == true ]]; then
                echo ""
                print_warning "⚠️  Votre branche a été rebasée - l'historique local a changé"

                # Vérifier si la branche existe sur origin
                if check_remote_branch_exists "$current_branch"; then
                    print_warning "La branche locale et origin/${current_branch} ont divergé"
                    echo ""
                    print_info "Options disponibles:"
                    echo "  1. Force push (écraser origin avec votre version rebasée)"
                    echo "  2. Reset (abandonner le rebase et revenir à origin)"
                    echo "  3. Ne rien faire (gérer manuellement plus tard)"
                    echo ""

                    read -p "Votre choix [1-3]: " sync_choice

                    case "$sync_choice" in
                        1)
                            print_warning "⚠️  Vous allez réécrire l'historique de origin/${current_branch}"
                            if confirm "Êtes-vous sûr de vouloir force push?" "n"; then
                                git push --force-with-lease origin "$current_branch"
                                print_success "Branche synchronisée avec origin (force push)"
                            else
                                print_info "Force push annulé"
                            fi
                            ;;
                        2)
                            print_step "Reset de ${current_branch} vers origin/${current_branch}..."
                            git reset --hard "origin/${current_branch}"
                            print_success "Branche réinitialisée depuis origin"
                            ;;
                        3|*)
                            print_info "Aucune action - vous pourrez synchroniser plus tard"
                            print_info "Utilisez: git push --force-with-lease origin ${current_branch}"
                            ;;
                    esac
                else
                    print_info "La branche ${current_branch} n'existe pas sur origin"
                    if confirm "Pousser ${current_branch} vers origin?" "y"; then
                        git push -u origin "$current_branch"
                        print_success "Branche poussée vers origin"
                    fi
                fi
            fi
        fi
    else
        print_error "Échec du merge. Résolvez les conflits manuellement"
    fi
}

promote_dev_to_staging() {
    print_header "⬆️  PROMOUVOIR DEV → STAGING"

    check_clean_working_tree

    print_step "Récupération des dernières modifications..."
    git fetch origin

    # Vérifier si la branche staging existe localement
    if ! check_branch_exists "$BRANCH_STAGING"; then
        print_warning "La branche locale ${BRANCH_STAGING} n'existe pas"

        # Vérifier si elle existe sur le remote
        if check_remote_branch_exists "$BRANCH_STAGING"; then
            print_step "Création de la branche locale ${BRANCH_STAGING} depuis origin/${BRANCH_STAGING}..."
            git checkout -b "$BRANCH_STAGING" "origin/$BRANCH_STAGING"
            print_success "Branche ${BRANCH_STAGING} créée depuis origin"
        else
            print_warning "La branche ${BRANCH_STAGING} n'existe ni localement ni sur origin"
            if confirm "Créer la branche ${BRANCH_STAGING} depuis ${BRANCH_DEV}?" "y"; then
                print_step "Création de ${BRANCH_STAGING} depuis ${BRANCH_DEV}..."
                git checkout -b "$BRANCH_STAGING" "$BRANCH_DEV"
                print_success "Branche ${BRANCH_STAGING} créée"

                if confirm "Pousser ${BRANCH_STAGING} vers origin?" "y"; then
                    git push -u origin "$BRANCH_STAGING"
                    print_success "${BRANCH_STAGING} poussée sur origin"
                fi

                print_info "${BRANCH_STAGING} est maintenant synchronisée avec ${BRANCH_DEV}"
                return
            else
                print_info "Annulé"
                return
            fi
        fi
    fi

    # Vérifier les différences
    print_info "Différences entre ${BRANCH_STAGING} et ${BRANCH_DEV}:"
    if git log "${BRANCH_STAGING}..${BRANCH_DEV}" --oneline 2>/dev/null | head -20; then
        echo ""
    else
        print_warning "Impossible de comparer les branches (peut-être déjà synchronisées)"
        echo ""
    fi

    if ! confirm "Continuer la promotion de ${BRANCH_DEV} vers ${BRANCH_STAGING}?" "y"; then
        print_info "Annulé"
        return
    fi

    # Basculer sur staging
    print_step "Basculement sur ${BRANCH_STAGING}..."
    git checkout "$BRANCH_STAGING"

    # Pull seulement si la branche existe sur origin
    if check_remote_branch_exists "$BRANCH_STAGING"; then
        git pull origin "$BRANCH_STAGING"
    fi

    # Merger dev
    print_step "Merge de ${BRANCH_DEV} dans ${BRANCH_STAGING}..."
    if git merge --no-ff "$BRANCH_DEV" -m "Merge ${BRANCH_DEV} into ${BRANCH_STAGING}"; then
        print_success "Merge réussi"

        # Pousser
        if confirm "Pousser ${BRANCH_STAGING} vers origin?" "y"; then
            git push origin "$BRANCH_STAGING"
            print_success "Changements poussés sur origin/${BRANCH_STAGING}"
            print_info "Tests QA peuvent commencer sur staging"
        fi

        # Demander où aller après le merge
        ask_branch_switch "$BRANCH_DEV" "$BRANCH_STAGING"
    else
        print_error "Échec du merge. Résolvez les conflits manuellement"
    fi
}

promote_staging_to_main() {
    print_header "🎯 PROMOUVOIR STAGING → MAIN (Release)"

    check_clean_working_tree

    print_step "Récupération des dernières modifications..."
    git fetch origin

    # Vérifier si la branche main existe localement
    if ! check_branch_exists "$BRANCH_MAIN"; then
        print_warning "La branche locale ${BRANCH_MAIN} n'existe pas"

        # Vérifier si elle existe sur le remote
        if check_remote_branch_exists "$BRANCH_MAIN"; then
            print_step "Création de la branche locale ${BRANCH_MAIN} depuis origin/${BRANCH_MAIN}..."
            git checkout -b "$BRANCH_MAIN" "origin/$BRANCH_MAIN"
            print_success "Branche ${BRANCH_MAIN} créée depuis origin"
        else
            print_error "La branche ${BRANCH_MAIN} n'existe ni localement ni sur origin"
            print_info "Vous devez d'abord créer la branche ${BRANCH_MAIN}"
            return 1
        fi
    fi

    # Vérifier les différences
    print_info "Différences entre ${BRANCH_MAIN} et ${BRANCH_STAGING}:"
    if git log "${BRANCH_MAIN}..${BRANCH_STAGING}" --oneline 2>/dev/null | head -20; then
        echo ""
    else
        print_warning "Impossible de comparer les branches"
        echo ""
    fi

    if ! confirm "Continuer la promotion de ${BRANCH_STAGING} vers ${BRANCH_MAIN}?" "y"; then
        print_info "Annulé"
        return
    fi

    # Basculer sur main
    print_step "Basculement sur ${BRANCH_MAIN}..."
    git checkout "$BRANCH_MAIN"
    git pull origin "$BRANCH_MAIN"

    # Merger staging
    print_step "Merge de ${BRANCH_STAGING} dans ${BRANCH_MAIN}..."
    if git merge --no-ff "$BRANCH_STAGING" -m "Merge ${BRANCH_STAGING} into ${BRANCH_MAIN}"; then
        print_success "Merge réussi"

        # Demander si on veut créer un tag
        if confirm "Créer un tag de version?" "y"; then
            create_version_tag
        fi

        # Pousser
        if confirm "Pousser ${BRANCH_MAIN} vers origin?" "y"; then
            git push origin "$BRANCH_MAIN"
            print_success "Changements poussés sur origin/${BRANCH_MAIN}"
            print_info "Release prête pour déploiement en production"
        fi

        # Demander où aller après le merge
        ask_branch_switch "$BRANCH_STAGING" "$BRANCH_MAIN"
    else
        print_error "Échec du merge. Résolvez les conflits manuellement"
    fi
}

deploy_main_to_prod() {
    print_header "🚀 DÉPLOYER MAIN → PROD"

    check_clean_working_tree

    print_warning "⚠️  ATTENTION: Vous allez déployer en PRODUCTION!"
    print_warning "⚠️  Cette opération doit être effectuée avec précaution"
    echo ""

    print_step "Récupération des dernières modifications..."
    git fetch origin

    # Vérifier si la branche prod existe localement
    if ! check_branch_exists "$BRANCH_PROD"; then
        print_warning "La branche locale ${BRANCH_PROD} n'existe pas"

        # Vérifier si elle existe sur le remote
        if check_remote_branch_exists "$BRANCH_PROD"; then
            print_step "Création de la branche locale ${BRANCH_PROD} depuis origin/${BRANCH_PROD}..."
            git checkout -b "$BRANCH_PROD" "origin/$BRANCH_PROD"
            print_success "Branche ${BRANCH_PROD} créée depuis origin"
        else
            print_warning "La branche ${BRANCH_PROD} n'existe ni localement ni sur origin"
            if confirm "Créer la branche ${BRANCH_PROD} depuis ${BRANCH_MAIN}?" "y"; then
                print_step "Création de ${BRANCH_PROD} depuis ${BRANCH_MAIN}..."
                git checkout -b "$BRANCH_PROD" "$BRANCH_MAIN"
                print_success "Branche ${BRANCH_PROD} créée"

                if confirm "Pousser ${BRANCH_PROD} vers origin?" "y"; then
                    git push -u origin "$BRANCH_PROD"
                    print_success "${BRANCH_PROD} poussée sur origin"
                fi

                print_success "✅ Branche ${BRANCH_PROD} initialisée avec ${BRANCH_MAIN}"
                return
            else
                print_info "Annulé"
                return
            fi
        fi
    fi

    # Vérifier les différences
    print_info "Différences entre ${BRANCH_PROD} et ${BRANCH_MAIN}:"
    if git log "${BRANCH_PROD}..${BRANCH_MAIN}" --oneline 2>/dev/null | head -20; then
        echo ""
    else
        print_warning "Impossible de comparer les branches"
        echo ""
    fi

    if ! confirm "ÊTES-VOUS SÛR de déployer ${BRANCH_MAIN} vers ${BRANCH_PROD}?" "n"; then
        print_info "Annulé (sage décision!)"
        return
    fi

    # Basculer sur prod
    print_step "Basculement sur ${BRANCH_PROD}..."
    git checkout "$BRANCH_PROD"

    # Pull seulement si la branche existe sur origin
    if check_remote_branch_exists "$BRANCH_PROD"; then
        git pull origin "$BRANCH_PROD"
    fi

    # Merger main (fast-forward only pour prod)
    print_step "Merge de ${BRANCH_MAIN} dans ${BRANCH_PROD} (fast-forward only)..."
    if git merge --ff-only "$BRANCH_MAIN"; then
        print_success "Merge réussi"

        # Pousser
        if confirm "Pousser ${BRANCH_PROD} vers origin?" "y"; then
            git push origin "$BRANCH_PROD"
            print_success "✅ DÉPLOIEMENT EN PRODUCTION EFFECTUÉ"
            print_info "Surveillez les logs de production!"
        fi

        # Demander où aller après le merge
        ask_branch_switch "$BRANCH_MAIN" "$BRANCH_PROD"
    else
        print_error "Impossible de faire un fast-forward merge"
        print_error "Vérifiez que ${BRANCH_PROD} n'a pas divergé de ${BRANCH_MAIN}"
    fi
}

get_latest_tag() {
    # Récupère le dernier tag de version (format vX.Y.Z)
    git tag -l "v*.*.*" | sort -V | tail -1
}

parse_version() {
    # Parse une version au format vX.Y.Z et retourne MAJOR MINOR PATCH
    local version="$1"

    # Supprimer le 'v' au début
    version="${version#v}"

    # Extraire major, minor, patch
    local major=$(echo "$version" | cut -d. -f1)
    local minor=$(echo "$version" | cut -d. -f2)
    local patch=$(echo "$version" | cut -d. -f3)

    echo "$major $minor $patch"
}

increment_version() {
    local current_version="$1"
    local increment_type="$2"

    # Parser la version actuelle
    read -r major minor patch <<< "$(parse_version "$current_version")"

    case "$increment_type" in
        patch)
            # v1.2.3 → v1.2.4
            ((patch++))
            ;;
        minor)
            # v1.2.3 → v1.3.0
            ((minor++))
            patch=0
            ;;
        major)
            # v1.2.3 → v2.0.0
            ((major++))
            minor=0
            patch=0
            ;;
        *)
            echo ""
            return 1
            ;;
    esac

    echo "v${major}.${minor}.${patch}"
}

create_version_tag() {
    print_header "🏷️  CRÉER UN TAG DE VERSION (Versioning Sémantique)"

    # Récupérer le dernier tag
    local latest_tag=$(get_latest_tag)

    if [[ -z "$latest_tag" ]]; then
        print_info "Aucun tag existant détecté"
        print_info "Création de la première version..."
        echo ""
        read -p "$(echo -e "${COLOR_CYAN}Version initiale (défaut: v1.0.0): ${COLOR_RESET}")" initial_version
        initial_version=${initial_version:-v1.0.0}

        # Ajouter 'v' si absent
        if [[ ! "$initial_version" =~ ^v ]]; then
            initial_version="v${initial_version}"
        fi

        new_version="$initial_version"
    else
        print_info "Dernière version: ${COLOR_BOLD}${latest_tag}${COLOR_RESET}"
        echo ""

        # Calculer les versions possibles
        local patch_version=$(increment_version "$latest_tag" "patch")
        local minor_version=$(increment_version "$latest_tag" "minor")
        local major_version=$(increment_version "$latest_tag" "major")

        echo -e "${COLOR_BOLD}Type de version (Versioning Sémantique):${COLOR_RESET}"
        echo ""
        echo -e "  ${COLOR_GREEN}1. PATCH${COLOR_RESET} - ${latest_tag} → ${COLOR_BOLD}${patch_version}${COLOR_RESET}"
        echo -e "     ${COLOR_CYAN}└─ Correctifs de bugs, petites corrections${COLOR_RESET}"
        echo ""
        echo -e "  ${COLOR_YELLOW}2. MINOR${COLOR_RESET} - ${latest_tag} → ${COLOR_BOLD}${minor_version}${COLOR_RESET}"
        echo -e "     ${COLOR_CYAN}└─ Nouvelles fonctionnalités (rétrocompatibles)${COLOR_RESET}"
        echo ""
        echo -e "  ${COLOR_RED}3. MAJOR${COLOR_RESET} - ${latest_tag} → ${COLOR_BOLD}${major_version}${COLOR_RESET}"
        echo -e "     ${COLOR_CYAN}└─ Changements incompatibles (breaking changes)${COLOR_RESET}"
        echo ""
        echo "  4. Personnalisée - Entrer manuellement"
        echo "  5. Annuler"
        echo ""

        read -p "$(echo -e "${COLOR_CYAN}Choisissez le type de version (1-5): ${COLOR_RESET}")" version_choice

        case $version_choice in
            1)
                new_version="$patch_version"
                version_type="PATCH (correctif)"
                ;;
            2)
                new_version="$minor_version"
                version_type="MINOR (nouvelle fonctionnalité)"
                ;;
            3)
                new_version="$major_version"
                version_type="MAJOR (breaking change)"
                ;;
            4)
                echo ""
                read -p "$(echo -e "${COLOR_CYAN}Numéro de version personnalisé (ex: v1.2.3): ${COLOR_RESET}")" custom_version

                if [[ -z "$custom_version" ]]; then
                    print_warning "Aucun tag créé"
                    return
                fi

                # Ajouter 'v' si absent
                if [[ ! "$custom_version" =~ ^v ]]; then
                    custom_version="v${custom_version}"
                fi

                new_version="$custom_version"
                version_type="PERSONNALISÉE"
                ;;
            5)
                print_info "Création de tag annulée"
                return
                ;;
            *)
                print_error "Option invalide"
                return
                ;;
        esac
    fi

    # Vérifier que le tag n'existe pas déjà
    if git tag -l | grep -q "^${new_version}$"; then
        print_error "Le tag ${new_version} existe déjà"
        return
    fi

    # Résumé
    echo ""
    print_step "Résumé de la nouvelle version:"
    echo -e "  Version: ${COLOR_BOLD}${new_version}${COLOR_RESET}"
    if [[ -n "${version_type:-}" ]]; then
        echo -e "  Type: ${version_type}"
    fi
    echo ""

    # Message du tag
    read -p "$(echo -e "${COLOR_CYAN}Message du tag (optionnel): ${COLOR_RESET}")" tag_message

    if [[ -z "$tag_message" ]]; then
        if [[ -n "${version_type:-}" ]]; then
            tag_message="Release ${new_version} - ${version_type}"
        else
            tag_message="Release ${new_version}"
        fi
    fi

    # Confirmation finale
    if ! confirm "Créer le tag ${new_version}?" "y"; then
        print_info "Création de tag annulée"
        return
    fi

    # Créer le tag
    print_step "Création du tag..."
    git tag -a "$new_version" -m "$tag_message"
    print_success "Tag ${new_version} créé localement"

    # Pousser le tag
    if confirm "Pousser le tag vers origin?" "y"; then
        git push origin "$new_version"
        print_success "Tag ${new_version} poussé sur origin"
        print_info "Le tag est maintenant disponible pour le déploiement"
    else
        print_warning "Tag créé localement uniquement"
        print_info "Pour le pousser plus tard: git push origin ${new_version}"
    fi
}

list_tags() {
    print_header "🏷️  TAGS DE VERSION"

    if git tag -l | grep -q .; then
        print_step "Tags existants:"
        git tag -l -n1 | sort -V -r | head -20
    else
        print_info "Aucun tag trouvé"
    fi
}

sync_branch() {
    print_header "🔄 SYNCHRONISER UNE BRANCHE"

    local current_branch=$(get_current_branch)
    print_info "Branche actuelle: ${current_branch}"

    if confirm "Synchroniser ${current_branch} avec origin?" "y"; then
        print_step "Récupération des modifications..."
        git fetch origin

        print_step "Pull avec rebase..."
        if git pull --rebase origin "$current_branch"; then
            print_success "Branche synchronisée"
        else
            print_error "Échec de la synchronisation"
            print_info "Résolvez les conflits et exécutez 'git rebase --continue'"
        fi
    fi
}

switch_branch() {
    print_header "🔀 CHANGER DE BRANCHE"

    check_clean_working_tree

    local current_branch=$(get_current_branch)
    print_info "Branche actuelle: ${COLOR_BOLD}${current_branch}${COLOR_RESET}"
    echo ""

    # Récupérer les dernières infos
    print_step "Récupération des branches distantes..."
    git fetch origin --prune
    echo ""

    # Récupérer toutes les branches
    local -a local_branches=()
    local -a remote_only_branches=()
    local -a all_branches=()
    local index=1

    # Branches locales
    while IFS= read -r branch; do
        branch=$(echo "$branch" | sed 's/^[\* ]*//g' | awk '{print $1}')
        if [[ -n "$branch" ]]; then
            local_branches+=("$branch")
            all_branches+=("local:$branch")
        fi
    done < <(git branch --format='%(refname:short)')

    # Branches distantes seulement (pas déjà en local)
    while IFS= read -r remote_branch; do
        remote_branch=$(echo "$remote_branch" | sed 's|^origin/||' | awk '{print $1}')
        if [[ -n "$remote_branch" ]] && [[ "$remote_branch" != "HEAD" ]]; then
            # Vérifier si la branche n'existe pas déjà en local
            local exists_locally=false
            for local_branch in "${local_branches[@]}"; do
                if [[ "$local_branch" == "$remote_branch" ]]; then
                    exists_locally=true
                    break
                fi
            done

            if [[ "$exists_locally" == "false" ]]; then
                remote_only_branches+=("$remote_branch")
                all_branches+=("remote:$remote_branch")
            fi
        fi
    done < <(git branch -r --format='%(refname:short)')

    # Afficher les branches disponibles
    print_step "Branches disponibles:"
    echo ""

    echo -e "${COLOR_BOLD}${COLOR_CYAN}BRANCHES LOCALES:${COLOR_RESET}"
    for branch in "${local_branches[@]}"; do
        if [[ "$branch" == "$current_branch" ]]; then
            echo -e "${COLOR_GREEN}  ${index}. ${branch} ${COLOR_BOLD}(actuelle)${COLOR_RESET}"
        else
            echo "  ${index}. ${branch}"
        fi
        ((index++))
    done

    if [[ ${#remote_only_branches[@]} -gt 0 ]]; then
        echo ""
        echo -e "${COLOR_BOLD}${COLOR_CYAN}BRANCHES DISTANTES (non trackées localement):${COLOR_RESET}"
        for branch in "${remote_only_branches[@]}"; do
            echo "  ${index}. origin/${branch} ${COLOR_YELLOW}(sera trackée localement)${COLOR_RESET}"
            ((index++))
        done
    fi

    echo ""
    echo "  0. Annuler"
    echo ""

    # Demander le choix
    local choice
    read -p "$(echo -e "${COLOR_CYAN}Choisissez une branche (0-$((index-1))): ${COLOR_RESET}")" choice

    # Valider le choix
    if [[ -z "$choice" ]] || [[ "$choice" == "0" ]]; then
        print_info "Annulé"
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -ge "$index" ]]; then
        print_error "Choix invalide"
        return
    fi

    # Récupérer la branche sélectionnée
    local selected_branch="${all_branches[$((choice-1))]}"
    local branch_type="${selected_branch%%:*}"
    local branch_name="${selected_branch#*:}"

    # Vérifier si c'est la branche actuelle
    if [[ "$branch_name" == "$current_branch" ]]; then
        print_warning "Vous êtes déjà sur la branche ${branch_name}"
        return
    fi

    # Basculer vers la branche
    print_step "Changement vers ${branch_name}..."

    if [[ "$branch_type" == "local" ]]; then
        # Branche locale
        if git checkout "$branch_name"; then
            print_success "Basculé sur ${branch_name}"

            # Proposer de synchroniser
            if check_remote_branch_exists "$branch_name"; then
                if confirm "Synchroniser avec origin/${branch_name}?" "y"; then
                    git pull origin "$branch_name"
                    print_success "Branche synchronisée"
                fi
            fi
        else
            print_error "Échec du changement de branche"
        fi
    else
        # Branche distante - créer locale et tracker
        if git checkout -b "$branch_name" "origin/$branch_name"; then
            print_success "Branche ${branch_name} créée et trackée depuis origin"
        else
            print_error "Échec de la création de la branche locale"
        fi
    fi

    echo ""
    print_info "Branche actuelle: ${COLOR_BOLD}$(get_current_branch)${COLOR_RESET}"
}

git_pull() {
    print_header "⬇️  PULL - RÉCUPÉRER LES CHANGEMENTS"

    local current_branch=$(get_current_branch)
    print_info "Branche actuelle: ${current_branch}"
    echo ""

    # Afficher l'état actuel
    print_step "Vérification de l'état du dépôt..."
    git fetch origin

    # Vérifier si la branche distante existe
    if ! check_remote_branch_exists "$current_branch"; then
        print_warning "Aucune branche distante 'origin/${current_branch}' trouvée"
        print_info "Utilisez 'git push -u origin ${current_branch}' pour créer la branche distante"
        return
    fi

    # Vérifier si en retard
    local behind=$(git rev-list --count "${current_branch}..origin/${current_branch}" 2>/dev/null || echo "0")
    local ahead=$(git rev-list --count "origin/${current_branch}..${current_branch}" 2>/dev/null || echo "0")

    if [[ "$behind" -eq 0 ]] && [[ "$ahead" -eq 0 ]]; then
        print_success "La branche est déjà à jour"
        return
    fi

    if [[ "$ahead" -gt 0 ]]; then
        print_info "Vous avez ${ahead} commit(s) en avance sur origin"
    fi
    if [[ "$behind" -gt 0 ]]; then
        print_info "Vous avez ${behind} commit(s) en retard sur origin"
    fi

    echo ""
    print_step "Changements à récupérer:"
    git log --oneline "${current_branch}..origin/${current_branch}"
    echo ""

    # Demander la méthode de pull
    echo -e "${COLOR_BOLD}Méthode de pull:${COLOR_RESET}"
    echo "  1. Pull avec merge (git pull)"
    echo "  2. Pull avec rebase (git pull --rebase)"
    echo "  3. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez une option (1-3): ${COLOR_RESET}")" pull_choice

    case $pull_choice in
        1)
            print_step "Pull avec merge..."
            if git pull origin "$current_branch"; then
                print_success "Pull réussi"
            else
                print_error "Échec du pull"
                print_info "Résolvez les conflits et commitez"
            fi
            ;;
        2)
            print_step "Pull avec rebase..."
            if git pull --rebase origin "$current_branch"; then
                print_success "Pull avec rebase réussi"
            else
                print_error "Échec du pull"
                print_info "Résolvez les conflits et exécutez 'git rebase --continue'"
            fi
            ;;
        3)
            print_info "Opération annulée"
            ;;
        *)
            print_error "Option invalide"
            ;;
    esac
}

git_add() {
    print_header "➕ ADD - AJOUTER DES FICHIERS"

    # Afficher l'état
    print_step "Fichiers modifiés:"
    git status --short
    echo ""

    if ! git diff-index --quiet HEAD -- 2>/dev/null && git diff-files --quiet 2>/dev/null; then
        print_success "Aucun fichier à ajouter (tout est déjà stagé)"
        return
    fi

    echo -e "${COLOR_BOLD}Options d'ajout:${COLOR_RESET}"
    echo "  1. Ajouter tous les fichiers (git add .)"
    echo "  2. Ajouter tous les fichiers modifiés et supprimés (git add -u)"
    echo "  3. Ajouter des fichiers spécifiques"
    echo "  4. Ajouter de manière interactive (git add -p)"
    echo "  5. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez une option (1-5): ${COLOR_RESET}")" add_choice

    case $add_choice in
        1)
            print_step "Ajout de tous les fichiers..."
            git add .
            print_success "Tous les fichiers ont été ajoutés"
            echo ""
            print_step "Fichiers stagés:"
            git status --short
            ;;
        2)
            print_step "Ajout des fichiers modifiés et supprimés..."
            git add -u
            print_success "Fichiers modifiés et supprimés ajoutés"
            echo ""
            print_step "Fichiers stagés:"
            git status --short
            ;;
        3)
            echo ""
            read -p "$(echo -e "${COLOR_CYAN}Chemin(s) des fichiers (séparés par des espaces): ${COLOR_RESET}")" files
            if [[ -n "$files" ]]; then
                print_step "Ajout des fichiers spécifiés..."
                if git add $files; then
                    print_success "Fichiers ajoutés"
                    echo ""
                    print_step "Fichiers stagés:"
                    git status --short
                else
                    print_error "Erreur lors de l'ajout des fichiers"
                fi
            else
                print_warning "Aucun fichier spécifié"
            fi
            ;;
        4)
            print_step "Mode interactif..."
            git add -p
            ;;
        5)
            print_info "Opération annulée"
            ;;
        *)
            print_error "Option invalide"
            ;;
    esac
}

git_commit() {
    print_header "💾 COMMIT - SAUVEGARDER LES CHANGEMENTS"

    # Vérifier qu'il y a des fichiers stagés
    if git diff-index --quiet --cached HEAD -- 2>/dev/null; then
        print_warning "Aucun fichier stagé à commiter"
        echo ""
        if confirm "Voulez-vous d'abord ajouter des fichiers?" "y"; then
            git_add
            echo ""
            # Revérifier après l'ajout
            if git diff-index --quiet --cached HEAD -- 2>/dev/null; then
                print_info "Toujours aucun fichier à commiter"
                return
            fi
        else
            return
        fi
    fi

    # Afficher les fichiers qui seront commités
    print_step "Fichiers qui seront commités:"
    git diff --cached --stat
    echo ""

    # Demander le message de commit
    read -p "$(echo -e "${COLOR_CYAN}Message du commit: ${COLOR_RESET}")" commit_message

    if [[ -z "$commit_message" ]]; then
        print_error "Message de commit requis"
        return
    fi

    # Demander si on veut un commit détaillé
    if confirm "Ajouter une description détaillée?" "n"; then
        echo ""
        read -p "$(echo -e "${COLOR_CYAN}Description (ligne 2+): ${COLOR_RESET}")" commit_description
        if [[ -n "$commit_description" ]]; then
            commit_message="${commit_message}

${commit_description}"
        fi
    fi

    # Créer le commit
    print_step "Création du commit..."
    if git commit -m "$commit_message"; then
        print_success "Commit créé avec succès"
        echo ""
        print_step "Dernier commit:"
        git log -1 --stat
    else
        print_error "Échec du commit"
    fi
}

git_push() {
    print_header "⬆️  PUSH - ENVOYER LES CHANGEMENTS"

    local current_branch=$(get_current_branch)
    print_info "Branche actuelle: ${current_branch}"
    echo ""

    # Récupérer l'état
    git fetch origin 2>/dev/null

    # Vérifier s'il y a des commits à pousser
    if check_remote_branch_exists "$current_branch"; then
        local ahead=$(git rev-list --count "origin/${current_branch}..${current_branch}" 2>/dev/null || echo "0")
        local behind=$(git rev-list --count "${current_branch}..origin/${current_branch}" 2>/dev/null || echo "0")

        if [[ "$ahead" -eq 0 ]]; then
            print_success "Aucun commit à pousser (déjà à jour)"
            return
        fi

        print_info "Vous avez ${ahead} commit(s) à pousser"

        if [[ "$behind" -gt 0 ]]; then
            print_warning "Attention: vous avez ${behind} commit(s) en retard sur origin"
            print_warning "Vous devriez d'abord faire un pull"
            if ! confirm "Continuer quand même?" "n"; then
                print_info "Opération annulée"
                return
            fi
        fi

        echo ""
        print_step "Commits qui seront poussés:"
        git log --oneline "origin/${current_branch}..${current_branch}"
        echo ""
    else
        print_warning "Aucune branche distante 'origin/${current_branch}'"
        print_info "Ce push créera la branche distante"
        echo ""
        print_step "Commits qui seront poussés:"
        git log --oneline "${current_branch}"
        echo ""
    fi

    # Options de push
    echo -e "${COLOR_BOLD}Options de push:${COLOR_RESET}"
    echo "  1. Push normal (git push)"
    echo "  2. Push et définir upstream (git push -u origin ${current_branch})"
    echo "  3. Force push (⚠️  DANGEREUX)"
    echo "  4. Annuler"
    echo ""

    read -p "$(echo -e "${COLOR_CYAN}Choisissez une option (1-4): ${COLOR_RESET}")" push_choice

    case $push_choice in
        1)
            print_step "Push en cours..."
            if git push origin "$current_branch"; then
                print_success "Push réussi"
            else
                print_error "Échec du push"
                print_info "Essayez 'git pull' d'abord ou utilisez l'option 2 pour -u"
            fi
            ;;
        2)
            print_step "Push avec upstream en cours..."
            if git push -u origin "$current_branch"; then
                print_success "Push réussi et upstream défini"
            else
                print_error "Échec du push"
            fi
            ;;
        3)
            print_warning "⚠️  ATTENTION: Le force push peut écraser l'historique distant!"
            if confirm "ÊTES-VOUS ABSOLUMENT SÛR?" "n"; then
                print_step "Force push en cours..."
                if git push --force-with-lease origin "$current_branch"; then
                    print_success "Force push réussi"
                    print_warning "Avertissez vos collaborateurs!"
                else
                    print_error "Échec du force push"
                fi
            else
                print_info "Force push annulé (sage décision!)"
            fi
            ;;
        4)
            print_info "Opération annulée"
            ;;
        *)
            print_error "Option invalide"
            ;;
    esac
}

ask_branch_switch() {
    local source_branch="$1"
    local target_branch="$2"
    local current_branch=$(get_current_branch)

    echo "" >&2
    print_header "🔀 CHOIX DE BRANCHE" >&2

    print_info "Branche source: ${source_branch}" >&2
    print_info "Branche cible: ${target_branch}" >&2
    print_info "Branche actuelle: ${current_branch}" >&2
    echo "" >&2

    echo -e "${COLOR_BOLD}Où voulez-vous aller?${COLOR_RESET}" >&2
    echo "  1. Rester sur ${current_branch}" >&2

    # Option 2: Retourner sur la branche source si différente de la branche actuelle
    if [[ "$current_branch" != "$source_branch" ]]; then
        echo "  2. Retourner sur ${source_branch}" >&2
        echo "  3. Aller sur une autre branche" >&2
        echo "  4. Afficher le statut et décider après" >&2
    else
        echo "  2. Aller sur une autre branche" >&2
        echo "  3. Afficher le statut et décider après" >&2
    fi
    echo "" >&2

    read -p "$(echo -e "${COLOR_CYAN}Choisissez une option: ${COLOR_RESET}")" switch_choice

    # Gérer les choix en fonction de la situation
    if [[ "$current_branch" != "$source_branch" ]]; then
        # Si on n'est PAS sur la branche source, options: 1(rester), 2(retourner), 3(autre), 4(statut)
        case $switch_choice in
            1)
                print_info "Vous restez sur ${current_branch}" >&2
                echo "1"
                ;;
            2)
                print_step "Basculement sur ${source_branch}..." >&2
                git checkout "$source_branch" >&2
                print_success "Maintenant sur ${source_branch}" >&2
                echo "2"
                ;;
            3)
                echo "" >&2
                print_step "Branches disponibles:" >&2
                git branch -a | grep -v "remotes/origin/HEAD" >&2
                echo "" >&2
                read -p "$(echo -e "${COLOR_CYAN}Nom de la branche: ${COLOR_RESET}")" chosen_branch
                chosen_branch=$(echo "$chosen_branch" | sed 's/^[* ]*//' | sed 's/remotes\/origin\///')

                if [[ -n "$chosen_branch" ]]; then
                    print_step "Basculement sur ${chosen_branch}..." >&2
                    if git checkout "$chosen_branch" 2>&1 >&2; then
                        print_success "Maintenant sur ${chosen_branch}" >&2
                    else
                        print_error "Impossible de basculer sur ${chosen_branch}" >&2
                    fi
                fi
                echo "3"
                ;;
            4)
                echo "" >&2
                git status >&2
                echo "" >&2
                git log --oneline --graph --decorate -5 >&2
                echo "" >&2
                if confirm "Voulez-vous changer de branche maintenant?" "n"; then
                    ask_branch_switch "$source_branch" "$target_branch"
                else
                    echo "4"
                fi
                ;;
            *)
                print_error "Option invalide" >&2
                echo "0"
                ;;
        esac
    else
        # Si on EST sur la branche source, options: 1(rester), 2(autre), 3(statut)
        case $switch_choice in
            1)
                print_info "Vous restez sur ${current_branch}" >&2
                echo "1"
                ;;
            2)
                echo "" >&2
                print_step "Branches disponibles:" >&2
                git branch -a | grep -v "remotes/origin/HEAD" >&2
                echo "" >&2
                read -p "$(echo -e "${COLOR_CYAN}Nom de la branche: ${COLOR_RESET}")" chosen_branch
                chosen_branch=$(echo "$chosen_branch" | sed 's/^[* ]*//' | sed 's/remotes\/origin\///')

                if [[ -n "$chosen_branch" ]]; then
                    print_step "Basculement sur ${chosen_branch}..." >&2
                    if git checkout "$chosen_branch" 2>&1 >&2; then
                        print_success "Maintenant sur ${chosen_branch}" >&2
                    else
                        print_error "Impossible de basculer sur ${chosen_branch}" >&2
                    fi
                fi
                echo "2"
                ;;
            3)
                echo "" >&2
                git status >&2
                echo "" >&2
                git log --oneline --graph --decorate -5 >&2
                echo "" >&2
                if confirm "Voulez-vous changer de branche maintenant?" "n"; then
                    ask_branch_switch "$source_branch" "$target_branch"
                else
                    echo "3"
                fi
                ;;
            *)
                print_error "Option invalide" >&2
                echo "0"
                ;;
        esac
    fi
}

show_branches_status() {
    print_header "🌳 ÉTAT DES BRANCHES"

    echo -e "${COLOR_BOLD}Branches principales:${COLOR_RESET}"

    for branch in "$BRANCH_DEV" "$BRANCH_STAGING" "$BRANCH_MAIN" "$BRANCH_PROD"; do
        if check_branch_exists "$branch"; then
            local commit_count=$(git rev-list --count "$branch" 2>/dev/null || echo "?")
            local last_commit=$(git log -1 --format="%h - %s (%ar)" "$branch" 2>/dev/null || echo "N/A")

            echo ""
            echo -e "${COLOR_CYAN}▶ ${branch}${COLOR_RESET}"
            echo -e "  Commits: ${commit_count}"
            echo -e "  Dernier: ${last_commit}"

            # Vérifier si en avance/retard sur origin
            if check_remote_branch_exists "$branch"; then
                local ahead=$(git rev-list --count "origin/${branch}..${branch}" 2>/dev/null || echo "0")
                local behind=$(git rev-list --count "${branch}..origin/${branch}" 2>/dev/null || echo "0")

                if [[ "$ahead" -gt 0 ]]; then
                    echo -e "  ${COLOR_GREEN}↑ ${ahead} commit(s) en avance${COLOR_RESET}"
                fi
                if [[ "$behind" -gt 0 ]]; then
                    echo -e "  ${COLOR_RED}↓ ${behind} commit(s) en retard${COLOR_RESET}"
                fi
            fi
        else
            echo ""
            echo -e "${COLOR_CYAN}▶ ${branch}${COLOR_RESET}"
            echo -e "  ${COLOR_YELLOW}Branche locale inexistante${COLOR_RESET}"
        fi
    done

    echo ""
    echo -e "${COLOR_BOLD}Feature branches:${COLOR_RESET}"

    local feature_branches=$(git branch --list "${FEATURE_PREFIX}*" | sed 's/^[* ]*//')

    if [[ -n "$feature_branches" ]]; then
        while IFS= read -r branch; do
            local last_commit=$(git log -1 --format="%h - %s (%ar)" "$branch" 2>/dev/null)
            echo -e "${COLOR_GREEN}▶ ${branch}${COLOR_RESET}"
            echo -e "  ${last_commit}"
        done <<< "$feature_branches"
    else
        print_info "Aucune feature branch"
    fi
}

show_help() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_CYAN}🚀 Git Deployment Workflow - Aide${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_BOLD}DESCRIPTION:${COLOR_RESET}"
    echo -e "    Script interactif complet pour gérer le workflow Git avec opérations avancées"
    echo ""
    echo -e "${COLOR_BOLD}WORKFLOW:${COLOR_RESET}"
    echo -e "    feature → dev → staging → main → prod"
    echo ""
    echo -e "${COLOR_BOLD}BRANCHES:${COLOR_RESET}"
    echo -e "    • ${BRANCH_DEV}      - Intégration des fonctionnalités"
    echo -e "    • ${BRANCH_STAGING}  - Pré-production (tests QA)"
    echo -e "    • ${BRANCH_MAIN}     - Version stable (release)"
    echo -e "    • ${BRANCH_PROD}     - Production live"
    echo ""
    echo -e "${COLOR_BOLD}USAGE:${COLOR_RESET}"
    echo -e "    git-deploy                   Mode interactif (recommandé)"
    echo -e "    git-deploy --help            Afficher cette aide"
    echo -e "    git-deploy --status          Afficher le statut rapide"
    echo -e "    git-deploy --branches        Afficher l'état des branches"
    echo ""
    echo -e "${COLOR_BOLD}FONCTIONNALITÉS:${COLOR_RESET}"
    echo ""
    echo -e "    ${COLOR_BOLD}${COLOR_CYAN}Développement:${COLOR_RESET}"
    echo -e "    1. Créer une feature branch"
    echo -e "    2. Merger feature → dev (avec choix de branche après merge)"
    echo ""
    echo -e "    ${COLOR_BOLD}${COLOR_CYAN}Opérations Git Basiques:${COLOR_RESET}"
    echo -e "    3. Add - Ajouter des fichiers au staging"
    echo -e "    4. Commit - Créer un commit"
    echo -e "    5. Push - Pousser les changements"
    echo -e "    6. Pull - Récupérer les changements (merge ou rebase)"
    echo -e "    7. Changer de branche"
    echo ""
    echo -e "    ${COLOR_BOLD}${COLOR_YELLOW}Opérations Avancées (NOUVEAU):${COLOR_RESET}"
    echo -e "    8.  ↩️  Annuler un commit"
    echo -e "        • Soft reset (garder changements staged)"
    echo -e "        • Mixed reset (garder changements unstaged)"
    echo -e "        • Hard reset (supprimer changements)"
    echo -e "        • Amend (modifier dernier commit)"
    echo ""
    echo -e "    9.  ⏮️  Revenir à un commit spécifique"
    echo -e "        • Par hash de commit"
    echo -e "        • Par nombre de commits en arrière"
    echo -e "        • Avec soft/mixed/hard reset"
    echo ""
    echo -e "    10. 🚫 Annuler le suivi d'un fichier"
    echo -e "        • Untrack fichier spécifique"
    echo -e "        • Untrack répertoire"
    echo -e "        • Ajout automatique à .gitignore"
    echo ""
    echo -e "    11. 📜 Voir l'historique (log)"
    echo -e "        • Log standard avec graphique"
    echo -e "        • Log détaillé avec diff"
    echo -e "        • Log d'un fichier spécifique"
    echo -e "        • Log par auteur"
    echo -e "        • Recherche dans les commits"
    echo ""
    echo -e "    12. 💼 Stash - Sauvegarder temporairement"
    echo -e "        • Créer un stash"
    echo -e "        • Lister les stash"
    echo -e "        • Appliquer un stash"
    echo -e "        • Supprimer un stash"
    echo ""
    echo -e "    13. 🗑️  Annuler les modifications"
    echo -e "        • Annuler toutes les modifications"
    echo -e "        • Annuler un fichier spécifique"
    echo -e "        • Nettoyer les fichiers non trackés"
    echo -e "        • Restaurer depuis un commit"
    echo ""
    echo -e "    14. 🗑️  Supprimer une branche"
    echo -e "        • Suppression normale (si mergée)"
    echo -e "        • Suppression forcée"
    echo -e "        • Supprimer locale et distante"
    echo ""
    echo -e "    ${COLOR_BOLD}${COLOR_CYAN}Promotion:${COLOR_RESET}"
    echo -e "    15. Promouvoir dev → staging (avec choix de branche après merge)"
    echo -e "    16. Promouvoir staging → main (avec choix de branche après merge)"
    echo -e "    17. Déployer main → prod (avec choix de branche après merge)"
    echo ""
    echo -e "    ${COLOR_BOLD}${COLOR_CYAN}Gestion & Tags:${COLOR_RESET}"
    echo -e "    18. Créer des tags de version (versioning sémantique automatique)"
    echo -e "    19. Lister les tags"
    echo -e "    20. Synchroniser une branche"
    echo ""
    echo -e "    ${COLOR_BOLD}${COLOR_CYAN}Informations:${COLOR_RESET}"
    echo -e "    21. Afficher le statut Git complet"
    echo -e "    22. Voir l'état des branches"
    echo ""
    echo -e "    7. Promouvoir dev → staging (avec choix de branche après merge)"
    echo -e "    8. Promouvoir staging → main (avec choix de branche après merge)"
    echo -e "    9. Déployer main → prod (avec choix de branche après merge)"
    echo ""
    echo -e "    ${COLOR_BOLD}Gestion:${COLOR_RESET}"
    echo -e "    10. Créer des tags de version (avec versioning sémantique automatique)"
    echo -e "    11. Lister les tags"
    echo -e "    12. Synchroniser une branche"
    echo ""
    echo -e "    ${COLOR_BOLD}Informations:${COLOR_RESET}"
    echo -e "    13. Afficher le statut Git complet"
    echo -e "    14. Voir l'état des branches"
    echo ""
    echo -e "${COLOR_BOLD}NOUVEAU - CHOIX DE BRANCHE APRÈS MERGE:${COLOR_RESET}"
    echo -e "    Après chaque opération de merge (feature→dev, dev→staging, etc.),"
    echo -e "    le script vous demande où vous voulez aller:"
    echo -e "    • Rester sur la branche cible (où le merge a été effectué)"
    echo -e "    • Retourner sur la branche source"
    echo -e "    • Aller sur une autre branche"
    echo -e "    • Afficher le statut avant de décider"
    echo ""
    echo -e "${COLOR_BOLD}EXEMPLES:${COLOR_RESET}"
    echo -e "    # Workflow complet avec nouvelles fonctionnalités"
    echo -e "    1. Créer feature:      ./git-deploy.sh → Option 1"
    echo -e "    2. Ajouter fichiers:   ./git-deploy.sh → Option 3 (git add)"
    echo -e "    3. Commit:             ./git-deploy.sh → Option 4 (git commit)"
    echo -e "    4. Push:               ./git-deploy.sh → Option 5 (git push)"
    echo -e "    5. Merger dans dev:    ./git-deploy.sh → Option 2"
    echo -e "       → Choisir où aller après le merge"
    echo -e "    6. Pull derniers changes: ./git-deploy.sh → Option 6 (git pull)"
    echo -e "    7. Promouvoir staging: ./git-deploy.sh → Option 7"
    echo -e "       → Choisir où aller après le merge"
    echo -e "    8. Tests QA"
    echo -e "    9. Promouvoir main:    ./git-deploy.sh → Option 8"
    echo -e "       → Choisir où aller après le merge"
    echo -e "    10. Déployer prod:     ./git-deploy.sh → Option 9"
    echo -e "        → Choisir où aller après le merge"
    echo ""
    echo -e "${COLOR_BOLD}CONFIGURATION:${COLOR_RESET}"
    echo -e "    Les noms de branches peuvent être modifiés dans le script:"
    echo -e "    - BRANCH_DEV=\"${BRANCH_DEV}\""
    echo -e "    - BRANCH_STAGING=\"${BRANCH_STAGING}\""
    echo -e "    - BRANCH_MAIN=\"${BRANCH_MAIN}\""
    echo -e "    - BRANCH_PROD=\"${BRANCH_PROD}\""
    echo ""
    echo -e "${COLOR_BOLD}SÉCURITÉ:${COLOR_RESET}"
    echo -e "    ✓ Vérification du working tree propre"
    echo -e "    ✓ Confirmation pour les opérations critiques"
    echo -e "    ✓ Fast-forward only pour prod"
    echo -e "    ✓ Affichage des différences avant merge"
    echo -e "    ✓ Options de pull (merge ou rebase)"
    echo -e "    ✓ Avertissement avant force push"
    echo -e "    ✓ Choix de branche intelligent après merge"
    echo ""
    echo -e "${COLOR_BOLD}OPÉRATIONS GIT DÉTAILLÉES:${COLOR_RESET}"
    echo -e "    ${COLOR_BOLD}Add:${COLOR_RESET}"
    echo -e "    • Ajouter tous les fichiers (git add .)"
    echo -e "    • Ajouter fichiers modifiés/supprimés (git add -u)"
    echo -e "    • Ajouter des fichiers spécifiques"
    echo -e "    • Mode interactif (git add -p)"
    echo ""
    echo -e "    ${COLOR_BOLD}Commit:${COLOR_RESET}"
    echo -e "    • Message de commit obligatoire"
    echo -e "    • Option de description détaillée"
    echo -e "    • Affichage des fichiers à commiter"
    echo ""
    echo -e "    ${COLOR_BOLD}Push:${COLOR_RESET}"
    echo -e "    • Push normal"
    echo -e "    • Push avec upstream (-u)"
    echo -e "    • Force push (avec confirmation)"
    echo -e "    • Détection des commits en retard"
    echo ""
    echo -e "    ${COLOR_BOLD}Pull:${COLOR_RESET}"
    echo -e "    • Pull avec merge"
    echo -e "    • Pull avec rebase"
    echo -e "    • Affichage des changements"
    echo -e "    • Détection d'état (en avance/retard)"
    echo ""
    echo -e "    ${COLOR_BOLD}Tags de version (Versioning Sémantique):${COLOR_RESET}"
    echo -e "    Le script gère automatiquement le versioning sémantique (SemVer):"
    echo ""
    echo -e "    • ${COLOR_GREEN}PATCH${COLOR_RESET} (v1.2.3 → v1.2.4)"
    echo -e "      └─ Correctifs de bugs, petites corrections, pas de nouvelles fonctionnalités"
    echo ""
    echo -e "    • ${COLOR_YELLOW}MINOR${COLOR_RESET} (v1.2.3 → v1.3.0)"
    echo -e "      └─ Nouvelles fonctionnalités rétrocompatibles"
    echo -e "      └─ Ajouts qui ne cassent pas l'API existante"
    echo ""
    echo -e "    • ${COLOR_RED}MAJOR${COLOR_RESET} (v1.2.3 → v2.0.0)"
    echo -e "      └─ Changements incompatibles (breaking changes)"
    echo -e "      └─ Modifications qui cassent la compatibilité avec les versions précédentes"
    echo ""
    echo -e "    • Personnalisée"
    echo -e "      └─ Saisie manuelle pour cas spéciaux"
    echo ""
    echo -e "    Le script détecte automatiquement le dernier tag et propose les versions suivantes."
    echo -e "    Si aucun tag n'existe, il propose de créer v1.0.0 comme version initiale."
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════
# MENU PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════

show_menu() {
    clear
    print_header "🚀 Git Deployment Workflow"

    local current_branch=$(get_current_branch)
    echo -e "${COLOR_BOLD}Branche actuelle:${COLOR_RESET} ${COLOR_GREEN}${current_branch}${COLOR_RESET}"
    echo ""

    echo -e "${COLOR_BOLD}DÉVELOPPEMENT:${COLOR_RESET}"
    echo "  1. 🌟 Créer une nouvelle feature branch"
    echo "  2. 🔀 Merger feature → ${BRANCH_DEV}"
    echo ""

    echo -e "${COLOR_BOLD}OPÉRATIONS GIT BASIQUES:${COLOR_RESET}"
    echo "  3. ➕ Add - Ajouter des fichiers"
    echo "  4. 💾 Commit - Créer un commit"
    echo "  5. ⬆️  Push - Pousser les changements"
    echo "  6. ⬇️  Pull - Récupérer les changements"
    echo "  7. 🔀 Changer de branche"
    echo ""

    echo -e "${COLOR_BOLD}OPÉRATIONS AVANCÉES:${COLOR_RESET}"
    echo "  8. ↩️  Annuler un commit"
    echo "  9. ⏮️  Revenir à un commit spécifique"
    echo " 10. 🚫 Annuler le suivi d'un fichier"
    echo " 11. 📜 Voir l'historique (log)"
    echo " 12. 💼 Stash - Sauvegarder temporairement"
    echo " 13. 🗑️  Annuler les modifications"
    echo " 14. 🗑️  Supprimer une branche"
    echo ""

    echo -e "${COLOR_BOLD}PROMOTION:${COLOR_RESET}"
    echo " 15. ⬆️  Promouvoir ${BRANCH_DEV} → ${BRANCH_STAGING}"
    echo " 16. 🎯 Promouvoir ${BRANCH_STAGING} → ${BRANCH_MAIN} (release)"
    echo " 17. 🚀 Déployer ${BRANCH_MAIN} → ${BRANCH_PROD}"
    echo ""

    echo -e "${COLOR_BOLD}GESTION & TAGS:${COLOR_RESET}"
    echo " 18. 🏷️  Créer un tag de version"
    echo " 19. 📋 Lister les tags"
    echo " 20. 🔄 Synchroniser la branche actuelle"
    echo ""

    echo -e "${COLOR_BOLD}INFORMATIONS:${COLOR_RESET}"
    echo " 21. 📊 Afficher le statut Git complet"
    echo " 22. 🌳 État des branches principales"
    echo ""

    echo " 23. ❓ Aide"
    echo "  0. ❌ Quitter"
    echo ""
}

interactive_mode() {
    while true; do
        show_menu

        read -p "$(echo -e "${COLOR_CYAN}Choisissez une option (0-23): ${COLOR_RESET}")" choice

        case $choice in
            1)
                create_feature_branch
                ;;
            2)
                merge_feature_to_dev
                ;;
            3)
                git_add
                ;;
            4)
                git_commit
                ;;
            5)
                git_push
                ;;
            6)
                git_pull
                ;;
            7)
                switch_branch
                ;;
            8)
                undo_commit
                ;;
            9)
                reset_to_commit
                ;;
            10)
                untrack_file
                ;;
            11)
                show_log
                ;;
            12)
                stash_changes
                ;;
            13)
                discard_changes
                ;;
            14)
                delete_branch
                ;;
            15)
                promote_dev_to_staging
                ;;
            16)
                promote_staging_to_main
                ;;
            17)
                deploy_main_to_prod
                ;;
            18)
                create_version_tag
                ;;
            19)
                list_tags
                ;;
            20)
                sync_branch
                ;;
            21)
                show_status
                ;;
            22)
                show_branches_status
                ;;
            23)
                show_help
                ;;
            0)
                print_info "Au revoir!"
                exit 0
                ;;
            *)
                print_error "Option invalide"
                ;;
        esac

        echo ""
        read -p "$(echo -e "${COLOR_CYAN}Appuyez sur Entrée pour continuer...${COLOR_RESET}")"
    done
}

# ═══════════════════════════════════════════════════════════════════════
# POINT D'ENTRÉE
# ═══════════════════════════════════════════════════════════════════════

main() {
    # Traiter les arguments qui n'ont pas besoin d'un repo Git
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --status|-s)
            # Vérifier qu'on est dans un repo Git
            check_git_repo
            show_status
            exit 0
            ;;
        --branches|-b)
            # Vérifier qu'on est dans un repo Git
            check_git_repo
            show_branches_status
            exit 0
            ;;
        "")
            # Vérifier qu'on est dans un repo Git
            check_git_repo
            interactive_mode
            ;;
        *)
            print_error "Option inconnue: $1"
            echo "Utilisez --help pour voir l'aide"
            exit 1
            ;;
    esac
}

# Lancer le script
main "$@"
