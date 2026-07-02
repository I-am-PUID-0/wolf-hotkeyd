#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[install-container-deps] $*"
}

if command -v python3 >/dev/null 2>&1; then
  log "python3 found: $(python3 --version 2>&1)"
else
  log "python3 is missing"
fi

if python3 - <<'PY' >/dev/null 2>&1
import evdev
import yaml
PY
then
  log "python3 evdev and yaml imports already work"
  exit 0
fi

if command -v apt-get >/dev/null 2>&1; then
  log "installing dependencies with apt-get"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 \
    python3-evdev \
    python3-yaml
elif command -v python3 >/dev/null 2>&1; then
  log "apt-get not found; trying pip through python3"
  python3 -m pip install --break-system-packages 'evdev>=1.7,<2' 'PyYAML>=6,<7'
else
  log "no supported installer found"
  exit 1
fi

python3 - <<'PY'
import evdev
import yaml

print("[install-container-deps] verified imports: evdev + yaml")
PY
