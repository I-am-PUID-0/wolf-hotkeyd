#!/usr/bin/env bash
set -u

GAME_LABEL="${1:-unknown-game}"
OUTPUT_DIR="${WOLF_HOTKEYD_CAPTURE_DIR:-/tmp/wolf-hotkeyd-captures}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_LABEL="$(printf '%s' "${GAME_LABEL}" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_//; s/_$//')"

if [[ -z "${SAFE_LABEL}" ]]; then
  SAFE_LABEL="unknown-game"
fi

mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/${TIMESTAMP}-${SAFE_LABEL}.log"

run_section() {
  local title="$1"
  shift

  {
    echo
    echo "===== ${title} ====="
    echo "\$ $*"
  } >> "${OUTPUT_FILE}"

  "$@" >> "${OUTPUT_FILE}" 2>&1
  local code=$?
  echo "[capture-game-processes] exit_code=${code}" >> "${OUTPUT_FILE}"
  return 0
}

{
  echo "===== capture metadata ====="
  echo "date=$(date -Is)"
  echo "game_label=${GAME_LABEL}"
  echo "safe_label=${SAFE_LABEL}"
  echo "user=$(id -u):$(id -g)"
  echo "cwd=$(pwd)"
  echo "script_dir=${SCRIPT_DIR}"
  echo "output_file=${OUTPUT_FILE}"
} > "${OUTPUT_FILE}"

run_section "input devices" ls -lah /dev/input
run_section "input device registry" cat /proc/bus/input/devices
run_section "steam and game process tree" "${SCRIPT_DIR}/debug-process-tree.sh"
run_section "force-close dry run" "${SCRIPT_DIR}/force-close-game.sh" --dry-run

echo "[capture-game-processes] wrote ${OUTPUT_FILE}"
echo "${OUTPUT_FILE}"
