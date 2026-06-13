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

  # Map X11 keycodes 198/202 → F20/F24 keysyms for neovide's Super+C/V path.
  # Patches the rule file directly because setxkbmap (called by ibus engine
  # switches) wipes any xmodmap override. Idempotent.
  INET=/usr/share/X11/xkb/symbols/inet
  if [ -f "$INET" ] && grep -q '<FK20>.*XF86AudioMicMute' "$INET"; then
    sudo sed -i.dotfiles-bak \
      -e 's|key <FK20>   {      \[ XF86AudioMicMute      \]       };|key <FK20>   {      [ F20                   ]       };  // dotfiles|' \
      "$INET"
    if ! grep -q '<FK24>.*F24' "$INET"; then
      sudo sed -i \
        '/key <FK20>.*F20.*dotfiles/a\    key <FK24>   {      [ F24                   ]       };  // dotfiles' \
        "$INET"
    fi
    # Apply to the live session.
    setxkbmap "$(setxkbmap -query | awk '/^layout:/{print $2}')" 2>/dev/null || true
  fi
fi

# keyd: system-level key remapping (skip on headless machines)
if [ -d /dev/input ]; then
  sudo mkdir -p /etc/keyd
  sudo cp "$SCRIPT_DIR/../keyd/"*.conf /etc/keyd/
  # `common` is included by every *.conf via keyd's `include` directive but
  # has no .conf extension, so it's not caught by the glob above.
  sudo cp "$SCRIPT_DIR/../keyd/common" /etc/keyd/
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

# adb/fastboot over USB: udev rule so the debug bridge (running as $USER) can
# open the device node, which is otherwise root-owned 0664. Matches on the USB
# interface class rather than any vendor id: ff/42/01 is adb, ff/42/03 is
# fastboot, so ff42?? covers both modes (a device re-enumerates when it reboots
# into the bootloader). uaccess tags it for the active-session user via ACLs.
if [ -d /dev/bus/usb ]; then
  sudo tee /etc/udev/rules.d/51-android.rules > /dev/null <<'EOF'
# Managed by home-manager/system-deps.sh — adb + fastboot device access.
SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:ff42??:*", MODE="0660", TAG+="uaccess"
EOF
  sudo udevadm control --reload-rules
  sudo udevadm trigger
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
