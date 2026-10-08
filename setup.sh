#!/bin/zsh
# Installs lg-tv-wake for the current user.
set -euo pipefail

REPO=${0:A:h}
DEST=~/.lg-tv-wake
LABEL=com.lgtvwake.watcher
PLIST=~/Library/LaunchAgents/$LABEL.plist

command -v swiftc >/dev/null || { echo "Install Xcode Command Line Tools: xcode-select --install"; exit 1; }

echo "Network ports:"
networksetup -listallhardwareports | awk '/Hardware Port/{p=substr($0,16)} /Device/{print "  " $2 "  " p}'
read "IFACE?Interface connected to the TV (e.g. en7): "
read "TV_MAC?TV wired MAC address (AA:BB:CC:DD:EE:FF): "
read "MAC_IP?Mac IP on that link [192.168.77.1]: "; MAC_IP=${MAC_IP:-192.168.77.1}
read "TV_IP?TV IP on that link [192.168.77.2]: "; TV_IP=${TV_IP:-192.168.77.2}

SERVICE=$(networksetup -listallhardwareports | awk -v d="$IFACE" '/Hardware Port/{p=substr($0,16)} $2==d{print p}')
[[ -n $SERVICE ]] || { echo "Unknown interface $IFACE"; exit 1; }
echo "Setting $SERVICE to $MAC_IP (may ask for your password)"
networksetup -setmanual "$SERVICE" "$MAC_IP" 255.255.255.0

mkdir -p $DEST ~/Library/LaunchAgents ~/Library/Logs
cp $REPO/src/tvctl.py $DEST/
cat > $DEST/config.json <<JSON
{"iface": "$IFACE", "tv_mac": "$TV_MAC", "mac_ip": "$MAC_IP", "tv_ip": "$TV_IP"}
JSON
swiftc -O $REPO/src/watcher.swift -o $DEST/watcher

cat > $PLIST <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key><array><string>$DEST/watcher</string></array>
	<key>LimitLoadToSessionType</key><string>Aqua</string>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
</dict>
</plist>
PL
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $PLIST

if [[ ! -f $DEST/client-key ]]; then
  echo "Turn the TV on and accept the prompt on screen."
  /usr/bin/python3 -I $DEST/tvctl.py pair
fi
echo "Done. Log: ~/Library/Logs/lg-tv-wake.log"
