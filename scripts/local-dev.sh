#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# local-dev.sh — Thin wrapper around docker-compose for the local dev stack
#
# Usage:
#   ./scripts/local-dev.sh up       # start all infrastructure services
#   ./scripts/local-dev.sh down     # stop and remove containers
#   ./scripts/local-dev.sh restart  # stop then start
#   ./scripts/local-dev.sh logs     # tail logs for all containers
#   ./scripts/local-dev.sh ps       # list running containers
#   ./scripts/local-dev.sh reset    # down + remove volumes (destructive)
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/local-dev/docker-compose.yml"

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
info()  { echo -e "${GREEN}[local-dev]${RESET} $*"; }
error() { echo -e "${RED}[local-dev]${RESET} $*" >&2; }

if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not on PATH."
  exit 1
fi

CMD="${1:-help}"

case "$CMD" in
  up)
    info "Starting local infrastructure stack..."
    docker compose -f "$COMPOSE_FILE" up -d --wait
    info "Stack is up. Services:"
    echo "  Postgres (api-gateway)        : localhost:5432"
    echo "  Postgres (user-service)       : localhost:5433"
    echo "  Postgres (payment-service)    : localhost:5434"
    echo "  Postgres (fraud-engine)       : localhost:5435"
    echo "  Postgres (notification)       : localhost:5436"
    echo "  Postgres (reconciliation)     : localhost:5437"
    echo "  Redis                         : localhost:6379"
    echo "  Kafka                         : localhost:9092"
    echo "  Kafka Schema Registry         : localhost:8081"
    echo "  Kafka UI                      : http://localhost:8080"
    ;;
  down)
    info "Stopping local infrastructure stack..."
    docker compose -f "$COMPOSE_FILE" down
    ;;
  restart)
    "$0" down
    "$0" up
    ;;
  logs)
    docker compose -f "$COMPOSE_FILE" logs -f "${@:2}"
    ;;
  ps)
    docker compose -f "$COMPOSE_FILE" ps
    ;;
  reset)
    echo -e "${RED}WARNING: This will delete all local volumes (databases, Kafka topics, Redis data).${RESET}"
    read -rp "Are you sure? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      info "Resetting stack (down + volumes)..."
      docker compose -f "$COMPOSE_FILE" down -v
      info "Done."
    else
      info "Cancelled."
    fi
    ;;
  help|*)
    echo "Usage: $0 {up|down|restart|logs|ps|reset}"
    ;;
esac
