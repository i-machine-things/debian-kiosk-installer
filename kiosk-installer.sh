#!/bin/bash

#run this script as root or sudo

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
    Option "DontVTSwitch" "false"
EndSection
EOF

# create configs
if [ -e "/etc/lightdm/lightdm.conf" ]; then
  mv /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
fi
cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
xserver-command=X -nolisten tcp
autologin-user=kiosk
autologin-session=openbox
EOF

if [ -e "/home/kiosk/.config/kiosk.conf" ]; then
  mv /home/kiosk/.config/kiosk.conf
fi
cat > /home/kiosk/.config/kiosk.conf << EOF
"www.example.com"
EOF

# create autostart

if [ -e "/home/kiosk/.config/openbox/autostart" ]; then
  mv /home/kiosk/.config/openbox/autostart /home/kiosk/.config/openbox/autostart.backup
fi

cat > /home/kiosk/.config/openbox/autostart << EOF
#!/bin/bash

CONFIG_FILE="/home/kiosk/.config/kiosk.conf"

options=(
    "Armbian Login"
    "Kiosk Mode"
    "Change Kiosk url"
)


# Display menu
echo "Please choose an option:"
for i in "${!options[@]}"; do
    printf "%d) %s\n" $((i+1)) "${options[$i]}"
done

# Get user input
while true; do
    read -p "Enter your choice [1-${#options[@]}]: " choice
    
    # Validate input
    if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#options[@]} ]; then
        break
    else
        echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
    fi
done

# Process selection
selected="${options[$((choice-1))]}"
echo "You selected: $selected"

# Add your action handling below
case $choice in
    1)
        echo "Exiting to Armbian Login"
        exit 0
        ;;
    2)
        echo "Continueing to Kiosk Mode"
        ;;
    3)
        echo "Current URL: $(cat $CONFIG_FILE)"
        read -p "Enter new URL: " new_url
        if [ -n "$new_url" ]; then
            echo "$new_url" > "$CONFIG_FILE"
            echo "URL updated successfully"
            # Optional: add command to restart Chromium here
        else
            echo "URL cannot be empty"
        fi
        ;;
    #*)
    #    echo "No action defined for this option"
    #    ;;
esac

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
    --kiosk \
    "$(cat $CONFIG_FILE)"&
  sleep 5
done &
EOF

echo "Done!"
