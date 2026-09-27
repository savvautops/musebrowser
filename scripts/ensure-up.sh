#!/usr/bin/env bash
# Watchdog for cron: re-run start.sh if any core component died.
# Recommended cron: */15 * * * * /path/to/musebrowser/scripts/ensure-up.sh
# NOTE: the _pids filter excludes this script and its caller, because
# pgrep -f matches the invoking shell's own command line.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_pids() {
  local pat="$1" pid
  for pid in $(pgrep -f "$pat" 2>/dev/null); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
      echo "$pid"
    fi
  done
}
_running() { [ -n "$(_pids "$1")" ]; }

need_restart=false
_running "[X]vnc :99" >/dev/null 2>&1 || need_restart=true
_running "[w]ebsockify.*6080" >/dev/null 2>&1 || need_restart=true
_running "[c]dp-bridge" >/dev/null 2>&1 || need_restart=true
_running "[m]b serve" >/dev/null 2>&1 || need_restart=true

if [ "$need_restart" = true ]; then
  echo "$(date -u +%FT%TZ) musebrowser: restarting stack" >> /tmp/musebrowser-watchdog.log
  "$SCRIPT_DIR/start.sh" >> /tmp/musebrowser-watchdog.log 2>&1
else
  echo "$(date -u +%FT%TZ) musebrowser: all up" >> /tmp/musebrowser-watchdog.log
fi
