#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# status.sh — Health-check dashboard for the payguard-core umbrella repo
#
# Reports for every submodule:
#   • Current branch / detached state
#   • Commits ahead / behind its remote tracking branch
#   • Dirty working tree or staged changes
#   • Whether the pointer recorded in payguard-core matches the submodule HEAD
#
# Usage:
#   ./scripts/status.sh
#   ./scripts/status.sh --short   # one-line-per-submodule summary
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

SHORT="${1:-}"
ISSUES=0

print_header() {
  echo ""
  echo -e "${BOLD}PayGuard Core — Submodule Status${RESET}"
  echo -e "${CYAN}$(printf '─%.0s' {1..60})${RESET}"
  printf "  %-38s %-10s %-12s %s\n" "SUBMODULE" "BRANCH" "SYNC" "STATE"
  echo -e "${CYAN}$(printf '─%.0s' {1..60})${RESET}"
}

check_submodule() {
  local path="$1"
  local name
  name="$(basename "$path")"

  pushd "$path" > /dev/null

  # Branch
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED")

  # Ahead / behind
  local tracking
  tracking=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")
  local sync_label="no-remote"
  if [[ -n "$tracking" ]]; then
    local ahead behind
    read -r ahead behind < <(git rev-list --left-right --count HEAD..."$tracking" 2>/dev/null || echo "0 0")
    if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
      sync_label="${GREEN}in-sync${RESET}"
    elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
      sync_label="${YELLOW}↑${ahead} ahead${RESET}"
    elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
      sync_label="${YELLOW}↓${behind} behind${RESET}"
      ISSUES=$((ISSUES + 1))
    else
      sync_label="${RED}↑${ahead}↓${behind}${RESET}"
      ISSUES=$((ISSUES + 1))
    fi
  fi

  # Dirty state
  local state_label=""
  if ! git diff --quiet 2>/dev/null; then
    state_label="${RED}dirty${RESET}"
    ISSUES=$((ISSUES + 1))
  elif ! git diff --cached --quiet 2>/dev/null; then
    state_label="${YELLOW}staged${RESET}"
  else
    state_label="${GREEN}clean${RESET}"
  fi

  # Pointer match: does the SHA recorded in payguard-core match actual HEAD?
  local recorded_sha head_sha pointer_label=""
  recorded_sha=$(cd "$REPO_ROOT" && git ls-tree HEAD "$path" 2>/dev/null | awk '{print substr($3,1,7)}')
  head_sha=$(git rev-parse --short HEAD)
  if [[ "$recorded_sha" != "$head_sha" ]]; then
    pointer_label=" ${YELLOW}[pointer stale: core@${recorded_sha} ≠ local@${head_sha}]${RESET}"
    ISSUES=$((ISSUES + 1))
  fi

  if [[ "$SHORT" == "--short" ]]; then
    printf "  %-38s %-10s " "$name" "$branch"
    echo -e "${sync_label}  ${state_label}${pointer_label}"
  else
    echo ""
    echo -e "  ${BOLD}${name}${RESET}"
    echo -e "    Branch  : $branch"
    echo -e "    Sync    : ${sync_label}"
    echo -e "    State   : ${state_label}${pointer_label}"
    echo -e "    HEAD    : ${head_sha}  $(git log -1 --pretty=format:'%s')"
  fi

  popd > /dev/null
}

# ---- Main -------------------------------------------------------------------
[[ "$SHORT" == "--short" ]] && print_header

while IFS= read -r path; do
  check_submodule "$path"
done < <(git submodule foreach --quiet 'echo $displaypath')

echo ""
echo -e "${CYAN}$(printf '─%.0s' {1..60})${RESET}"
if [[ $ISSUES -eq 0 ]]; then
  echo -e "  ${GREEN}All submodules are healthy.${RESET}"
else
  echo -e "  ${YELLOW}${ISSUES} issue(s) found. Run './scripts/update-all.sh' to sync.${RESET}"
fi
echo ""
