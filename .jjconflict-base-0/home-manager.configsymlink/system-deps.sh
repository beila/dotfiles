#!/bin/bash
# System-level dependencies that can't be managed by Home Manager.
# Run this on a new machine before `home-manager switch`.
set -xeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Set pretty hostname for this machine (used by sync scripts for branch names)
CURRENT=$(hostnamectl --pretty 2>/dev/null)
if [ -z "$CURRENT" ] || echo "$CURRENT" | grep -q '\.'; then
    read -rp "Enter a pretty hostname for this machine [current: ${CURRENT:-<not set>}]: " PRETTY_NAME
    [ -n "$PRETTY_NAME" ] && sudo hostnamectl set-hostname --pretty "$PRETTY_NAME"
fi

# Detect package manager (prefer dnf/yum on Amazon Linux even if apt exists)
if command -v dnf &>/dev/null; then
  PKG_INSTALL="sudo dnf install -y"
elif command -v yum &>/dev/null; then
  PKG_INSTALL="sudo yum install -y"
elif command -v apt-get &>/dev/null; then
  PKG_INSTALL="sudo apt-get install -y"
else
  echo "No supported package manager found" >&2
  exit 1
fi

# GNOME-specific setup (skip on headless/non-GNOME machines)
if command -v gnome-session &>/dev/null; then
  $PKG_INSTALL \
    gnome-screensaver \
    ibus-hangul \
    gnome-session-flashback

  # GNOME + XMonad session
  sudo cp "$SCRIPT_DIR/../xwindow/gnome-xmonad.desktop" /usr/share/xsessions/
  sudo cp "$SCRIPT_DIR/../xwindow/gnome-flashback-xmonad.session" /usr/share/gnome-session/sessions/
  sudo cp "$SCRIPT_DIR/../xwindow/xmonad.desktop" /usr/share/applications/
fi

# keyd: system-level key remapping (skip on headless machines)
if [ -d /dev/input ]; then
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
fi

# linger: keep systemd --user alive after logout so zellij servers,
# sync timers, and other user services survive GNOME session restarts.
# Without this, logging out stops the user manager and kills all children.
sudo loginctl enable-linger "$USER"

# ollama: installed via nix (home.nix), pull model if missing
if command -v ollama &>/dev/null && ! ollama list 2>/dev/null | grep -q qwen2.5-coder:3b; then
  ollama serve &>/dev/null & ollama_pid=$!
  until curl -sf http://localhost:11434/api/tags &>/dev/null; do sleep 0.1; done
  ollama pull qwen2.5-coder:3b
  kill $ollama_pid 2>/dev/null
fi
