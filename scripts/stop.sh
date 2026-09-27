#!/usr/bin/env bash
# Stop the musebrowser stack. (Bracket trick: don't match our own cmdline.)
pkill -f "[c]hromium.*musebrowser" 2>/dev/null || true
pkill -f "[w]ebsockify.*6080" 2>/dev/null || true
pkill -f "[x]11vnc.*-rfbport 5900" 2>/dev/null || true
pkill -f "[o]penbox" 2>/dev/null || true
pkill -f "[X]vfb :99" 2>/dev/null || true
echo "musebrowser stopped."
