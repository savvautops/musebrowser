# musebrowser

A self-hosted, web-accessible Chromium — noVNC in front of a real Chromium
running under Xvfb, exposed to the internet through a Cloudflare Tunnel and
locked down with Cloudflare Access (only allowlisted emails get in).

Live instance: `https://musebrowser.nano-nodes.com` (behind Access login).

## Architecture

```
internet --TLS--> Cloudflare edge --Access check--> cloudflared (tunnel)
    --> http://127.0.0.1:6080 (websockify + noVNC)
    --> VNC :5900 (x11vnc) --> Xvfb :99 --> openbox --> chromium
```

## Quick start (fresh Debian/Ubuntu VM)

```bash
sudo ./scripts/install.sh
./scripts/start.sh            # launches Xvfb, openbox, x11vnc, websockify, chromium
./scripts/ensure-up.sh        # watchdog: restarts anything that died (cron-friendly)
```

Then wire up Cloudflare (see CLOUDFLARE.md): create a tunnel whose ingress
points at `http://127.0.0.1:6080`, add the DNS CNAME, and put an Access app
with an Allow policy in front of it.

## Files

- `scripts/install.sh` — apt packages: xvfb, x11vnc, websockify, novnc, openbox, chromium
- `scripts/start.sh` — launches the whole stack; idempotent-ish, safe to re-run
- `scripts/stop.sh` — stops the stack
- `scripts/ensure-up.sh` — starts whatever isn't running (for cron/watchdog)
- `cloudflared.example.yml` — example tunnel config (bring your own credentials file)
- `CLOUDFLARE.md` — tunnel + DNS + Access setup notes

## Notes

- VNC has no password on purpose: it only listens on 127.0.0.1 and the only
  ingress is the Cloudflare tunnel behind Access. Do not expose 5900/6080 directly.
- Chromium profile lives in `./profile` (next to the scripts) so sessions
  survive restarts. Treat that profile as sensitive — whoever opens the page
  inherits its cookies.
- noVNC auto-connects: opening the root URL drops you straight into the desktop.
