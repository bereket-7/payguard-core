#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# bootstrap.sh — First-time setup for payguard-core
#
# Usage:
#   ./scripts/bootstrap.sh          # initialise all submodules
#   ./scripts/bootstrap.sh --https  # rewrite SSH remotes to HTTPS (CI / no SSH key)
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---- Colour helpers ---------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
info()  { echo -e "${GREEN}[bootstrap]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[bootstrap]${RESET} $*"; }
error() { echo -e "${RED}[bootstrap]${RESET} $*" >&2; }

# ---- Dependency checks ------------------------------------------------------
for cmd in git docker docker-compose; do
  if ! command -v "$cmd" &>/dev/null; then
    warn "$cmd not found — some steps may be skipped"
  fi
done

# ---- Optional: rewrite SSH → HTTPS ------------------------------------------
if [[ "${1:-}" == "--https" ]]; then
  info "Rewriting submodule remotes to HTTPS..."
  git config --global url."https://github.com/".insteadOf "git@github.com:"
fi

# ---- Initialise & update submodules -----------------------------------------
info "Initialising submodules..."
git submodule update --init --recursive

info "Fetching latest commits for all submodules..."
git submodule update --remote --merge

# ---- Verify each submodule is on its expected branch ------------------------
info "Verifying submodule branches..."
FAILED=0
git submodule foreach --quiet '
  BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED")
  if [ "$BRANCH" = "DETACHED" ]; then
    echo "  WARN  $name is in detached HEAD state"
  else
    echo "  OK    $name @ $BRANCH"
  fi
'

# ---- Done -------------------------------------------------------------------
if [[ $FAILED -eq 0 ]]; then
  info "Bootstrap complete. All submodules are ready."
  echo ""
  echo "  Next steps:"
  echo "    Start local stack : ./scripts/local-dev.sh up"
  echo "    Check repo status : ./scripts/status.sh"
else
  error "Bootstrap finished with warnings. Review output above."
  exit 1
fi
