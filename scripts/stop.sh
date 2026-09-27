#!/usr/bin/env bash
# Stop the musebrowser stack.
pkill -f "chromium.*musebrowser" 2>/dev/null || true
pkill -f "websockify.*6080" 2>/dev/null || true
pkill -f "x11vnc.*-rfbport 5900" 2>/dev/null || true
pkill -f "openbox" 2>/dev/null || true
pkill -f "Xvfb :99" 2>/dev/null || true
echo "musebrowser stopped."
