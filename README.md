# musebrowser

A self-hosted, web-accessible Chromium with a persistent profile — noVNC in
front of a real Chromium running under Xvnc, exposed to the internet through
a Cloudflare Tunnel and locked down with Cloudflare Access (only allowlisted
emails get in).

Live instance: `https://musebrowser.nano-nodes.com` (behind Access login).

## Our hands

The same Chromium is drivable two ways, on the same tabs and the same
persistent profile:

- **Human** — open the URL, drive the desktop through noVNC.
- **Agent** — `agent/mb` CLI or the HTTP API on `127.0.0.1:9280`
  (see `agent/README.md`): `tabs goto click fill type press shot text eval…`

Sign in once in the profile and it stays signed in — for both of you.

## Architecture

```
internet --TLS--> Cloudflare edge --Access check--> cloudflared (tunnel)
    --> http://127.0.0.1:6080 (websockify + noVNC)
    --> VNC :5900 (Xvnc, localhost only, no password: Access is the auth)
    --> Chromium (persistent ./profile)
            ^
            +-- agent/cdp-bridge: spawns Chromium with --remote-debugging-pipe
                (headed CfT never binds a TCP debug port) and serves the
                DevTools HTTP+WS surface on 127.0.0.1:9222 (localhost only)
                +-- agent/mb CLI / HTTP API :9280 (localhost only)
```

All of 5900/6080/9222/9280 bind localhost only. The only ingress is the
Cloudflare tunnel behind Access. Do not expose those ports directly.

## Quick start (fresh Debian/Ubuntu VM)

```bash
sudo ./scripts/install.sh
./scripts/start.sh            # Xvnc, websockify, chromium, agent API
./scripts/ensure-up.sh        # watchdog: restarts anything that died (cron-friendly)
```

Then wire up Cloudflare (see CLOUDFLARE.md): create a tunnel whose ingress
points at `http://127.0.0.1:6080`, add the DNS CNAME, and put an Access app
with an Allow policy in front of it.

## Files

- `scripts/install.sh` — deps into $HOME: pip websockify, Playwright chromium
  (Ubuntu 24.04's `chromium` deb is a snap stub — don't use it)
- `scripts/start.sh` — launches the whole stack; idempotent, safe to re-run
- `scripts/stop.sh` — stops the stack
- `scripts/ensure-up.sh` — starts whatever isn't running (for cron/watchdog)
- `agent/mb` — agent control CLI (stdlib only, no pip packages)
- `agent/cdp.py` — minimal stdlib Chrome DevTools Protocol client (HTTP + WS)
- `agent/cdp-bridge` — spawns headed Chromium on `--remote-debugging-pipe`
  and serves the DevTools surface on 127.0.0.1:9222 (headed CfT won't bind
  a TCP debug port, so the pipe is the transport)
- `agent/README.md` — CLI + HTTP API reference
- `cloudflared.example.yml` — example tunnel config (bring your own credentials file)
- `CLOUDFLARE.md` — tunnel + DNS + Access setup notes

## Notes

- VNC has no password on purpose: it only listens on 127.0.0.1 and the only
  ingress is the Cloudflare tunnel behind Access. Do not expose 5900/6080 directly.
- Chromium profile lives in `./profile` (next to the scripts) so sessions
  survive restarts. Treat that profile as sensitive — whoever opens the page
  (or reaches the agent API) inherits its cookies.
- noVNC auto-connects: opening the root URL drops you straight into the desktop.
- The agent API binds `127.0.0.1:9280`. Set `MB_TOKEN` before `start.sh` to
  require a bearer token on `/api/*`. For remote agent access (browser on a
  box the agent can't reach directly), add a second tunnel ingress for 9280 —
  see CLOUDFLARE.md §5.
