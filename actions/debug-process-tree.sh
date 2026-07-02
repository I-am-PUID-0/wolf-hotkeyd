#!/usr/bin/env bash
set -u

echo "[debug-process-tree] date=$(date -Is)"
echo "[debug-process-tree] user=$(id -u):$(id -g) cwd=$(pwd)"

echo "[debug-process-tree] steam processes:"
pgrep -a -f '(^|/)(steam|steamwebhelper)( |$)|steamapps|compatdata|Proton|wine|\.exe' || true

echo "[debug-process-tree] process candidates:"
ps -eo pid=,ppid=,pgid=,sid=,etimes=,comm=,args= \
  | awk '
      BEGIN { IGNORECASE=1 }
      /steamapps|compatdata|Proton|wine|\.exe/ &&
      !/wolf-hotkeyd|debug-process-tree|force-close-game|awk / {
        print
      }
    ' || true

echo "[debug-process-tree] process forest:"
ps -eo pid,ppid,pgid,sid,etimes,comm,args --forest || ps -eo pid,ppid,pgid,sid,etimes,comm,args
