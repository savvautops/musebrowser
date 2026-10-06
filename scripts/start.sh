#!/usr/bin/env bash
# Launch the musebrowser stack: Xvnc (TigerVNC X server w/ built-in VNC)
# -> websockify (noVNC) -> chromium, driven by cdp-bridge
# -> agent HTTP API on 9280 ("our hands": human via noVNC, agent via mb/API).
# Headed Chrome-for-Testing never binds a TCP --remote-debugging-port, so
# agent/cdp-bridge spawns chromium with --remote-debugging-pipe and serves
# the DevTools HTTP+WS surface on 127.0.0.1:9222 for the agent tooling.
# Designed for persistence: Xvnc comes from the base image, websockify from
# pip --user, chromium from Playwright's bundle, agent tooling is stdlib-only
# python — everything lives in $HOME, nothing depends on apt state (apt
# installs outside $HOME can vanish).
# Safe to re-run: only starts components that aren't already running.
set -uo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$BASE/profile"
WEBROOT="$BASE/web"
NOVNC_SRC="/usr/share/novnc"
DISPLAY_NUM=":99"
VNC_PORT="5900"
WEB_PORT="6080"
CDP_PORT="9222"
AGENT_PORT="9280"

export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$PROFILE" "$WEBROOT"

# pgrep -f matches the invoking shell's own command line, so a naive check
# could "see" this script's caller when the caller's command text contains
# the literal pattern (e.g. .../agent/cdp-bridge). _pids filters out this
# script and its parent; _running is the boolean check.
_pids() {
  local pat="$1" pid
  for pid in $(pgrep -f "$pat" 2>/dev/null); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
      echo "$pid"
    fi
  done
}
_running() { [ -n "$(_pids "$1")" ]; }

# --- web root: noVNC files + auto-connect landing page + SAO overlay ---
if [ ! -f "$WEBROOT/vnc.html" ] && [ -d "$NOVNC_SRC" ]; then
  cp -r "$NOVNC_SRC"/. "$WEBROOT"/ 2>/dev/null || true
fi
# Copy SAO overlay if present in repo
if [ -f "$BASE/web/sao-overlay.js" ]; then
  cp -f "$BASE/web/sao-overlay.js" "$WEBROOT/sao-overlay.js"
fi
# Inject SAO overlay script into vnc.html if not present
if [ -f "$WEBROOT/vnc.html" ] && ! grep -q 'sao-overlay.js' "$WEBROOT/vnc.html"; then
  sed -i 's#</head>#    <script src="sao-overlay.js"></script>\n</head>#' "$WEBROOT/vnc.html"
fi
cat > "$WEBROOT/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>musebrowser</title>
<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale"></head>
<body style="background:#111;color:#eee;font-family:sans-serif">
<p>loading desktop… <a href="vnc.html?autoconnect=true&resize=scale">click here if stuck</a></p>
</body></html>
HTML

# --- Xvnc: X server + VNC in one (localhost only, no auth: the Access gate is the auth) ---
if ! _running "[X]vnc $DISPLAY_NUM"; then
  Xvnc $DISPLAY_NUM -geometry 1280x800 -depth 24 -rfbport $VNC_PORT \
    -localhost -SecurityTypes None -AlwaysShared \
    >/tmp/musebrowser-xvnc.log 2>&1 &
  sleep 2
fi
export DISPLAY=$DISPLAY_NUM

# --- websockify + noVNC on $WEB_PORT (with SAO control proxy) ---
# Bind explicitly to 127.0.0.1: the public URL is served through the
# Cloudflare tunnel, never by exposing websockify directly.
if ! _running "[w]ebsockify.*$WEB_PORT"; then
  if [ -x "$BASE/agent/websockify-sao" ]; then
    "$BASE/agent/websockify-sao" --web "$WEBROOT" 127.0.0.1:$WEB_PORT localhost:$VNC_PORT \
      >/tmp/musebrowser-websockify.log 2>&1 &
  else
    websockify --web "$WEBROOT" 127.0.0.1:$WEB_PORT localhost:$VNC_PORT \
      >/tmp/musebrowser-websockify.log 2>&1 &
  fi
  sleep 1
fi

# --- chromium (auto-detect: Playwright bundle first, then system; skip snap stubs) ---
detect_chromium() {
  local c bin
  for c in "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux/chrome \
             "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux64/chrome; do
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
# --- local forward proxy for Chrome (adds egress Proxy-Authorization) ---
# Chrome itself can't authenticate to the sandbox egress proxy, so a tiny
# localhost-only forwarder on 18080 injects the credentials. Chrome gets
# --proxy-server=http://127.0.0.1:18080 (set in agent/cdp-bridge).
if ! _running "[l]ocal-proxy.py"; then
  python3 "$BASE/agent/local-proxy.py" >/tmp/musebrowser-proxy.log 2>&1 &
  sleep 1
fi

# --- chromium via cdp-bridge (NOT launched directly) ---
# Headed Chrome-for-Testing never binds a TCP --remote-debugging-port, so the
# bridge spawns chromium with --remote-debugging-pipe and serves the DevTools
# HTTP+WS surface on $CDP_PORT (localhost only). The Cloudflare Access gate
# in front of the tunnel is the auth — never expose 9222 directly.
if ! _running "[c]dp-bridge"; then
  "$BASE/agent/cdp-bridge" --chrome "$CHROMIUM_BIN" --profile "$PROFILE" \
    --display=$DISPLAY_NUM --port=$CDP_PORT \
    >/tmp/musebrowser-bridge.log 2>&1 &
fi

# --- agent control API ("our hands"): HTTP on $AGENT_PORT, localhost only ---
if ! _running "[m]b serve"; then
  "$BASE/agent/mb" serve --port $AGENT_PORT \
    >/tmp/musebrowser-agent.log 2>&1 &
  sleep 1
fi

sleep 2
echo "musebrowser stack ($CHROMIUM_BIN):"
for pid in $(_pids "[X]vnc $DISPLAY_NUM|[w]ebsockify.*$WEB_PORT|[c]dp-bridge|[m]b serve"); do
  ps -p "$pid" -o args= 2>/dev/null | sed 's/^/  /' | cut -c1-160
done
curl -s -o /dev/null -w "noVNC web UI: HTTP %{http_code} on :$WEB_PORT\n" http://127.0.0.1:$WEB_PORT/
curl -s -o /dev/null -w "agent API: HTTP %{http_code} on :$AGENT_PORT\n" http://127.0.0.1:$AGENT_PORT/healthz
