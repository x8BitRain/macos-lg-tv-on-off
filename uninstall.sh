#!/bin/zsh
LABEL=com.lgtvwake.watcher
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null
rm -f ~/Library/LaunchAgents/$LABEL.plist
rm -rf ~/.lg-tv-wake
echo "Removed. The Ethernet adapter keeps its manual IP."
