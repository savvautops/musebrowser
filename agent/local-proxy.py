#!/usr/bin/env python3
"""Local forward proxy for musebrowser's Chrome.

Listens on 127.0.0.1:18080 (no auth) and forwards everything to the
sandbox egress proxy, adding Proxy-Authorization from the environment.
Chrome gets --proxy-server=http://127.0.0.1:18080 so it can reach the
public internet. Localhost-only: never expose this port.
"""
import base64
import os
import socket
import threading
import urllib.parse

LISTEN = ("127.0.0.1", 18080)
BUF = 65536


def _upstream():
    # https_proxy=http://user:pass@host:port
    u = os.environ.get("https_proxy") or os.environ.get("http_proxy", "")
    p = urllib.parse.urlparse(u)
    creds = f"{urllib.parse.unquote(p.username or '')}:{urllib.parse.unquote(p.password or '')}"
    auth = base64.b64encode(creds.encode()).decode()
    return p.hostname, p.port or 3128, auth


def _relay(a, b):
    try:
        while True:
            d = a.recv(BUF)
            if not d:
                break
            b.sendall(d)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            s.close()


def _handle(client):
    up_host, up_port, auth = _upstream()
    try:
        # read request head
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = client.recv(4096)
            if not chunk:
                client.close()
                return
            head += chunk
            if len(head) > 65536:
                client.close()
                return
        header, _, rest = head.partition(b"\r\n\r\n")
        lines = header.decode("latin1").split("\r\n")
        method, target, _ = lines[0].split(" ", 2)

        up = socket.create_connection((up_host, up_port), timeout=20)
        if method.upper() == "CONNECT":
            # tunnel: forward CONNECT with auth, then relay raw bytes
            up.sendall(f"CONNECT {target} HTTP/1.1\r\n"
                       f"Host: {target}\r\n"
                       f"Proxy-Authorization: Basic {auth}\r\n"
                       f"Proxy-Connection: keep-alive\r\n\r\n".encode())
            resp = b""
            while b"\r\n\r\n" not in resp:
                chunk = up.recv(4096)
                if not chunk:
                    client.close()
                    up.close()
                    return
                resp += chunk
            status = resp.decode("latin1").split("\r\n", 1)[0]
            if " 200" not in status:
                client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
                client.close()
                up.close()
                return
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            if rest:
                up.sendall(rest)
        else:
            # plain HTTP: rewrite request line to absolute URI, inject auth
            if not target.startswith("http"):
                host = next((l[6:] for l in lines[1:]
                             if l.lower().startswith("host: ")), "")
                target = f"http://{host}{target}"
            out = [f"{method} {target} HTTP/1.1"]
            for l in lines[1:]:
                if l.lower().startswith("proxy-authorization:"):
                    continue
                out.append(l)
            out.append(f"Proxy-Authorization: Basic {auth}")
            out.append("Connection: close")
            up.sendall(("\r\n".join(out) + "\r\n\r\n").encode() + rest)
        t = threading.Thread(target=_relay, args=(client, up), daemon=True)
        t.start()
        _relay(up, client)
        t.join()
    except Exception:
        try:
            client.close()
        except OSError:
            pass


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(LISTEN)
    srv.listen(64)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=_handle, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()
