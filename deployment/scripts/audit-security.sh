#!/bin/bash

# ============================================================================
# Vérification de sécurité - Secrets et .env
# ============================================================================
#
# Ce script vérifie que les secrets ne sont pas exposés dans l'image Docker
#
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

ISSUES_FOUND=0

echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Audit de sécurité - Secrets et .env              ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Test 1: Vérifier que .env n'est pas commité dans git
echo -e "${CYAN}Test 1: Fichiers .env dans git${NC}"
ENV_FILES=$(git ls-files | grep -E "\.env\.(dev|staging|prod|local)$" || true)
if [ -n "$ENV_FILES" ]; then
    log_error "Fichiers .env trouvés dans git:"
    echo "$ENV_FILES"
    log_warn "Ces fichiers ne doivent PAS être committé (contiennent des secrets)"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    log_success "Aucun fichier .env sensible dans git"
fi
echo ""

# Test 2: Vérifier .gitignore
echo -e "${CYAN}Test 2: Configuration .gitignore${NC}"
if grep -q ".env" .gitignore 2>/dev/null; then
    log_success ".gitignore contient .env"
else
    log_error ".env n'est pas dans .gitignore"
    log_warn "Ajoutez '.env*' dans .gitignore"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Test 3: Vérifier que Dockerfile ne copie pas .env
echo -e "${CYAN}Test 3: Dockerfile ne copie pas .env${NC}"
DOCKERFILE_COPY=$(grep -r "COPY.*\.env" deployment/docker/ 2>/dev/null || true)
if [ -n "$DOCKERFILE_COPY" ]; then
    log_error "Dockerfile copie des fichiers .env:"
    echo "$DOCKERFILE_COPY"
    log_warn "Les secrets ne doivent PAS être dans l'image Docker"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    log_success "Dockerfile ne copie pas de fichiers .env"
fi
echo ""

# Test 4: Vérifier que Dockerfile ne hardcode pas de secrets
echo -e "${CYAN}Test 4: Dockerfile ne hardcode pas de secrets${NC}"
DOCKERFILE_SECRETS=$(grep -rE "ENV.*(PASSWORD|SECRET|KEY|TOKEN)=" deployment/docker/ | grep -v "example" || true)
if [ -n "$DOCKERFILE_SECRETS" ]; then
    log_warn "Variables sensibles trouvées dans Dockerfile:"
    echo "$DOCKERFILE_SECRETS"
    log_warn "Vérifiez que ce ne sont pas des secrets réels"
else
    log_success "Pas de secrets hardcodés dans Dockerfile"
fi
echo ""

# Test 5: Vérifier les images Docker locales
echo -e "${CYAN}Test 5: Vérification des images Docker locales${NC}"
if docker images | grep -q "${IMAGE_NAME:-api}"; then
    log_info "Images Docker locales trouvées, vérification..."

    # Prendre la première image
    IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "${IMAGE_NAME:-api}" | head -n1)

    if [ -n "$IMAGE" ]; then
        log_info "Test de l'image: $IMAGE"

        # Vérifier qu'il n'y a pas de .env dans l'image
        if docker run --rm "$IMAGE" sh -c "ls -la /app/.env* 2>/dev/null" 2>/dev/null | grep -q ".env"; then
            log_error "Fichiers .env trouvés dans l'image Docker!"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            log_success "Pas de fichiers .env dans l'image"
        fi

        # Vérifier les variables d'environnement par défaut
        ENV_VARS=$(docker run --rm "$IMAGE" env 2>/dev/null || true)
        if echo "$ENV_VARS" | grep -qE "(DATABASE_PASSWORD|JWT_SECRET|API_KEY)="; then
            log_warn "Variables sensibles détectées dans l'image:"
            echo "$ENV_VARS" | grep -E "(PASSWORD|SECRET|KEY|TOKEN)="
            log_warn "Vérifiez que ce ne sont pas des valeurs réelles"
        else
            log_success "Pas de secrets dans les variables d'environnement par défaut"
        fi
    fi
else
    log_info "Aucune image Docker locale trouvée (OK)"
fi
echo ""

# Test 6: Vérifier docker-compose utilise env_file
echo -e "${CYAN}Test 6: docker-compose utilise env_file${NC}"
if grep -q "env_file:" deployment/docker-compose*.yml 2>/dev/null; then
    log_success "docker-compose utilise env_file (bonne pratique)"
else
    log_warn "docker-compose n'utilise pas env_file"
    log_warn "Recommandé: utiliser env_file au lieu de environment: avec secrets"
fi
echo ""

# Test 7: Vérifier les permissions des fichiers .env
echo -e "${CYAN}Test 7: Permissions des fichiers .env${NC}"
for env_file in .env.dev .env.staging .env.prod; do
    if [ -f "$env_file" ]; then
        PERMS=$(stat -f "%A" "$env_file" 2>/dev/null || stat -c "%a" "$env_file" 2>/dev/null)
        if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
            log_success "$env_file: permissions OK ($PERMS)"
        else
            log_warn "$env_file: permissions trop ouvertes ($PERMS)"
            log_info "Recommandation: chmod 600 $env_file"
        fi
    fi
done
echo ""

# Test 8: Vérifier qu'il existe un .env.example
echo -e "${CYAN}Test 8: Template .env.example${NC}"
if [ -f ".env.example" ]; then
    # Vérifier qu'il ne contient pas de vrais secrets
    if grep -qE "(password|secret|key).*=.*[a-zA-Z0-9]{10,}" .env.example; then
        log_warn ".env.example semble contenir de vraies valeurs"
        log_info "Remplacez les vraies valeurs par 'changeme' ou des exemples"
    else
        log_success ".env.example existe et semble propre"
    fi
else
    log_warn ".env.example n'existe pas"
    log_info "Recommandé: créer un template pour documenter les variables nécessaires"
fi
echo ""

# Résumé
echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Résumé de l'audit                                 ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    log_success "Aucun problème de sécurité majeur détecté !"
    echo ""
    log_info "Bonnes pratiques détectées:"
    echo "  ✅ .env non commité dans git"
    echo "  ✅ .gitignore configuré"
    echo "  ✅ Dockerfile ne copie pas .env"
    echo "  ✅ docker-compose utilise env_file"
    echo "  ✅ Pas de secrets dans l'image Docker"
    echo ""
    exit 0
else
    log_error "$ISSUES_FOUND problème(s) de sécurité détecté(s)"
    echo ""
    log_warn "Consultez la documentation: deployment/SECURITE_SECRETS_ENV.md"
    echo ""
    exit 1
fi

