#!/usr/bin/env bash
# Install everything musebrowser needs on Debian/Ubuntu.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq xvfb x11vnc websockify novnc openbox
# NOTE (Ubuntu 24.04): the 'chromium' deb is a snap stub that won't run here.
# Use Playwright's bundled Chromium instead (real open-source Chromium build):
python3 -m pip install playwright && python3 -m playwright install --with-deps chromium
echo "musebrowser deps installed."
