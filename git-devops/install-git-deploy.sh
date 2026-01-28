#!/usr/bin/env bash

# ═══════════════════════════════════════════════════════════════════════
# 🚀 Installation de git-deploy comme commande globale
# ═══════════════════════════════════════════════════════════════════════
#
# Ce script installe git-deploy.sh comme commande globale sur votre Mac
#
# Usage:
#   ./install-git-deploy.sh
#
# Après l'installation, vous pourrez utiliser:
#   git-deploy              # depuis n'importe quel projet
#   git deploy              # comme une commande Git native
#
# ═══════════════════════════════════════════════════════════════════════

set -e

# Couleurs
COLOR_GREEN="\033[0;32m"
COLOR_BLUE="\033[0;34m"
COLOR_YELLOW="\033[0;33m"
COLOR_RESET="\033[0m"

echo ""
echo -e "${COLOR_BLUE}═══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BLUE}  🚀 Installation de git-deploy comme commande globale${COLOR_RESET}"
echo -e "${COLOR_BLUE}═══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

# Déterminer le répertoire d'installation
if [[ -d "$HOME/bin" ]]; then
    INSTALL_DIR="$HOME/bin"
elif [[ -d "$HOME/.local/bin" ]]; then
    INSTALL_DIR="$HOME/.local/bin"
else
    INSTALL_DIR="$HOME/bin"
    mkdir -p "$INSTALL_DIR"
    echo -e "${COLOR_YELLOW}📁 Création du répertoire $INSTALL_DIR${COLOR_RESET}"
fi

# Copier le script
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-deploy.sh"

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo -e "${COLOR_RED}❌ Erreur: git-deploy.sh non trouvé${COLOR_RESET}"
    exit 1
fi

echo -e "${COLOR_BLUE}📋 Installation de git-deploy...${COLOR_RESET}"

# Copier le script
cp "$SCRIPT_PATH" "$INSTALL_DIR/git-deploy"
chmod +x "$INSTALL_DIR/git-deploy"

echo -e "${COLOR_GREEN}✅ Script copié vers $INSTALL_DIR/git-deploy${COLOR_RESET}"

# Créer un alias Git
git config --global alias.deploy '!git-deploy'

echo -e "${COLOR_GREEN}✅ Alias Git créé : 'git deploy'${COLOR_RESET}"

# Vérifier si le PATH contient déjà le répertoire
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo -e "${COLOR_YELLOW}⚠️  Le répertoire $INSTALL_DIR n'est pas dans votre PATH${COLOR_RESET}"
    echo ""
    echo "Ajoutez cette ligne à votre ~/.zshrc (ou ~/.bashrc) :"
    echo ""
    echo "    export PATH=\"\$HOME/bin:\$PATH\""
    echo ""
    echo "Puis rechargez :"
    echo ""
    echo "    source ~/.zshrc"
    echo ""
else
    echo -e "${COLOR_GREEN}✅ Le répertoire $INSTALL_DIR est déjà dans votre PATH${COLOR_RESET}"
fi

echo ""
echo -e "${COLOR_BLUE}═══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_GREEN}  ✅ Installation terminée !${COLOR_RESET}"
echo -e "${COLOR_BLUE}═══════════════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo "Vous pouvez maintenant utiliser :"
echo ""
echo "  ${COLOR_GREEN}git-deploy${COLOR_RESET}              # depuis n'importe quel répertoire Git"
echo "  ${COLOR_GREEN}git deploy${COLOR_RESET}              # comme commande Git native"
echo ""
echo "Pour tester :"
echo ""
echo "  cd /chemin/vers/un/projet"
echo "  git deploy"
echo ""

