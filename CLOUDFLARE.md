# Cloudflare setup for musebrowser

The VM side only listens on `http://127.0.0.1:6080`. Everything public goes
through a Cloudflare Tunnel + Access app. Steps below use the `cf-tunnel` /
`cf-access` CLIs (Cloudflare API), but the dashboard works the same.

## 1. Tunnel

```bash
TID=$(cf-tunnel create musebrowser | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
cf-tunnel token $TID > tunnel-token.txt          # keep secret, never commit
cf-tunnel ingress $TID musebrowser.example.com http://127.0.0.1:6080
```

Run the connector on the VM (background, survives as long as the VM does):

```bash
cloudflared tunnel --no-autoupdate run --token "$(cat tunnel-token.txt)"
```

Or with a config file (`cloudflared.example.yml` in this repo) + a credentials
file from `cloudflared tunnel login`.

## 2. DNS

```bash
cf-tunnel dns <zone-name> musebrowser.example.com $TID
# creates proxied CNAME -> <tunnel-id>.cfargotunnel.com
```

## 3. Access (Zero Trust)

Lock it to specific people — a browser profile is sensitive (cookies = sessions).

```bash
APP=$(cf-access app-create musebrowser musebrowser.example.com \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
cf-access policy-add $APP you@example.com
```

Login methods (Settings > Authentication, or API):
- **One-time PIN** — zero setup, email gets a code. API quirk: the
  identity-providers POST *requires* `"config": {}` in the body, otherwise it
  fails with a misleading `unexpected end of JSON input`.
- **Google** — needs your own OAuth client ID + secret from Google Cloud
  Console (Cloudflare rejects `type: google` without them).

## 4. Verify

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://musebrowser.example.com/
# 302 -> Access login   (good: gate is working)
# 200                   (only after logging in through Access)
```

## 5. Agent API ingress (optional)

The agent API (`agent/mb serve`, `127.0.0.1:9280`) is localhost-only. If
musebrowser runs on a box the agent can't reach directly, add a second
ingress on the same tunnel behind the same Access gate:

```bash
cf-tunnel ingress $TID api.musebrowser.example.com http://127.0.0.1:9280
cf-tunnel dns <zone-name> api.musebrowser.example.com $TID
# then add api.musebrowser.example.com to the Access app (or a second app)
```

Set `MB_TOKEN` on the box before `start.sh` so `/api/*` requires
`Authorization: Bearer <token>` — whoever reaches the API inherits the
browser profile's sessions, so treat the token like a password.
