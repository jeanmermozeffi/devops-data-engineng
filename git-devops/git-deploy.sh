#!/usr/bin/env bash
# Shim de compatibilité - le code principal est dans bin/git-deploy
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../bin/git-deploy" "$@"
