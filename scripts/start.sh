#!/usr/bin/env bash
# Launch the musebrowser stack: Xvnc (TigerVNC X server w/ built-in VNC)
# -> websockify (noVNC) -> chromium.
# Designed for persistence: Xvnc comes from the base image, websockify from
# pip --user, chromium from Playwright's bundle — everything lives in $HOME,
# nothing depends on apt state (apt installs outside $HOME can vanish).
# Safe to re-run: only starts components that aren't already running.
set -uo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$BASE/profile"
WEBROOT="$BASE/web"
NOVNC_SRC="/usr/share/novnc"
DISPLAY_NUM=":99"
VNC_PORT="5900"
WEB_PORT="6080"

export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$PROFILE" "$WEBROOT"

# --- web root: noVNC files + auto-connect landing page ---
if [ ! -f "$WEBROOT/vnc.html" ] && [ -d "$NOVNC_SRC" ]; then
  cp -r "$NOVNC_SRC"/. "$WEBROOT"/ 2>/dev/null || true
fi
cat > "$WEBROOT/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>musebrowser</title>
<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale"></head>
<body style="background:#111;color:#eee;font-family:sans-serif">
<p>loading desktop… <a href="vnc.html?autoconnect=true&resize=scale">click here if stuck</a></p>
</body></html>
HTML

# --- Xvnc: X server + VNC in one (localhost only, no auth: the Access gate is the auth) ---
if ! pgrep -f "[X]vnc $DISPLAY_NUM" >/dev/null 2>&1; then
  Xvnc $DISPLAY_NUM -geometry 1280x800 -depth 24 -rfbport $VNC_PORT \
    -localhost -SecurityTypes None -AlwaysShared \
    >/tmp/musebrowser-xvnc.log 2>&1 &
  sleep 2
fi
export DISPLAY=$DISPLAY_NUM

# --- websockify + noVNC on $WEB_PORT ---
if ! pgrep -f "[w]ebsockify.*$WEB_PORT" >/dev/null 2>&1; then
  websockify --web "$WEBROOT" $WEB_PORT localhost:$VNC_PORT \
    >/tmp/musebrowser-websockify.log 2>&1 &
  sleep 1
fi

# --- chromium (auto-detect: Playwright bundle first, then system; skip snap stubs) ---
detect_chromium() {
  local c bin
  for c in "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux/chrome; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  for c in chromium chromium-browser google-chrome google-chrome-stable; do
    bin="$(command -v "$c" 2>/dev/null)" || continue
    if "$bin" --version 2>/dev/null | grep -qi "chrom"; then echo "$bin"; return 0; fi
  done
  return 1
}
CHROMIUM_BIN="${CHROMIUM_BIN:-$(detect_chromium)}"
if [ -z "$CHROMIUM_BIN" ]; then
  echo "ERROR: no working chromium found." >&2
  echo "  pip install --user --break-system-packages playwright && python3 -m playwright install chromium" >&2
  echo "  (then download the zip with curl --retry, the in-tool downloader stalls here)" >&2
  exit 1
fi
if ! pgrep -f "[c]hrom.*--user-data-dir=$PROFILE" >/dev/null 2>&1; then
  "$CHROMIUM_BIN" --no-sandbox --disable-dev-shm-usage \
    --user-data-dir="$PROFILE" --display=$DISPLAY_NUM \
    --window-size=1280,800 --start-maximized \
    about:blank >/tmp/musebrowser-chromium.log 2>&1 &
fi

sleep 2
echo "musebrowser stack ($CHROMIUM_BIN):"
pgrep -af "[X]vnc $DISPLAY_NUM|[w]ebsockify.*$WEB_PORT|[c]hrom.*--user-data-dir=$PROFILE" \
  | sed 's/^/  /' | cut -c1-160 || true
curl -s -o /dev/null -w "noVNC web UI: HTTP %{http_code} on :$WEB_PORT\n" http://127.0.0.1:$WEB_PORT/
