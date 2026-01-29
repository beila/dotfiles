#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up Kensington mouse udev rules..."

# Make handler script executable
chmod +x "$SCRIPT_DIR/kensington-handler.sh"

# Create udev rule
sudo tee /etc/udev/rules.d/99-kensington-mouse.rules > /dev/null << EOF
# Kensington Expert Wireless Trackball
ACTION=="add|remove", SUBSYSTEM=="input", ENV{ID_VENDOR_ID}=="047d", ENV{ID_MODEL_ID}=="8018", ENV{ID_INPUT_MOUSE}=="1", RUN+="$SCRIPT_DIR/kensington-handler.sh"
EOF

# Reload udev rules
sudo udevadm control --reload-rules

echo "Setup complete! Disconnect and reconnect your Kensington mouse to test."
echo "Check /tmp/kensington-debug.log to verify it's working."
