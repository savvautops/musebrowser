#!/usr/bin/env bash
# Stop the musebrowser stack.
# pkill -f matches the invoking shell's own command line, so a naive
# `pkill -f "[c]dp-bridge"` would SIGTERM this script's caller whenever the
# caller's command text contains the literal pattern (e.g. the file path
# .../agent/cdp-bridge). Guard: never kill ourselves or our parent.
set -uo pipefail
_ME=$$
_PARENT=$PPID

_kill_pat() {
  local pat="$1" pid
  for pid in $(pgrep -f "$pat" 2>/dev/null); do
    if [ "$pid" = "$_ME" ] || [ "$pid" = "$_PARENT" ]; then
      continue
    fi
    kill "$pid" 2>/dev/null || true
  done
}

_kill_pat "[m]b serve"
_kill_pat "[c]dp-bridge"
sleep 1
# backup: any straggler chromium holding the musebrowser profile
_kill_pat "[c]hrome.*musebrowser/profile"
_kill_pat "[w]ebsockify.*6080"
_kill_pat "[X]vnc :99"
echo "musebrowser stopped."
