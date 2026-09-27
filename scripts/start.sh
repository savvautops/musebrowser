#!/usr/bin/env bash
# Launch the musebrowser stack: Xvfb -> openbox -> x11vnc -> websockify(noVNC) -> chromium.
# Safe to re-run: it only starts components that aren't already running.
set -uo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$BASE/profile"
WEBROOT="$BASE/web"
NOVNC_SRC="/usr/share/novnc"
DISPLAY_NUM=":99"
VNC_PORT="5900"
WEB_PORT="6080"

mkdir -p "$PROFILE" "$WEBROOT"

running() { pgrep -f "$1" >/dev/null 2>&1; }

# --- web root: noVNC files + auto-connect landing page ---
if [ ! -f "$WEBROOT/vnc.html" ]; then
  if [ -d "$NOVNC_SRC" ]; then
    cp -r "$NOVNC_SRC"/. "$WEBROOT"/ 2>/dev/null || true
  fi
fi
cat > "$WEBROOT/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>musebrowser</title>
<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale"></head>
<body style="background:#111;color:#eee;font-family:sans-serif">
<p>loading desktop… <a href="vnc.html?autoconnect=true&resize=scale">click here if stuck</a></p>
</body></html>
HTML

# --- Xvfb ---
if ! running "Xvfb $DISPLAY_NUM"; then
  Xvfb $DISPLAY_NUM -screen 0 1280x800x24 >/tmp/musebrowser-xvfb.log 2>&1 &
  sleep 1
fi
export DISPLAY=$DISPLAY_NUM

# --- window manager ---
if ! pgrep -x openbox >/dev/null 2>&1; then
  openbox >/tmp/musebrowser-openbox.log 2>&1 &
  sleep 1
fi

# --- VNC server (localhost only, no password: Access gate is the auth) ---
if ! running "x11vnc.*-rfbport $VNC_PORT"; then
  x11vnc -display $DISPLAY_NUM -nopw -forever -shared -rfbport $VNC_PORT \
    -localhost -ncache 10 >/tmp/musebrowser-x11vnc.log 2>&1 &
  sleep 1
fi

# --- websockify + noVNC on $WEB_PORT ---
if ! running "websockify.*$WEB_PORT"; then
  websockify --web "$WEBROOT" $WEB_PORT localhost:$VNC_PORT \
    >/tmp/musebrowser-websockify.log 2>&1 &
  sleep 1
fi

# --- chromium ---
if ! running "chromium.*--user-data-dir=$PROFILE"; then
  chromium --no-sandbox --disable-dev-shm-usage \
    --user-data-dir="$PROFILE" --display=$DISPLAY_NUM \
    --window-size=1280,800 --start-maximized \
    about:blank >/tmp/musebrowser-chromium.log 2>&1 &
fi

sleep 2
echo "musebrowser stack:"
pgrep -af "Xvfb $DISPLAY_NUM|x11vnc.*$VNC_PORT|websockify.*$WEB_PORT|chromium.*user-data-dir=$PROFILE" \
  | sed 's/^/  /' || true
curl -s -o /dev/null -w "noVNC web UI: HTTP %{http_code} on :$WEB_PORT\n" http://127.0.0.1:$WEB_PORT/
