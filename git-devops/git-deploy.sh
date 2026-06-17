#!/usr/bin/env bash
# Shim de compatibilité - le code principal est dans bin/git-deploy
set -euo pipefail
# Résout les symlinks pour retrouver le vrai emplacement du script
# (robuste même si ce shim est symlinké, p. ex. dans ~/.local/bin)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
exec "$SCRIPT_DIR/../bin/git-deploy" "$@"
