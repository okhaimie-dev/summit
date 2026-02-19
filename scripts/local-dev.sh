#!/usr/bin/env bash
#
# Start the local Summit development environment.
#
# Services:
#   1. PostgreSQL (Docker)   — port 5432
#   2. Indexer (Apibara)     — streams Starknet events into PostgreSQL
#   3. API (Hono)            — port 3001
#
# Usage:
#   ./scripts/local-dev.sh          # start all services
#   ./scripts/local-dev.sh stop     # stop all services
#   ./scripts/local-dev.sh restart  # restart all services
#   ./scripts/local-dev.sh status   # show service status
#   ./scripts/local-dev.sh logs     # tail indexer + API logs
#
# Prerequisites:
#   - Docker running
#   - Node.js installed
#   - npm dependencies installed in api/ and indexer/

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DB_CONTAINER="summit-postgres"
DB_USER="postgres"
DB_PASS="postgres"
DB_NAME="summit"
DB_PORT="5432"
DATABASE_URL="postgres://${DB_USER}:${DB_PASS}@localhost:${DB_PORT}/${DB_NAME}"
API_PORT="3001"
STREAM_URL="https://mainnet.starknet.a5a.ch"
STARTING_BLOCK="2209828"
DNA_TOKEN="${DNA_TOKEN:-dna_l3lo5bdfwxr7y8i7j1e7}"

LOG_DIR="${ROOT_DIR}/.local-dev-logs"
INDEXER_LOG="${LOG_DIR}/indexer.log"
API_LOG="${LOG_DIR}/api.log"

# ── helpers ──────────────────────────────────────────────

green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }

is_postgres_running() {
  docker ps --filter "name=${DB_CONTAINER}" --filter "status=running" -q 2>/dev/null | grep -q .
}

is_api_running() {
  lsof -ti ":${API_PORT}" &>/dev/null
}

is_indexer_running() {
  pgrep -f "apibara dev" &>/dev/null
}

wait_for_postgres() {
  local retries=30
  while ! docker exec "${DB_CONTAINER}" pg_isready -U "${DB_USER}" &>/dev/null; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      red "PostgreSQL did not become ready in time"
      exit 1
    fi
    sleep 1
  done
}

# ── start ────────────────────────────────────────────────

start_postgres() {
  if is_postgres_running; then
    green "PostgreSQL already running"
    return
  fi

  yellow "Starting PostgreSQL..."
  if docker ps -a --filter "name=${DB_CONTAINER}" -q 2>/dev/null | grep -q .; then
    docker start "${DB_CONTAINER}" >/dev/null
  else
    docker run -d \
      --name "${DB_CONTAINER}" \
      -e POSTGRES_USER="${DB_USER}" \
      -e POSTGRES_PASSWORD="${DB_PASS}" \
      -e POSTGRES_DB="${DB_NAME}" \
      -p "${DB_PORT}:5432" \
      postgres:16-alpine >/dev/null
  fi

  wait_for_postgres
  green "PostgreSQL ready on port ${DB_PORT}"
}

run_migrations() {
  yellow "Running migrations..."
  cd "${ROOT_DIR}/indexer"
  DATABASE_URL="${DATABASE_URL}" npx drizzle-kit migrate 2>/dev/null || true

  # Apply WebSocket notification triggers
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" \
    -f /dev/stdin < "${ROOT_DIR}/indexer/migrations/0001_triggers.sql" 2>/dev/null
  green "Migrations and triggers applied"
}

start_indexer() {
  if is_indexer_running; then
    green "Indexer already running"
    return
  fi

  mkdir -p "${LOG_DIR}"
  yellow "Starting indexer..."
  cd "${ROOT_DIR}/indexer"
  DNA_TOKEN="${DNA_TOKEN}" \
  DATABASE_URL="${DATABASE_URL}" \
  STREAM_URL="${STREAM_URL}" \
  STARTING_BLOCK="${STARTING_BLOCK}" \
    npm run dev > "${INDEXER_LOG}" 2>&1 &

  sleep 3
  if is_indexer_running; then
    green "Indexer started (log: ${INDEXER_LOG})"
  else
    red "Indexer failed to start. Check ${INDEXER_LOG}"
    tail -10 "${INDEXER_LOG}" 2>/dev/null
    exit 1
  fi
}

start_api() {
  if is_api_running; then
    green "API already running on port ${API_PORT}"
    return
  fi

  mkdir -p "${LOG_DIR}"
  yellow "Starting API..."
  cd "${ROOT_DIR}/api"
  DATABASE_URL="${DATABASE_URL}" \
  PORT="${API_PORT}" \
  NODE_ENV=development \
    npm run dev > "${API_LOG}" 2>&1 &

  sleep 3
  if is_api_running; then
    green "API started on port ${API_PORT} (log: ${API_LOG})"
  else
    red "API failed to start. Check ${API_LOG}"
    tail -10 "${API_LOG}" 2>/dev/null
    exit 1
  fi
}

start_all() {
  echo ""
  green "━━━ Summit Local Dev ━━━"
  echo ""
  start_postgres
  run_migrations
  start_indexer
  start_api
  echo ""
  green "All services running!"
  echo ""
  echo "  PostgreSQL:  localhost:${DB_PORT}"
  echo "  API:         http://localhost:${API_PORT}"
  echo "  API health:  http://localhost:${API_PORT}/health"
  echo "  Indexer log: tail -f ${INDEXER_LOG}"
  echo "  API log:     tail -f ${API_LOG}"
  echo ""
}

# ── stop ─────────────────────────────────────────────────

stop_all() {
  echo ""
  yellow "Stopping services..."

  if is_indexer_running; then
    pkill -f "apibara dev" 2>/dev/null || true
    green "Indexer stopped"
  fi

  if is_api_running; then
    kill "$(lsof -t -i ":${API_PORT}")" 2>/dev/null || true
    green "API stopped"
  fi

  if is_postgres_running; then
    docker stop "${DB_CONTAINER}" >/dev/null
    green "PostgreSQL stopped"
  fi

  echo ""
}

# ── status ───────────────────────────────────────────────

show_status() {
  echo ""
  printf "  %-12s %s\n" "PostgreSQL:" "$(is_postgres_running && green 'running' || red 'stopped')"
  printf "  %-12s %s\n" "Indexer:" "$(is_indexer_running && green 'running' || red 'stopped')"
  printf "  %-12s %s\n" "API:" "$(is_api_running && green 'running' || red 'stopped')"

  if is_postgres_running; then
    local block
    block=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -tAc \
      "SELECT order_key FROM airfoil.checkpoints LIMIT 1;" 2>/dev/null || echo "?")
    printf "  %-12s %s\n" "Indexed to:" "block ${block}"
  fi

  if is_api_running; then
    local health
    health=$(curl -s "http://localhost:${API_PORT}/health" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
    printf "  %-12s %s\n" "API health:" "${health}"
  fi
  echo ""
}

# ── logs ─────────────────────────────────────────────────

show_logs() {
  tail -f "${INDEXER_LOG}" "${API_LOG}" 2>/dev/null
}

# ── main ─────────────────────────────────────────────────

case "${1:-start}" in
  start)   start_all ;;
  stop)    stop_all ;;
  restart) stop_all; sleep 2; start_all ;;
  status)  show_status ;;
  logs)    show_logs ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs}"
    exit 1
    ;;
esac
