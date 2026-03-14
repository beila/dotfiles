#!/bin/bash
# System-level dependencies that can't be managed by Home Manager.
# Run this on a new machine before `home-manager switch`.
set -xeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

sudo apt install -y \
  ibus-hangul \
  input-remapper \
  gnome-session-flashback

# GNOME + XMonad session
sudo cp "$SCRIPT_DIR/../xwindow/gnome-xmonad.desktop" /usr/share/xsessions/
sudo cp "$SCRIPT_DIR/../xwindow/gnome-flashback-xmonad.session" /usr/share/gnome-session/sessions/
sudo cp "$SCRIPT_DIR/../xwindow/xmonad.desktop" /usr/share/applications/

# keyd: system-level key remapping (replaces xmodmap)
sudo mkdir -p /etc/keyd
sudo cp "$SCRIPT_DIR/../keyd/"*.conf /etc/keyd/
sudo tee /etc/systemd/system/keyd.service > /dev/null <<EOF
[Unit]
Description=key remapping daemon
After=local-fs.target

[Service]
Type=simple
ExecStart=$HOME/.nix-profile/bin/keyd
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now keyd

# ollama: local LLM server (for commit message generation etc.)
if ! command -v ollama &>/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi
ollama list 2>/dev/null | grep -q qwen2.5-coder:3b || ollama pull qwen2.5-coder:3b
