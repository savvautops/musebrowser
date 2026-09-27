#!/usr/bin/env bash
# Install everything musebrowser needs on Debian/Ubuntu.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq xvfb x11vnc websockify novnc openbox chromium
echo "musebrowser deps installed."
