#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME=$(whoami)

echo "Setting up Kensington mouse udev rules..."

# Create systemd user services
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/kensington-connect.service << EOF
[Unit]
Description=Kensington Mouse Connected

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/kenleft
EOF

cat > ~/.config/systemd/user/kensington-disconnect.service << EOF
[Unit]
Description=Kensington Mouse Disconnected

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/resetmouse
EOF

systemctl --user daemon-reload

# Create disconnect trigger script
sudo tee /usr/local/bin/kensington-disconnect-trigger.sh > /dev/null << EOF
#!/bin/bash
/bin/systemctl --user --machine=${USERNAME}@.host start kensington-disconnect.service
EOF

sudo chmod +x /usr/local/bin/kensington-disconnect-trigger.sh

# Create udev rule
sudo tee /etc/udev/rules.d/99-kensington-mouse.rules > /dev/null << 'EOF'
# Kensington Expert Wireless Trackball
ACTION=="add", SUBSYSTEM=="input", ENV{ID_VENDOR_ID}=="047d", ENV{ID_MODEL_ID}=="8018", ENV{ID_INPUT_MOUSE}=="1", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="kensington-connect.service"
ACTION=="remove", SUBSYSTEM=="input", ENV{ID_VENDOR_ID}=="047d", ENV{ID_MODEL_ID}=="8018", ENV{ID_INPUT_MOUSE}=="1", RUN+="/usr/local/bin/kensington-disconnect-trigger.sh"
EOF

# Reload udev rules
sudo udevadm control --reload-rules

echo "Setup complete! Disconnect and reconnect your Kensington mouse to test."
