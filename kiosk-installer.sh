#!/bin/bash

# be new
apt-get update

# get software
apt-get install \
    unclutter \
    xorg \
    chromium \
    openbox \
    lightdm \
    locales \
    xdotool \
    -y

# dir
mkdir -p /home/kiosk/.config/openbox

# create group
groupadd -f kiosk

# create user if not exists
id -u kiosk &>/dev/null || useradd -m kiosk -g kiosk -s /bin/bash 

# rights
chown -R kiosk:kiosk /home/kiosk

# remove virtual consoles
if [ -e "/etc/X11/xorg.conf" ]; then
  mv /etc/X11/xorg.conf /etc/X11/xorg.conf.backup
fi
cat > /etc/X11/xorg.conf << EOF
Section "ServerFlags"
    Option "DontVTSwitch" "true"
EndSection
EOF

# create config
if [ -e "/etc/lightdm/lightdm.conf" ]; then
  mv /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
fi
cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
xserver-command=X -nocursor -nolisten tcp
autologin-user=kiosk
autologin-session=openbox
EOF

# create autostart
if [ -e "/home/kiosk/.config/openbox/autostart" ]; then
  mv /home/kiosk/.config/openbox/autostart /home/kiosk/.config/openbox/autostart.backup
fi

KIOSK_URL="https://www.example.com/"

cat > /home/kiosk/.config/openbox/autostart << EOF
#!/bin/bash

# Wait for the Openbox session to start
sleep 1

# Disable X.org screensaver and power management
xset s noblank
xset s off
xset -dpms


# Hide the mouse cursor after a period of inactivity
unclutter -idle 0.1 -grab -root &

# Start a background loop to refresh Chromium every hour (3600 seconds)
# NOTE: The refresh interval can be adjusted here.
(
  while true; do
    sleep 900
    # Find the Chromium window and send a Ctrl+F5 keypress
    xdotool search --onlyvisible --class "chromium" windowactivate key "ctrl+F5"
  done
) &

while :
do
  xrandr --auto
  chromium \
    --noerrdialogs \
    --no-memcheck \
    --no-first-run \
    --start-maximized \
    --disable \
    --disable-translate \
    --disable-infobars \
    --disable-suggestions-service \
    --disable-save-password-bubble \
    --disable-session-crashed-bubble \
    --kiosk-idle-timeout-ms=0 \
    --kiosk
    "$KIOSK_URL"
  sleep 5
done &
EOF

echo "Done!"
