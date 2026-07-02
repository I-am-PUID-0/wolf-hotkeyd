#!/usr/bin/env bash
set -u

TERM_WAIT_SECONDS="${WOLF_FORCE_CLOSE_TERM_WAIT_SECONDS:-5}"
DRY_RUN=0

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

log() {
  echo "[force-close-game] $*"
}

steam_pid() {
  pgrep -xo steam 2>/dev/null || pgrep -fo '(^|/)steam( |$)' 2>/dev/null || true
}

candidate_rows() {
  ps -eo pid=,ppid=,pgid=,sid=,etimes=,comm=,args= \
    | awk '
        BEGIN { IGNORECASE=1 }
        /steamapps|compatdata|Proton|wine|\.exe/ &&
        !/steamwebhelper|wineserver|services\.exe|explorer\.exe|pressure-vessel|reaper|pv-bwrap|umu-shim|wolf-hotkeyd|force-close-game|debug-process-tree|awk / {
          print
        }
      ' || true
}

scored_candidate_rows() {
  candidate_rows \
    | awk '
        BEGIN { IGNORECASE=1 }
        {
          score = 0
          pid = $1
          comm = $6
          args = $0
          lower_comm = tolower(comm)
          lower_args = tolower(args)

          if (args ~ /\.exe/) score += 20
          if (comm ~ /\.exe$/) score += 40
          if (args ~ /S:\\common\\/ || args ~ /steamapps\/common/) score += 80
          if (args ~ /Binaries|Win64|x64|shipping/) score += 40

          if (args ~ /C:\\windows\\system32/ || args ~ /windows\\system32/) score -= 500
          if (comm ~ /steam\.exe|wineserver|services\.exe|explorer\.exe|winedevice\.exe|plugplay\.exe|svchost\.exe|rpcss\.exe|tabtip\.exe|xalia\.exe/) score -= 500
          if (comm ~ /python|pv-adverb|srt-bwrap|reaper|sh$/) score -= 200
          if (args ~ /Proton -|proton waitforexitandrun|SteamLinuxRuntime|pressure-vessel/) score -= 100
          if (lower_comm ~ /(crash|crs|report|uploader|upload|telemetry|metrics|handler)/) score -= 500
          if (lower_args ~ /\\crs\\/ ||
              lower_args ~ /crashrecorder|crashpad|crashreport|crash-handler|crash_report/ ||
              lower_args ~ /--no-upload|--upload|--metrics-dir|--database=.*\\crs\\/ ||
              lower_args ~ /recap\.tools|sentry|bugsnag/) score -= 500

          printf "%d %010d %s\n", score, pid, $0
        }
      '
}

children_of() {
  local parent="$1"
  ps -eo pid=,ppid= \
    | awk -v parent="${parent}" '$2 == parent { print $1 }'
}

collect_tree() {
  local root="$1"
  local queue=("${root}")
  local seen=" ${root} "
  local result=("${root}")

  while ((${#queue[@]})); do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")

    local child
    while read -r child; do
      [[ -z "${child}" ]] && continue
      if [[ "${seen}" != *" ${child} "* ]]; then
        seen+="${child} "
        result+=("${child}")
        queue+=("${child}")
      fi
    done < <(children_of "${current}")
  done

  printf '%s\n' "${result[@]}"
}

pid_alive() {
  local pid="$1"
  kill -0 "${pid}" 2>/dev/null
}

kill_pids() {
  local signal="$1"
  shift
  local pid

  for pid in "$@"; do
    if [[ -n "${pid}" ]] && pid_alive "${pid}"; then
      log "sending ${signal} to pid=${pid}"
      kill "-${signal}" "${pid}" 2>/dev/null || true
    fi
  done
}

main() {
  log "starting dry_run=${DRY_RUN}"

  local steam
  steam="$(steam_pid)"
  if [[ -z "${steam}" ]]; then
    log "Steam process not found"
    return 1
  fi
  log "Steam PID: ${steam}"

  local candidates
  candidates="$(candidate_rows)"
  if [[ -z "${candidates}" ]]; then
    log "No obvious game candidate found"
    return 2
  fi

  log "Candidates:"
  printf '%s\n' "${candidates}" | sed 's/^/[force-close-game]   /'

  local scored_candidates
  scored_candidates="$(scored_candidate_rows)"
  log "Scored candidates:"
  printf '%s\n' "${scored_candidates}" | sed 's/^/[force-close-game]   /'

  local selected
  selected="$(printf '%s\n' "${scored_candidates}" | sort -n -k1,1 -k2,2 | tail -1 | awk '{ print $3 }')"
  if [[ -z "${selected}" ]]; then
    log "Failed to select a candidate"
    return 3
  fi

  local selected_args
  selected_args="$(ps -p "${selected}" -o args= 2>/dev/null || true)"
  log "Selected PID: ${selected} ${selected_args}"

  mapfile -t tree < <(collect_tree "${selected}" | sort -rn)
  if ((${#tree[@]} == 0)); then
    log "No process tree found for selected PID"
    return 4
  fi

  log "Selected process tree:"
  local pid
  for pid in "${tree[@]}"; do
    ps -p "${pid}" -o pid=,ppid=,pgid=,sid=,comm=,args= 2>/dev/null \
      | sed 's/^/[force-close-game]   /' || true
  done

  if ((DRY_RUN)); then
    log "Dry run complete; no signals sent"
    return 0
  fi

  kill_pids TERM "${tree[@]}"
  sleep "${TERM_WAIT_SECONDS}"

  local survivors=()
  for pid in "${tree[@]}"; do
    if pid_alive "${pid}"; then
      survivors+=("${pid}")
    fi
  done

  if ((${#survivors[@]})); then
    log "Processes still alive after ${TERM_WAIT_SECONDS}s"
    kill_pids KILL "${survivors[@]}"
  fi

  log "Done"
}

main "$@"
