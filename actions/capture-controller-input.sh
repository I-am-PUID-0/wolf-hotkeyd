#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${WOLF_HOTKEYD_INPUT_CAPTURE_DIR:-/tmp/wolf-hotkeyd-input-captures}"
DEFAULT_SECONDS="${WOLF_HOTKEYD_INPUT_CAPTURE_SECONDS:-45}"
LABEL="${1:-}"

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value

  if [[ -t 0 ]]; then
    read -r -p "${prompt} [${default}]: " value || value=""
    printf '%s' "${value:-${default}}"
  else
    printf '%s' "${default}"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="$2"
  local value

  if [[ -t 0 ]]; then
    read -r -p "${prompt} [${default}]: " value || value=""
    value="${value:-${default}}"
  else
    value="${default}"
  fi

  case "${value}" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

append_notes() {
  local title="$1"

  {
    echo
    echo "===== ${title} ====="
  } >> "${OUTPUT_FILE}"

  if [[ ! -t 0 ]]; then
    echo "(no interactive notes; stdin is not a terminal)" >> "${OUTPUT_FILE}"
    return 0
  fi

  echo
  echo "${title}"
  echo "Type notes for the log. Finish with a single '.' on its own line."

  local line
  while true; do
    read -r line || break
    [[ "${line}" == "." ]] && break
    echo "${line}" >> "${OUTPUT_FILE}"
  done
}

run_logged() {
  local title="$1"
  shift

  {
    echo
    echo "===== ${title} ====="
    echo "\$ $*"
  } >> "${OUTPUT_FILE}"

  "$@" >> "${OUTPUT_FILE}" 2>&1
  local code=$?
  echo "[capture-controller-input] exit_code=${code}" >> "${OUTPUT_FILE}"
  return 0
}

if [[ -z "${LABEL}" ]]; then
  LABEL="$(prompt_default "Capture label/controller/game context" "controller-input")"
fi

SAFE_LABEL="$(printf '%s' "${LABEL}" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_//; s/_$//')"
if [[ -z "${SAFE_LABEL}" ]]; then
  SAFE_LABEL="controller-input"
fi

mkdir -p "${OUTPUT_DIR}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/${TIMESTAMP}-${SAFE_LABEL}.log"

CAPTURE_SECONDS="$(prompt_default "Capture duration in seconds (0 means until Ctrl+C)" "${DEFAULT_SECONDS}")"
ALL_DEVICES_FLAG=()
RAW_EVENTS_FLAG=()
INCLUDE_STICKS_FLAG=()

if prompt_yes_no "Include all input devices? Usually no" "n"; then
  ALL_DEVICES_FLAG=(--all-devices)
fi

if prompt_yes_no "Include raw non-key/non-axis events? Usually no" "n"; then
  RAW_EVENTS_FLAG=(--raw-events)
fi

if prompt_yes_no "Include noisy analog stick axes? Usually no" "n"; then
  INCLUDE_STICKS_FLAG=(--include-sticks)
fi

{
  echo "===== capture metadata ====="
  echo "date=$(date -Is)"
  echo "label=${LABEL}"
  echo "safe_label=${SAFE_LABEL}"
  echo "user=$(id -u):$(id -g)"
  echo "cwd=$(pwd)"
  echo "script_dir=${SCRIPT_DIR}"
  echo "project_root=${PROJECT_ROOT}"
  echo "output_file=${OUTPUT_FILE}"
  echo "capture_seconds=${CAPTURE_SECONDS}"
  echo "all_devices=${ALL_DEVICES_FLAG[*]:-false}"
  echo "raw_events=${RAW_EVENTS_FLAG[*]:-false}"
  echo "include_sticks=${INCLUDE_STICKS_FLAG[*]:-false}"
} > "${OUTPUT_FILE}"

append_notes "pre-capture notes"

run_logged "input devices" ls -lah /dev/input
run_logged "input device registry" cat /proc/bus/input/devices
run_logged "wolf-hotkeyd device capabilities" env "PYTHONPATH=${PROJECT_ROOT}:${PYTHONPATH:-}" python3 -m wolf_hotkeyd --list-devices --show-capabilities

{
  echo
  echo "===== capture instructions ====="
  echo "Suggested order: A, B, X, Y, LB, RB, LT, RT, D-pad up/down/left/right,"
  echo "left stick click, right stick click, left stick movement, right stick movement,"
  echo "Steam Deck back buttons if mapped, and any suspect combo."
  echo "Analog stick axes are suppressed unless --include-sticks was selected."
} | tee -a "${OUTPUT_FILE}"

LISTEN_CMD=(
  env "PYTHONPATH=${PROJECT_ROOT}:${PYTHONPATH:-}"
  python3 -m wolf_hotkeyd
  --listen-debug
  "${ALL_DEVICES_FLAG[@]}"
  "${RAW_EVENTS_FLAG[@]}"
  "${INCLUDE_STICKS_FLAG[@]}"
)

{
  echo
  echo "===== controller event capture ====="
  echo "\$ ${LISTEN_CMD[*]}"
} >> "${OUTPUT_FILE}"

echo
echo "[capture-controller-input] writing ${OUTPUT_FILE}"
echo "[capture-controller-input] press the controls now"

if [[ "${CAPTURE_SECONDS}" =~ ^[0-9]+$ ]] && ((CAPTURE_SECONDS > 0)) && command -v timeout >/dev/null 2>&1; then
  timeout --foreground "${CAPTURE_SECONDS}" "${LISTEN_CMD[@]}" 2>&1 | tee -a "${OUTPUT_FILE}"
  echo "[capture-controller-input] listener_exit_code=${PIPESTATUS[0]}" >> "${OUTPUT_FILE}"
else
  echo "[capture-controller-input] running until Ctrl+C" | tee -a "${OUTPUT_FILE}"
  "${LISTEN_CMD[@]}" 2>&1 | tee -a "${OUTPUT_FILE}"
  echo "[capture-controller-input] listener_exit_code=${PIPESTATUS[0]}" >> "${OUTPUT_FILE}"
fi

append_notes "post-capture notes"

echo "[capture-controller-input] wrote ${OUTPUT_FILE}"
echo "${OUTPUT_FILE}"
