#!/usr/bin/env bash
# Install everything musebrowser needs on Debian/Ubuntu.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
# PREFERRED: TigerVNC (Xvnc) ships in the base image on Hatch VMs — no install needed.
# Everything else goes to $HOME (apt installs outside $HOME can disappear):
python3 -m pip install --user --break-system-packages websockify vncdotool
# Chromium: Playwright's bundle (Ubuntu 24.04's 'chromium' deb is a snap stub).
# NOTE: the in-tool downloader stalls on big files here — download the zip with curl:
#   curl -L --retry 20 --retry-all-errors -C - -o chrome-linux64.zip \
#     https://cdn.playwright.dev/builds/cft/<ver>/linux64/chrome-linux64.zip
#   unzip, move to ~/.cache/ms-playwright/chromium-<ver>/chrome-linux/
# noVNC static files: apt install novnc if you want them, or copy from anywhere
# Agent control (agent/mb) needs nothing extra: python3 stdlib only.
echo "musebrowser deps installed."
