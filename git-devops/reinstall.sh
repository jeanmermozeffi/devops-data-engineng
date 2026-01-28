#!/usr/bin/env bash

# Script de réinstallation rapide pour git-deploy v3.0

echo "🔄 Réinstallation de git-deploy v3.0..."
echo ""

# Copier le script
cp git-deploy.sh ~/bin/git-deploy
chmod +x ~/bin/git-deploy

echo "✅ git-deploy installé dans ~/bin/git-deploy"
echo ""

# Vérifier l'alias Git
if git config --global --get alias.deploy > /dev/null 2>&1; then
    echo "✅ Alias Git 'deploy' déjà configuré"
else
    git config --global alias.deploy '!git-deploy'
    echo "✅ Alias Git 'deploy' configuré"
fi

echo ""
echo "🎉 Installation terminée !"
echo ""
echo "Vous pouvez maintenant utiliser :"
echo "  git-deploy              # Depuis n'importe quel projet"
echo "  git deploy              # Alias Git"
echo "  git-deploy --help       # Aide"
echo ""
echo "Nouvelles fonctionnalités v3.0 :"
echo "  Option 8  : Annuler un commit"
echo "  Option 9  : Revenir à un commit spécifique"
echo "  Option 10 : Annuler le suivi d'un fichier"
echo "  Option 11 : Voir l'historique (log)"
echo "  Option 12 : Stash - Sauvegarder temporairement"
echo "  Option 13 : Annuler les modifications"
echo "  Option 14 : Supprimer une branche"
echo ""
echo "📚 Documentation : NOUVELLES-FONCTIONNALITÉS.md"
echo ""

