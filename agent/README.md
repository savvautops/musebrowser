# agent/ — drive musebrowser like an agent ("our hands")

The same Chromium the human drives through noVNC is also drivable by an
agent through Chrome DevTools Protocol. Same tabs, same persistent profile,
same cookies — whoever acts, both see it.

## How it works

`scripts/start.sh` launches `agent/cdp-bridge`, which spawns Chromium headed
on the Xvnc display. Headed Chrome-for-Testing never binds a TCP
`--remote-debugging-port`, so the bridge uses `--remote-debugging-pipe`
(Chrome reads CDP on fd 3, writes on fd 4) and serves the classic DevTools
HTTP + WebSocket surface on `127.0.0.1:9222` — localhost only, same as VNC.
The Cloudflare Access gate in front of the tunnel is the auth.

On top of that:

- **`mb`** — CLI control. Stdlib only, no pip packages. Talks to the bridge
  exactly as if Chrome had opened the DevTools port itself.
- **`mb serve`** — HTTP API on `127.0.0.1:9280` (started automatically by
  `start.sh`). Same ops as the CLI, as JSON.

## CLI

```bash
agent/mb tabs                                # list open tabs
agent/mb goto https://example.com            # navigate tab 0, wait for load
agent/mb shot /tmp/page.png                  # screenshot tab 0
agent/mb shot --full /tmp/full.png           # full-page screenshot
agent/mb text                                # visible text of tab 0
agent/mb click "button.submit"               # click a CSS selector
agent/mb fill "#search" "pixel sorting"      # set an input's value
agent/mb type "#search" "hello"              # realistic keystroke typing
agent/mb press Enter --tab 1                 # key press on tab 1
agent/mb eval "document.title"               # run JS, get the result
agent/mb wait ".results" --timeout 20        # wait for a selector
agent/mb newtab https://news.ycombinator.com
agent/mb closetab 2
agent/mb back | agent/mb forward | agent/mb reload
```

Every command prints JSON: `{"ok": true, "result": ...}` or
`{"ok": false, "error": ...}` (exit 1).

Env overrides: `MB_HOST` / `MB_PORT` (DevTools endpoint, default
`127.0.0.1:9222`).

## HTTP API

```bash
curl -s http://127.0.0.1:9280/healthz
curl -s -X POST http://127.0.0.1:9280/api/goto \
  -d '{"url":"https://example.com"}'
curl -s -X POST http://127.0.0.1:9280/api/shot \
  -d '{"path":"/tmp/page.png","full":true}'
```

Ops: `tabs goto newtab closetab back forward reload shot text click fill
type press eval wait`. Params are the CLI args as JSON keys
(`url`, `selector`, `text`, `key`, `js`, `path`, `full`, `timeout`, `tab`).

Optional bearer auth: set `MB_TOKEN` in the environment before `start.sh`
(or before `mb serve`) — then every `/api/*` call needs
`Authorization: Bearer <token>`.

## Remote agent access

The API binds `127.0.0.1` only. When musebrowser runs on a box the agent
can't reach directly, add a second tunnel ingress for port 9280 (see
`CLOUDFLARE.md` §5) behind the same Access gate — or just run the agent on
the same machine, which is the default setup.

## Security notes

- DevTools (9222) and the agent API (9280) are localhost-only by design.
  Never port-forward or proxy them without the Access gate in front.
- Whoever can reach the agent API inherits the browser profile's sessions —
  treat `MB_TOKEN` like a password if you expose it past localhost.
