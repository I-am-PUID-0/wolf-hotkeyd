#!/usr/bin/env bash
set -euo pipefail

echo "[test-action] wolf-hotkeyd action execution works"
echo "[test-action] uid=$(id -u) gid=$(id -g)"
echo "[test-action] argv=$*"
