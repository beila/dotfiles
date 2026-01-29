#!/bin/bash
echo "$(date): Handler called with ACTION=$ACTION" >> /tmp/kensington-debug.log 2>&1
export DISPLAY=:0
export XAUTHORITY=/home/ANT.AMAZON.COM/hojin/.Xauthority

if [ "$ACTION" = "add" ]; then
    echo "$(date): kenleft triggered by udev" >> /tmp/kensington-debug.log
    /home/ANT.AMAZON.COM/hojin/.dotfiles/xwindow/bin/kenleft
elif [ "$ACTION" = "remove" ]; then
    echo "$(date): resetmouse triggered by udev" >> /tmp/kensington-debug.log
    /home/ANT.AMAZON.COM/hojin/.dotfiles/xwindow/bin/resetmouse
fi
