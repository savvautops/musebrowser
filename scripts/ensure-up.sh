#!/usr/bin/env bash
# Watchdog for cron: re-run start.sh if any core component died.
# Recommended cron: */15 * * * * /path/to/musebrowser/scripts/ensure-up.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_restart=false
pgrep -f "Xvfb :99" >/dev/null 2>&1 || need_restart=true
pgrep -f "x11vnc.*-rfbport 5900" >/dev/null 2>&1 || need_restart=true
pgrep -f "websockify.*6080" >/dev/null 2>&1 || need_restart=true

if [ "$need_restart" = true ]; then
  echo "$(date -u +%FT%TZ) musebrowser: restarting stack" >> /tmp/musebrowser-watchdog.log
  "$SCRIPT_DIR/start.sh" >> /tmp/musebrowser-watchdog.log 2>&1
else
  echo "$(date -u +%FT%TZ) musebrowser: all up" >> /tmp/musebrowser-watchdog.log
fi
