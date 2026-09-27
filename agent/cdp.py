#!/usr/bin/env python3
"""Minimal stdlib-only Chrome DevTools Protocol client.

Talks to Chromium's DevTools HTTP endpoint (default http://127.0.0.1:9222),
lists page targets, and speaks CDP over a minimal WebSocket implementation
built on stdlib sockets — no third-party dependencies.
"""

import base64
import hashlib  # noqa: F401  (kept: documents the WS handshake components)
import json
import os
import select
import socket
import struct
import time
import urllib.parse
import urllib.request


class CDPError(RuntimeError):
    pass


# ------------------------------------------------------------- WebSocket

def _ws_handshake(host, port, path):
    s = socket.create_connection((host, port), timeout=10)
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    s.sendall(req.encode("ascii"))
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            s.close()
            raise CDPError("websocket handshake: connection closed")
        buf += chunk
    status_line = buf.split(b"\r\n", 1)[0].decode("latin1")
    if "101" not in status_line:
        s.close()
        raise CDPError(f"websocket handshake failed: {status_line}")
    rest = buf.split(b"\r\n\r\n", 1)[1]
    return s, rest


class WSConnection:
    def __init__(self, sock, rest=b""):
        self.sock = sock
        self.buf = rest

    def _recv_exact(self, n, deadline):
        while len(self.buf) < n:
            timeout = deadline - time.time()
            if timeout <= 0:
                raise CDPError("websocket read timeout")
            r, _, _ = select.select([self.sock], [], [], timeout)
            if not r:
                raise CDPError("websocket read timeout")
            chunk = self.sock.recv(65536)
            if not chunk:
                raise CDPError("websocket closed by peer")
            self.buf += chunk
        data, self.buf = self.buf[:n], self.buf[n:]
        return data

    def send_text(self, text):
        payload = text.encode("utf-8")
        n = len(payload)
        header = bytearray([0x81])  # FIN + text opcode
        if n < 126:
            header.append(0x80 | n)
        elif n < 0x10000:
            header.append(0x80 | 126)
            header += struct.pack(">H", n)
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", n)
        mask = os.urandom(4)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + masked)

    def recv_text(self, timeout=30):
        deadline = time.time() + timeout
        message = bytearray()
        while True:
            hdr = self._recv_exact(2, deadline)
            fin = hdr[0] & 0x80
            opcode = hdr[0] & 0x0F
            masked = hdr[1] & 0x80
            length = hdr[1] & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._recv_exact(2, deadline))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._recv_exact(8, deadline))[0]
            mask = self._recv_exact(4, deadline) if masked else None
            payload = self._recv_exact(length, deadline)
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            if opcode == 0x8:  # close
                raise CDPError("websocket closed by peer")
            if opcode == 0x9:  # ping -> pong
                self.sock.sendall(bytes([0x8A, len(payload)]) + payload)
                continue
            if opcode in (0x0, 0x1, 0x2):  # continuation / text / binary
                message += payload
                if fin:
                    return bytes(message).decode("utf-8")
                continue
            # ignore anything else

    def close(self):
        try:
            self.sock.sendall(bytes([0x88, 0x80]) + os.urandom(4))  # masked close
        except OSError:
            pass
        self.sock.close()


# ------------------------------------------------------------------- CDP

def devtools_http(host, port, path, timeout=10):
    url = f"http://{host}:{port}{path}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def list_targets(host="127.0.0.1", port=9222):
    try:
        return devtools_http(host, port, "/json/list")
    except Exception as e:
        raise CDPError(
            f"cannot reach DevTools at {host}:{port} "
            f"(is the stack running? ./scripts/start.sh): {e}"
        )


def browser_ws_url(host="127.0.0.1", port=9222):
    try:
        return devtools_http(host, port, "/json/version")["webSocketDebuggerUrl"]
    except Exception as e:
        raise CDPError(
            f"cannot reach DevTools at {host}:{port} "
            f"(is the stack running? ./scripts/start.sh): {e}"
        )


class Session:
    """One CDP session attached to a page (or the browser) target."""

    def __init__(self, ws_url):
        parts = urllib.parse.urlsplit(ws_url)
        host = parts.hostname or "127.0.0.1"
        port = parts.port or 80
        path = parts.path + ("?" + parts.query if parts.query else "")
        sock, rest = _ws_handshake(host, port, path)
        self.ws = WSConnection(sock, rest)
        self._id = 0

    def call(self, method, params=None, timeout=30):
        self._id += 1
        msg_id = self._id
        self.ws.send_text(json.dumps({"id": msg_id, "method": method,
                                     "params": params or {}}))
        deadline = time.time() + timeout
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                raise CDPError(f"CDP call timed out: {method}")
            data = json.loads(self.ws.recv_text(timeout=remaining))
            if data.get("id") == msg_id:
                if "error" in data:
                    raise CDPError(f"CDP {method}: {data['error']}")
                return data.get("result", {})
            # otherwise it's an event — ignore

    def close(self):
        self.ws.close()


def connect_page(host="127.0.0.1", port=9222, index=0):
    targets = [t for t in list_targets(host, port) if t.get("type") == "page"]
    if not targets:
        raise CDPError("no page targets open")
    if index < 0 or index >= len(targets):
        raise CDPError(f"tab index {index} out of range (0..{len(targets) - 1})")
    return Session(targets[index]["webSocketDebuggerUrl"]), targets[index]


def connect_browser(host="127.0.0.1", port=9222):
    return Session(browser_ws_url(host, port))
