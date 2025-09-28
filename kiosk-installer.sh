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
    network-manager \
    wpasupplicant \
    wireless-tools \
    xterm \
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

# Create WiFi connection check script
cat > /usr/local/bin/check-wifi.sh << 'EOF'
#!/bin/bash

# Wait for NetworkManager to start
sleep 10

# Maximum number of connection attempts
MAX_ATTEMPTS=3
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    # Check if we have an active WiFi connection by trying to ping Google DNS
    if nmcli -t -f STATE general | grep -q "connected"; then
        echo "WiFi connection detected"
        exit 0
    fi
    
    # Check if WiFi is enabled but not connected
    if nmcli -t -f TYPE,STATE dev | grep -q "wifi:disconnected"; then
        echo "WiFi enabled but not connected (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    else
        echo "No WiFi adapter found or WiFi disabled (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    fi
    
    # Wait before retry
    sleep 5
    ATTEMPT=$((ATTEMPT + 1))
done

echo "No WiFi connection after $MAX_ATTEMPTS attempts"
exit 1
EOF

chmod +x /usr/local/bin/check-wifi.sh

# Create WiFi setup script
cat > /usr/local/bin/wifi-setup.sh << 'EOF'
#!/bin/bash

# Simple WiFi setup interface using nmtui
xterm -geometry 80x24+0+0 -e "nmcli device wifi list" &
sleep 2

# Create a simple HTML page for WiFi setup
cat > /tmp/wifi-setup.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>WiFi Setup</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background: #f0f0f0;
            text-align: center;
        }
        .container { 
            background: white; 
            padding: 30px; 
            border-radius: 10px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
            max-width: 600px;
            margin: 0 auto;
        }
        h1 { color: #333; }
        .instruction { 
            background: #e7f3ff; 
            padding: 15px; 
            border-radius: 5px;
            margin: 20px 0;
            text-align: left;
        }
        .terminal {
            background: #000;
            color: #0f0;
            padding: 15px;
            border-radius: 5px;
            font-family: monospace;
            text-align: left;
            margin: 20px 0;
        }
        .button {
            background: #007cba;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
            margin: 10px;
        }
        .button:hover {
            background: #005a87;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>WiFi Setup Required</h1>
        <p>No WiFi connection detected. Please configure WiFi access.</p>
        
        <div class="instruction">
            <h3>Setup Instructions:</h3>
            <ol>
                <li>Press Alt+Tab to switch to the terminal window</li>
                <li>Run: <code>sudo nmtui</code> to launch the WiFi setup tool</li>
                <li>Configure your WiFi connection</li>
                <li>Return to this page and click "Check Connection"</li>
            </ol>
        </div>
        
        <div class="terminal">
            # Switch to terminal (Alt+Tab) and run:<br>
            # sudo nmtui<br>
            # Follow the prompts to connect to WiFi
        </div>
        
        <button class="button" onclick="location.reload()">Check Connection</button>
        <button class="button" onclick="window.open('http://www.example.com/', '_blank')">Try Main Site</button>
    </div>
</body>
</html>
HTMLEOF

# Start simple HTTP server for WiFi setup page
python3 -m http.server 8000 --directory /tmp > /tmp/http-server.log 2>&1 &
HTTP_PID=$!

# Function to cleanup on exit
cleanup() {
    kill $HTTP_PID 2>/dev/null
    pkill xterm 2>/dev/null
    exit
}
trap cleanup EXIT

# Open WiFi setup page in Chromium
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
    "http://localhost:8000/wifi-setup.html" &

# Wait for Chromium to start
sleep 5

# Keep this script running until WiFi is connected or system shuts down
while true; do
    # Check if WiFi is now connected
    if /usr/local/bin/check-wifi.sh; then
        echo "WiFi connection established! Returning to kiosk mode..."
        pkill chromium
        break
    fi
    sleep 10
done
EOF

chmod +x /usr/local/bin/wifi-setup.sh

if [ -e "/home/kiosk/.config/kiosk.conf" ]; then
  mv /home/kiosk/.config/kiosk.conf
fi
cat > /home/kiosk/.config/kiosk.conf << EOF
"www.example.com"
EOF

# Create the main kiosk launcher script
cat > /usr/local/bin/kiosk-launcher.sh << 'EOF'
#!/bin/bash

# Wait for X to start properly
sleep 5

# Disable X.org screensaver and power management
xset s noblank
xset s off
xset -dpms

# Hide the mouse cursor after a period of inactivity
unclutter -idle 0.1 -grab -root &

# Check WiFi connection first
if /usr/local/bin/check-wifi.sh; then
    echo "Starting kiosk mode with WiFi connection"
    
    # Start a background loop to refresh Chromium every 15 minutes
    (
        while true; do
            sleep 900
            # Find the Chromium window and send a Ctrl+F5 keypress
            xdotool search --onlyvisible --class "chromium" windowactivate key "ctrl+F5"
        done
    ) &

    # Main kiosk loop with WiFi
    while true; do
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
            "https://www.example.com/" &
        CHROMIUM_PID=$!
        
        # Monitor Chromium and check WiFi periodically
        while kill -0 $CHROMIUM_PID 2>/dev/null; do
            sleep 30
            # Check if WiFi is still connected
            if ! /usr/local/bin/check-wifi.sh; then
                echo "WiFi connection lost! Switching to setup mode..."
                kill $CHROMIUM_PID
                break
            fi
        done
        
        wait $CHROMIUM_PID
        sleep 2
    done
else
    echo "No WiFi connection detected. Starting WiFi setup mode."
    /usr/local/bin/wifi-setup.sh
fi
EOF

chmod +x /usr/local/bin/kiosk-launcher.sh

# Create NetworkManager configuration to enable WiFi
cat > /etc/NetworkManager/conf.d/wifi-enable.conf << 'EOF'
[device]
wifi.scan-rand-mac-address=no

[connection]
wifi.powersave=0
EOF

# Enable and start NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager

# Update autostart to use the new launcher
if [ -e "/home/kiosk/.config/openbox/autostart" ]; then
  mv /home/kiosk/.config/openbox/autostart /home/kiosk/.config/openbox/autostart.backup
fi

cat > /home/kiosk/.config/openbox/autostart << 'EOF'
#!/bin/bash

# Wait for the Openbox session to start
sleep 2

# Start the kiosk launcher
/usr/local/bin/kiosk-launcher.sh &
EOF

chmod +x /home/kiosk/.config/openbox/autostart
chown kiosk:kiosk /home/kiosk/.config/openbox/autostart

echo "Done!"
echo "System will now:"
echo "1. Check for WiFi connection on startup"
echo "2. Start kiosk mode if WiFi is connected"
echo "3. Start WiFi setup mode if no connection is detected"
echo "4. Automatically switch to setup mode if WiFi connection is lost"
