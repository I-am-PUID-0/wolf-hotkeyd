#!/usr/bin/env bash
set -u

GAME_LABEL="${1:-}"
OUTPUT_DIR="${WOLF_HOTKEYD_CAPTURE_DIR:-/tmp/wolf-hotkeyd-captures}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
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

append_prompt_value() {
  local prompt="$1"
  local key="$2"
  local default="$3"
  local value

  value="$(prompt_default "${prompt}" "${default}")"
  echo "${key}=${value}" >> "${OUTPUT_FILE}"
}

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

capture_process_snapshot() {
  local label="$1"

  {
    echo
    echo "===== process snapshot: ${label} ====="
    echo "date=$(date -Is)"
  } >> "${OUTPUT_FILE}"

  echo
  echo "Capturing process snapshot: ${label}"
  run_section "steam and game process tree (${label})" "${SCRIPT_DIR}/debug-process-tree.sh"
  run_section "force-close dry run (${label})" "${SCRIPT_DIR}/force-close-game.sh" --dry-run
}

print_walkthrough() {
  echo
  echo "wolf-hotkeyd game process capture"
  echo
  echo "Use this while the target game is running inside the Wolf Steam container."
  echo "The script records the process tree and a force-close dry run so selector"
  echo "scoring can be tuned for games with launchers, crash reporters, or sidecars."
  echo
  echo "Before sharing the log, review and remove secrets, account names, local paths,"
  echo "hostnames, container IDs, or unrelated process output."
  echo
}

print_submission_instructions() {
  {
    echo
    echo "===== what to do with this capture ====="
    echo "1. Review the log before sharing it."
    echo "2. Remove secrets, account names, hostnames, container IDs, local paths, or unrelated process output if present."
    echo "3. Open a GitHub issue at ${GITHUB_ISSUES_URL}."
    echo "4. Use the Bug report or Help request template."
    echo "5. Attach this log or paste the force-close dry-run section."
    echo "6. Include game title, Steam/App ID if known, Proton version, whether the selected PID was correct, and what process should have been selected."
    echo "7. If you know the scoring fix, open a pull request updating actions/force-close-game.sh and include this capture as evidence in the PR notes."
  } >> "${OUTPUT_FILE}"

  echo
  echo "[capture-game-processes] wrote ${OUTPUT_FILE}"
  echo
  echo "Next steps:"
  echo "1. Review and sanitize the log."
  echo "2. Open: ${GITHUB_ISSUES_URL}"
  echo "3. Attach the log or paste the relevant dry-run sections so game process selection can be improved."
  echo
  echo "${OUTPUT_FILE}"
}

if [[ -z "${GAME_LABEL}" ]]; then
  GAME_LABEL="$(prompt_default "Game label" "unknown-game")"
fi

SAFE_LABEL="$(printf '%s' "${GAME_LABEL}" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_//; s/_$//')"

if [[ -z "${SAFE_LABEL}" ]]; then
  SAFE_LABEL="unknown-game"
fi

mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/${TIMESTAMP}-${SAFE_LABEL}.log"

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

print_walkthrough | tee -a "${OUTPUT_FILE}"

{
  echo
  echo "===== game context ====="
} >> "${OUTPUT_FILE}"

append_prompt_value "Game title" "game_title" "${GAME_LABEL}"
append_prompt_value "Steam/App ID if known" "steam_app_id" "unknown"
append_prompt_value "Proton version / compatibility tool if known" "proton_version" "unknown"
append_prompt_value "Launch state" "launch_state" "in-game"
append_prompt_value "Expected main game executable if known" "expected_game_executable" "unknown"

append_notes_block "pre-capture notes"

run_section "input devices" ls -lah /dev/input
run_section "input device registry" cat /proc/bus/input/devices

if [[ -t 0 ]]; then
  prompt_continue "Start or focus the target game now, then press Enter to capture the first snapshot..."
fi

capture_process_snapshot "initial"

if [[ -t 0 ]]; then
  echo
  echo "Review the dry-run output above."
  echo "Look for the '[force-close-game] Selected PID:' line."
  if prompt_yes_no "Did force-close-game select the correct main game process?" "y"; then
    echo "selected_process_correct=yes" >> "${OUTPUT_FILE}"
  else
    echo "selected_process_correct=no" >> "${OUTPUT_FILE}"
    append_prompt_value "What process should have been selected?" "expected_selected_process" "unknown"
    append_prompt_value "What wrong helper/launcher was selected?" "wrong_selected_process" "unknown"
  fi

  while prompt_yes_no "Capture another snapshot after changing game state?" "n"; do
    local_label="$(prompt_default "Snapshot label" "after-state-change")"
    prompt_continue "Change game state as needed, then press Enter to capture ${local_label}..."
    capture_process_snapshot "${local_label}"
  done
fi

append_notes_block "manual observations and post-capture notes"
print_submission_instructions
