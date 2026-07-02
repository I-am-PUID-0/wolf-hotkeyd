#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${WOLF_HOTKEYD_INPUT_CAPTURE_DIR:-/tmp/wolf-hotkeyd-input-captures}"
DEFAULT_STEP_SECONDS="${WOLF_HOTKEYD_INPUT_STEP_SECONDS:-6}"
DEFAULT_SECONDS="${WOLF_HOTKEYD_INPUT_CAPTURE_SECONDS:-45}"
LABEL="${1:-}"
GITHUB_ISSUES_URL="https://github.com/I-am-PUID-0/wolf-hotkeyd/issues/new/choose"

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

prompt_continue() {
  local prompt="$1"

  if [[ -t 0 ]]; then
    read -r -p "${prompt}" _ || true
  fi
}

append_notes_block() {
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

append_note_line() {
  local prompt="$1"
  local prefix="$2"
  local value

  if [[ ! -t 0 ]]; then
    return 0
  fi

  read -r -p "${prompt}: " value || value=""
  if [[ -n "${value}" ]]; then
    echo "${prefix}${value}" >> "${OUTPUT_FILE}"
  fi
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

listener_cmd() {
  local include_sticks="$1"

  LISTEN_CMD=(
    env "PYTHONPATH=${PROJECT_ROOT}:${PYTHONPATH:-}"
    python3 -m wolf_hotkeyd
    --listen-debug
    "${ALL_DEVICES_FLAG[@]}"
    "${RAW_EVENTS_FLAG[@]}"
  )

  if [[ "${include_sticks}" == "1" ]]; then
    LISTEN_CMD+=(--include-sticks)
  fi
}

capture_step() {
  local label="$1"
  local instructions="$2"
  local include_sticks="$3"
  local seconds="$4"
  local tmp_file
  tmp_file="$(mktemp)"

  {
    echo
    echo "===== control capture: ${label} ====="
    echo "instructions=${instructions}"
    echo "include_sticks=${include_sticks}"
    echo "seconds=${seconds}"
  } >> "${OUTPUT_FILE}"

  echo
  echo "---- ${label} ----"
  echo "${instructions}"
  echo "Capture window: ${seconds}s. Press/release the control when prompted."

  if prompt_yes_no "Capture this control?" "y"; then
    prompt_continue "Press Enter when ready, then press/release ${label}..."
    listener_cmd "${include_sticks}"
    echo "\$ timeout --foreground ${seconds} ${LISTEN_CMD[*]}" >> "${OUTPUT_FILE}"

    if command -v timeout >/dev/null 2>&1; then
      timeout --foreground "${seconds}" "${LISTEN_CMD[@]}" > "${tmp_file}" 2>&1
      local code=$?
      cat "${tmp_file}" | tee -a "${OUTPUT_FILE}"
      echo "[capture-controller-input] listener_exit_code=${code}" >> "${OUTPUT_FILE}"
    else
      echo "[capture-controller-input] timeout is not available; press Ctrl+C after capturing ${label}" | tee -a "${OUTPUT_FILE}"
      "${LISTEN_CMD[@]}" 2>&1 | tee -a "${OUTPUT_FILE}"
      echo "[capture-controller-input] listener_exit_code=${PIPESTATUS[0]}" >> "${OUTPUT_FILE}"
    fi

    if ! grep -Eq ' EV_| pressed| released| value=' "${tmp_file}"; then
      echo "[capture-controller-input] no input events captured for ${label}" | tee -a "${OUTPUT_FILE}"
    fi

    if prompt_yes_no "Repeat ${label} capture?" "n"; then
      capture_step "${label} (repeat)" "${instructions}" "${include_sticks}" "${seconds}"
    fi
  else
    echo "[capture-controller-input] skipped ${label}" >> "${OUTPUT_FILE}"
  fi

  append_note_line "Optional note for ${label}" "note="
  rm -f "${tmp_file}"
}

capture_freeform() {
  local seconds="$1"

  {
    echo
    echo "===== additional free-form controller event capture ====="
    echo "seconds=${seconds}"
  } >> "${OUTPUT_FILE}"

  echo
  echo "Additional free-form capture"
  echo "Use this for controls not listed, unusual combos, touchpads, paddles, mode switches, or controls that did not produce events."

  if ! prompt_yes_no "Run an additional free-form listener?" "y"; then
    echo "[capture-controller-input] skipped additional free-form listener" >> "${OUTPUT_FILE}"
    return 0
  fi

  if prompt_yes_no "Include noisy analog stick axes for this free-form capture?" "n"; then
    listener_cmd 1
  else
    listener_cmd 0
  fi

  prompt_continue "Press Enter when ready. Capture will run for ${seconds}s..."
  echo "\$ timeout --foreground ${seconds} ${LISTEN_CMD[*]}" >> "${OUTPUT_FILE}"

  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "${seconds}" "${LISTEN_CMD[@]}" 2>&1 | tee -a "${OUTPUT_FILE}"
    echo "[capture-controller-input] listener_exit_code=${PIPESTATUS[0]}" >> "${OUTPUT_FILE}"
  else
    "${LISTEN_CMD[@]}" 2>&1 | tee -a "${OUTPUT_FILE}"
    echo "[capture-controller-input] listener_exit_code=${PIPESTATUS[0]}" >> "${OUTPUT_FILE}"
  fi
}

capture_custom_controls() {
  if [[ ! -t 0 ]]; then
    return 0
  fi

  while prompt_yes_no "Add a custom control/combo capture?" "n"; do
    local custom_label
    local custom_seconds
    local include_sticks
    custom_label="$(prompt_default "Custom control/combo name" "custom-control")"
    custom_seconds="$(prompt_default "Capture seconds for ${custom_label}" "${STEP_SECONDS}")"
    include_sticks=0
    if prompt_yes_no "Include analog stick axes for ${custom_label}?" "n"; then
      include_sticks=1
    fi
    capture_step "${custom_label}" "Press/release or perform ${custom_label}." "${include_sticks}" "${custom_seconds}"
  done
}

print_submission_instructions() {
  {
    echo
    echo "===== what to do with this capture ====="
    echo "1. Review the log before sharing it."
    echo "2. Remove secrets, account names, hostnames, container IDs, local paths, or unrelated process output if present."
    echo "3. Open a GitHub issue at ${GITHUB_ISSUES_URL}."
    echo "4. Use the Help request or Bug report template."
    echo "5. Attach this log or paste the relevant control sections."
    echo "6. Include controller model, client device, Moonlight/Wolf setup, game/profile context, and which controls worked or did not work."
    echo "7. If you already know the mapping fix, open a pull request updating docs/controller-mapping.md or the relevant config/examples."
  } >> "${OUTPUT_FILE}"

  echo
  echo "[capture-controller-input] wrote ${OUTPUT_FILE}"
  echo
  echo "Next steps:"
  echo "1. Review and sanitize the log."
  echo "2. Open: ${GITHUB_ISSUES_URL}"
  echo "3. Attach the log or paste the relevant sections so the controller mapping can be incorporated."
  echo
  echo "${OUTPUT_FILE}"
}

legacy_timed_capture() {
  {
    echo
    echo "===== non-interactive timed capture ====="
    echo "capture_seconds=${CAPTURE_SECONDS}"
  } >> "${OUTPUT_FILE}"

  listener_cmd "${INCLUDE_STICKS_BY_DEFAULT}"

  if [[ "${CAPTURE_SECONDS}" =~ ^[0-9]+$ ]] && ((CAPTURE_SECONDS > 0)) && command -v timeout >/dev/null 2>&1; then
    timeout --foreground "${CAPTURE_SECONDS}" "${LISTEN_CMD[@]}" 2>&1 | tee -a "${OUTPUT_FILE}"
    echo "[capture-controller-input] listener_exit_code=${PIPESTATUS[0]}" >> "${OUTPUT_FILE}"
  else
    echo "[capture-controller-input] running until Ctrl+C" | tee -a "${OUTPUT_FILE}"
    "${LISTEN_CMD[@]}" 2>&1 | tee -a "${OUTPUT_FILE}"
    echo "[capture-controller-input] listener_exit_code=${PIPESTATUS[0]}" >> "${OUTPUT_FILE}"
  fi
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

STEP_SECONDS="$(prompt_default "Per-control capture seconds" "${DEFAULT_STEP_SECONDS}")"
CAPTURE_SECONDS="$(prompt_default "Free-form capture duration in seconds" "${DEFAULT_SECONDS}")"
ALL_DEVICES_FLAG=()
RAW_EVENTS_FLAG=()
INCLUDE_STICKS_BY_DEFAULT=0
LISTEN_CMD=()

if prompt_yes_no "Include all input devices? Usually no" "n"; then
  ALL_DEVICES_FLAG=(--all-devices)
fi

if prompt_yes_no "Include raw non-key/non-axis events? Usually no" "n"; then
  RAW_EVENTS_FLAG=(--raw-events)
fi

if prompt_yes_no "Include analog stick axes by default? Usually no" "n"; then
  INCLUDE_STICKS_BY_DEFAULT=1
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
  echo "step_seconds=${STEP_SECONDS}"
  echo "free_form_capture_seconds=${CAPTURE_SECONDS}"
  echo "all_devices=${ALL_DEVICES_FLAG[*]:-false}"
  echo "raw_events=${RAW_EVENTS_FLAG[*]:-false}"
  echo "include_sticks_by_default=${INCLUDE_STICKS_BY_DEFAULT}"
} > "${OUTPUT_FILE}"

append_notes_block "pre-capture notes"

run_logged "input devices" ls -lah /dev/input
run_logged "input device registry" cat /proc/bus/input/devices
run_logged "wolf-hotkeyd device capabilities" env "PYTHONPATH=${PROJECT_ROOT}:${PYTHONPATH:-}" python3 -m wolf_hotkeyd --list-devices --show-capabilities

{
  echo
  echo "===== walkthrough instructions ====="
  echo "The script will prompt for one control at a time."
  echo "For each prompt, press Enter, then press and release the requested control during the capture window."
  echo "If no events appear, continue anyway; the log records that the control produced no visible event."
  echo "Use custom controls at the end for paddles, touchpads, mode buttons, combos, or layout-specific mappings."
} | tee -a "${OUTPUT_FILE}"

if [[ ! -t 0 ]]; then
  legacy_timed_capture
  append_notes_block "post-capture notes"
  print_submission_instructions
  exit 0
fi

capture_step "A / south face button" "Press and release A / south." 0 "${STEP_SECONDS}"
capture_step "B / east face button" "Press and release B / east." 0 "${STEP_SECONDS}"
capture_step "X / west face button" "Press and release X / west." 0 "${STEP_SECONDS}"
capture_step "Y / north face button" "Press and release Y / north." 0 "${STEP_SECONDS}"
capture_step "LB / L1" "Press and release left bumper." 0 "${STEP_SECONDS}"
capture_step "RB / R1" "Press and release right bumper." 0 "${STEP_SECONDS}"
capture_step "LT / L2" "Fully press and release left trigger." 0 "${STEP_SECONDS}"
capture_step "RT / R2" "Fully press and release right trigger." 0 "${STEP_SECONDS}"
capture_step "D-pad up" "Press and release D-pad up." 0 "${STEP_SECONDS}"
capture_step "D-pad down" "Press and release D-pad down." 0 "${STEP_SECONDS}"
capture_step "D-pad left" "Press and release D-pad left." 0 "${STEP_SECONDS}"
capture_step "D-pad right" "Press and release D-pad right." 0 "${STEP_SECONDS}"
capture_step "Minus / Select / Back" "Press and release minus, select, or back." 0 "${STEP_SECONDS}"
capture_step "Plus / Start / Menu" "Press and release plus, start, or menu." 0 "${STEP_SECONDS}"
capture_step "L3 / left stick press" "Press and release the left stick click." 0 "${STEP_SECONDS}"
capture_step "R3 / right stick press" "Press and release the right stick click." 0 "${STEP_SECONDS}"
capture_step "Guide / Home" "Press and release Guide/Home if it is not intercepted by the client." 0 "${STEP_SECONDS}"
capture_step "Left stick movement" "Move the left stick in a circle, then release to center." 1 "${STEP_SECONDS}"
capture_step "Right stick movement" "Move the right stick in a circle, then release to center." 1 "${STEP_SECONDS}"
capture_step "Steam Deck L4 / left rear button" "Press and release L4 if present or mapped." 0 "${STEP_SECONDS}"
capture_step "Steam Deck R4 / right rear button" "Press and release R4 if present or mapped." 0 "${STEP_SECONDS}"
capture_step "Steam Deck L5 / lower left rear button" "Press and release L5 if present or mapped." 0 "${STEP_SECONDS}"
capture_step "Steam Deck R5 / lower right rear button" "Press and release R5 if present or mapped." 0 "${STEP_SECONDS}"

capture_custom_controls
capture_freeform "${CAPTURE_SECONDS}"
append_notes_block "manual observations and post-capture notes"
print_submission_instructions
