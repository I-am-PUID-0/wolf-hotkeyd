#!/usr/bin/env bash

wolf_hotkeyd_done() {
  return 0 2>/dev/null || exit 0
}

wolf_hotkeyd_log() {
  if declare -F gow_log >/dev/null 2>&1; then
    gow_log "[wolf-hotkeyd] $*"
  else
    echo "[wolf-hotkeyd] $*"
  fi
}

if [[ "${WOLF_HOTKEYD_ENABLED:-1}" == "0" || "${WOLF_HOTKEYD_ENABLED:-1}" == "false" ]]; then
  wolf_hotkeyd_log "disabled by WOLF_HOTKEYD_ENABLED"
  wolf_hotkeyd_done
fi

if [[ -f /run/wolf-hotkeyd.pid ]] && kill -0 "$(cat /run/wolf-hotkeyd.pid)" 2>/dev/null; then
  wolf_hotkeyd_log "already running pid=$(cat /run/wolf-hotkeyd.pid)"
  wolf_hotkeyd_done
fi

if ! python3 - <<'PY' >/dev/null 2>&1
import evdev
import yaml
PY
then
  wolf_hotkeyd_log "missing python evdev/yaml dependencies; daemon not started"
  wolf_hotkeyd_done
fi

WOLF_HOTKEYD_CONFIG="${WOLF_HOTKEYD_CONFIG:-/opt/wolf-hotkeyd/examples/config.force-close.yaml}"
WOLF_HOTKEYD_LOG="${WOLF_HOTKEYD_LOG:-/var/log/wolf-hotkeyd.log}"

mkdir -p "$(dirname "${WOLF_HOTKEYD_LOG}")"
touch "${WOLF_HOTKEYD_LOG}"
chmod 0644 "${WOLF_HOTKEYD_LOG}" || true

wolf_hotkeyd_log "starting daemon config=${WOLF_HOTKEYD_CONFIG} log=${WOLF_HOTKEYD_LOG}"
PYTHONPATH=/opt/wolf-hotkeyd \
  nohup python3 -m wolf_hotkeyd \
    --config "${WOLF_HOTKEYD_CONFIG}" \
    --run-actions \
    >> "${WOLF_HOTKEYD_LOG}" 2>&1 &

echo "$!" > /run/wolf-hotkeyd.pid
wolf_hotkeyd_log "started pid=$(cat /run/wolf-hotkeyd.pid)"

wolf_hotkeyd_done
