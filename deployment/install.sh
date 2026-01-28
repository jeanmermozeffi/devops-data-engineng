#!/usr/bin/env bash

# ============================================================================
# Installation du DevOps CLI
# ============================================================================
#
# Ce script installe les commandes devops globalement sur votre système
#
# Usage: ./install.sh
#
# ============================================================================

set -e

# Couleurs
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"

echo -e "${CYAN}Installation du DevOps CLI${NC}"
echo ""

# Créer le dossier d'installation s'il n'existe pas
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${GREEN}[INFO]${NC} Création de $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

# Créer un symlink vers le CLI
echo -e "${GREEN}[INFO]${NC} Installation de la commande 'devops'..."
ln -sf "$SCRIPT_DIR/devops" "$INSTALL_DIR/devops"

# Vérifier si ~/.local/bin est dans le PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}[ATTENTION]${NC} $INSTALL_DIR n'est pas dans votre PATH"
    echo ""
    echo "Ajoutez cette ligne à votre ~/.zshrc ou ~/.bashrc :"
    echo ""
    echo -e "${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo ""
    echo "Puis rechargez votre configuration:"
    echo -e "${CYAN}source ~/.zshrc${NC}  # ou source ~/.bashrc"
    echo ""
fi

echo -e "${GREEN}[✓]${NC} Installation terminée !"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}Commandes disponibles:${NC}"
echo ""
echo -e "  ${CYAN}devops init${NC}              Initialiser un projet"
echo -e "  ${CYAN}devops deploy <env>${NC}     Déployer (dev/staging/prod)"
echo -e "  ${CYAN}devops package${NC}           Créer un package"
echo -e "  ${CYAN}devops registry <cmd>${NC}   Gérer le registry Docker"
echo -e "  ${CYAN}devops help${NC}              Afficher l'aide complète"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}Quick Start:${NC}"
echo ""
echo "  1. cd /path/to/your-project"
echo "  2. devops init"
echo "  3. nano .devops.yml  # Configurer"
echo "  4. devops deploy dev"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}Documentation:${NC}"
echo ""
echo -e "  ${CYAN}cat $SCRIPT_DIR/QUICKSTART.md${NC}   Guide 5 minutes"
echo -e "  ${CYAN}cat $SCRIPT_DIR/README.md${NC}        Doc complète"
echo -e "  ${CYAN}cat $SCRIPT_DIR/CHEATSHEET.md${NC}    Commandes essentielles"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
