#!/usr/bin/env bash
#
# run-tests.sh
# Lance les tests unitaires d'un projet Node.js (React/Vite ou NestJS)
# et génère un rapport JUnit XML dans test-results/junit.xml
#
# Usage   ./run-tests.sh [dossier_du_projet]   (par défaut le dossier courant)
#
# Codes de sortie
#   0  tous les tests passent
#   1  au moins un test échoue
#   2  prérequis manquant (node, npm, package.json, script de test, dépendances)
#   3  les tests ont tourné mais le rapport JUnit n'a pas été généré

set -uo pipefail

PROJECT_DIR="${1:-.}"
RESULTS_DIR_NAME="test-results"
REPORT_NAME="junit.xml"

log()   { printf '\033[1;34m[run-tests]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[run-tests]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[run-tests] ERREUR\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 1. Vérification des outils
# ---------------------------------------------------------------------------
for cmd in node npm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "$cmd n'est pas installé ou n'est pas dans le PATH."
    exit 2
  fi
done
log "Node $(node --version), npm $(npm --version)"

cd "$PROJECT_DIR" 2>/dev/null || { error "Dossier introuvable : $PROJECT_DIR"; exit 2; }

if [[ ! -f package.json ]]; then
  error "Aucun package.json dans $(pwd)."
  exit 2
fi

# ---------------------------------------------------------------------------
# 2. Détection du type de projet et du lanceur de tests
# ---------------------------------------------------------------------------
read_pkg() {
  node -e "
    const p = require('./package.json');
    const deps = { ...(p.dependencies || {}), ...(p.devDependencies || {}) };
    $1
  "
}

PROJECT_NAME=$(read_pkg "console.log(p.name || 'projet')")
PROJECT_TYPE=$(read_pkg "console.log(deps['@nestjs/core'] ? 'nestjs' : deps['react'] ? 'react' : 'node')")
TEST_RUNNER=$(read_pkg "console.log(deps['vitest'] ? 'vitest' : deps['jest'] ? 'jest' : 'inconnu')")
HAS_TEST_SCRIPT=$(read_pkg "console.log(Boolean(p.scripts && p.scripts.test))")

log "Projet détecté : $PROJECT_NAME (type $PROJECT_TYPE, tests avec $TEST_RUNNER)"

if [[ "$HAS_TEST_SCRIPT" != "true" ]]; then
  error "Aucun script \"test\" dans package.json."
  exit 2
fi

if [[ "$TEST_RUNNER" == "inconnu" ]]; then
  error "Ni Jest ni Vitest trouvé dans les dépendances, impossible de générer un rapport JUnit."
  exit 2
fi

# ---------------------------------------------------------------------------
# 3. Dépendances
# ---------------------------------------------------------------------------
if [[ ! -d node_modules ]]; then
  log "node_modules absent, installation des dépendances..."
  if [[ -f package-lock.json ]]; then
    npm ci || { error "Échec de npm ci."; exit 2; }
  else
    npm install || { error "Échec de npm install."; exit 2; }
  fi
fi

# Jest a besoin du reporter jest-junit pour produire du JUnit XML
if [[ "$TEST_RUNNER" == "jest" && ! -d node_modules/jest-junit ]]; then
  log "jest-junit absent, installation temporaire (à ajouter en devDependency pour la suite)..."
  npm install --no-save jest-junit || { error "Impossible d'installer jest-junit."; exit 2; }
fi

# ---------------------------------------------------------------------------
# 4. Nettoyage des résultats précédents
# ---------------------------------------------------------------------------
RESULTS_DIR="$(pwd)/$RESULTS_DIR_NAME"
log "Nettoyage de $RESULTS_DIR_NAME/ et coverage/"
rm -rf "$RESULTS_DIR" coverage
mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# 5. Exécution des tests selon le lanceur
# ---------------------------------------------------------------------------
export CI=true
log "Lancement des tests..."

case "$TEST_RUNNER" in
  jest)
    export JEST_JUNIT_OUTPUT_DIR="$RESULTS_DIR"
    export JEST_JUNIT_OUTPUT_NAME="$REPORT_NAME"
    export JEST_JUNIT_SUITE_NAME="$PROJECT_NAME ($PROJECT_TYPE)"
    export JEST_JUNIT_ADD_FILE_ATTRIBUTE="true"
    npm test -- --ci --reporters=default --reporters=jest-junit
    TEST_EXIT=$?
    ;;
  vitest)
    npx vitest run --reporter=default --reporter=junit \
      --outputFile.junit="$RESULTS_DIR/$REPORT_NAME"
    TEST_EXIT=$?
    ;;
esac

# ---------------------------------------------------------------------------
# 6. Vérification du rapport et code de sortie
# ---------------------------------------------------------------------------
if [[ ! -s "$RESULTS_DIR/$REPORT_NAME" ]]; then
  error "Le rapport $RESULTS_DIR_NAME/$REPORT_NAME n'a pas été généré."
  exit 3
fi
log "Rapport JUnit : $RESULTS_DIR_NAME/$REPORT_NAME"

if [[ $TEST_EXIT -ne 0 ]]; then
  error "Des tests ont échoué (code $TEST_EXIT)."
  exit 1
fi

ok "Tous les tests sont passés."
exit 0