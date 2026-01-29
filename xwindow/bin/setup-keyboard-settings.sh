#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME=$(whoami)

echo "Setting up keyboard settings auto-apply..."

# Create systemd user service
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/keyboard-settings.service << EOF
[Unit]
Description=Apply Keyboard Settings

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/keyb
EOF

systemctl --user daemon-reload

# Create trigger script for remove events
sudo tee /usr/local/bin/keyboard-settings-trigger.sh > /dev/null << EOF
#!/bin/bash
/bin/systemctl --user --machine=${USERNAME}@.host start keyboard-settings.service
EOF

sudo chmod +x /usr/local/bin/keyboard-settings-trigger.sh

# Create udev rule
sudo tee /etc/udev/rules.d/90-keyboard-settings.rules > /dev/null << 'EOF'
# Apply keyboard settings on any input device change
ACTION=="add", SUBSYSTEM=="input", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="keyboard-settings.service"
ACTION=="remove", SUBSYSTEM=="input", RUN+="/usr/local/bin/keyboard-settings-trigger.sh"
EOF

# Reload udev rules
sudo udevadm control --reload-rules

echo "Setup complete! Connect/disconnect any input device to test."
