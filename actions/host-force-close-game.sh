#!/usr/bin/env bash
set -u

CONTAINER_NAME="${WOLF_HOTKEYD_CONTAINER:-}"
CONTAINER_PREFIX="${WOLF_HOTKEYD_CONTAINER_PREFIX:-WolfSteam}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNER_SCRIPT="${SCRIPT_DIR}/force-close-game.sh"

log() {
  echo "[host-force-close-game] $*"
}

usage() {
  cat <<'EOF'
Usage: host-force-close-game.sh [--dry-run]

Runs from the Docker/Wolf host. It finds the active Wolf Steam container and
executes force-close-game.sh inside that container only when triggered.

Environment:
  WOLF_HOTKEYD_CONTAINER        exact container name or id to target
  WOLF_HOTKEYD_CONTAINER_PREFIX container name prefix to auto-select
                               default: WolfSteam
EOF
}

find_container() {
  if [[ -n "${CONTAINER_NAME}" ]]; then
    docker inspect "${CONTAINER_NAME}" >/dev/null 2>&1 && {
      printf '%s\n' "${CONTAINER_NAME}"
      return 0
    }
    log "configured container not found: ${CONTAINER_NAME}"
    return 1
  fi

  docker ps --format '{{.Names}}' \
    | awk -v prefix="${CONTAINER_PREFIX}" '
        index($0, prefix "_") == 1 || $0 == prefix { print; exit }
      '
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    log "docker CLI not found"
    return 1
  fi

  if [[ ! -r "${INNER_SCRIPT}" ]]; then
    log "missing inner script: ${INNER_SCRIPT}"
    return 1
  fi

  local container
  container="$(find_container)"
  if [[ -z "${container}" ]]; then
    log "no running container found with prefix ${CONTAINER_PREFIX}"
    return 2
  fi

  log "target container=${container}"
  docker exec -i "${container}" bash -s -- "$@" < "${INNER_SCRIPT}"
}

main "$@"
