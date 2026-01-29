#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up Kensington mouse udev rules..."

# Create handler script
sudo tee /usr/local/bin/kensington-handler.sh > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/ANT.AMAZON.COM/hojin/.Xauthority

if [ "$ACTION" = "add" ]; then
    echo "$(date): kenleft triggered by udev" >> /tmp/kensington-debug.log
    /home/ANT.AMAZON.COM/hojin/.dotfiles/xwindow/bin/kenleft
elif [ "$ACTION" = "remove" ]; then
    echo "$(date): resetmouse triggered by udev" >> /tmp/kensington-debug.log
    /home/ANT.AMAZON.COM/hojin/.dotfiles/xwindow/bin/resetmouse
fi
EOF

sudo chmod +x /usr/local/bin/kensington-handler.sh

# Create udev rule
sudo tee /etc/udev/rules.d/99-kensington-mouse.rules > /dev/null << 'EOF'
# Kensington Expert Wireless Trackball
ACTION=="add|remove", SUBSYSTEM=="input", ENV{ID_VENDOR_ID}=="047d", ENV{ID_MODEL_ID}=="8018", ENV{ID_INPUT_MOUSE}=="1", RUN+="/usr/local/bin/kensington-handler.sh"
EOF

# Reload udev rules
sudo udevadm control --reload-rules

echo "Setup complete! Disconnect and reconnect your Kensington mouse to test."
echo "Check /tmp/kensington-debug.log to verify it's working."
