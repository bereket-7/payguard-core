#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# update-all.sh — Pull the latest commits for every submodule from its remote
#
# Usage:
#   ./scripts/update-all.sh              # update all submodules
#   ./scripts/update-all.sh <submodule>  # update a single named submodule
#
# What it does per submodule:
#   1. Checks out the tracking branch (main)
#   2. Pulls with --rebase to keep history linear
#   3. Reports the new HEAD SHA and commit message
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; RESET='\033[0m'
info()    { echo -e "${GREEN}[update]${RESET} $*"; }
section() { echo -e "\n${CYAN}── $* ${RESET}"; }
warn()    { echo -e "${YELLOW}[update]${RESET} $*"; }
error()   { echo -e "${RED}[update]${RESET} $*" >&2; }

TARGET="${1:-}"
UPDATED=0
SKIPPED=0
FAILED=0

update_submodule() {
  local path="$1"
  local name
  name="$(basename "$path")"

  section "$name"

  # Resolve the configured tracking branch (default: main)
  local branch
  branch=$(git config -f .gitmodules "submodule.${name}.branch" 2>/dev/null || echo "main")

  pushd "$path" > /dev/null

  # Ensure we're on the tracking branch, not detached HEAD
  if ! git checkout "$branch" 2>/dev/null; then
    warn "$name: could not checkout '$branch', skipping"
    SKIPPED=$((SKIPPED + 1))
    popd > /dev/null
    return
  fi

  local before
  before=$(git rev-parse --short HEAD)

  if git pull --rebase --autostash origin "$branch"; then
    local after
    after=$(git rev-parse --short HEAD)
    local msg
    msg=$(git log -1 --pretty=format:"%s")

    if [[ "$before" != "$after" ]]; then
      info "  $before → $after  \"$msg\""
      UPDATED=$((UPDATED + 1))
    else
      info "  already up to date ($after)"
    fi
  else
    error "  pull failed for $name"
    FAILED=$((FAILED + 1))
  fi

  popd > /dev/null
}

# ---- Run updates ------------------------------------------------------------
if [[ -n "$TARGET" ]]; then
  if [[ ! -d "$TARGET" ]]; then
    error "Submodule directory '$TARGET' not found."
    exit 1
  fi
  update_submodule "$TARGET"
else
  while IFS= read -r path; do
    update_submodule "$path"
  done < <(git submodule foreach --quiet 'echo $displaypath')
fi

# ---- Stage bumped pointers --------------------------------------------------
section "Staging updated submodule pointers"
if git diff --quiet; then
  info "No pointer changes to stage."
else
  git add .
  info "Staged submodule pointer changes. Review with 'git diff --cached', then commit:"
  echo ""
  echo "    git commit -m \"chore(deps): bump submodules to latest main\""
fi

# ---- Summary ----------------------------------------------------------------
section "Summary"
echo "  Updated : $UPDATED"
echo "  Skipped : $SKIPPED"
echo "  Failed  : $FAILED"
[[ $FAILED -gt 0 ]] && exit 1 || exit 0
