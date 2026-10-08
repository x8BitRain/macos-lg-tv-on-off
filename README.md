# lg-tv-wake

Turns an LG webOS TV on when a Mac wakes, and off when it locks or sleeps.

Macs can't send HDMI-CEC, so this uses a direct Ethernet cable to the TV instead.

## Physical setup

```
Mac --HDMI--> TV
Mac --Ethernet--> TV LAN port
```

Connect your TV via ethernet directly to the mac (I did it this way instead of over Wifi because I never want my TV to access the internet)

No router needed.

## TV settings

- Quick Start+: on
- Mobile TV On > Turn on via Wi-Fi: on (also covers wired)
- Wired network, manual IP: `192.168.77.2`, mask `255.255.255.0`, gateway `192.168.77.1`
- Note the wired MAC address (Settings > General > About This TV)

## Install

```
./setup.sh
```

Asks for the adapter interface and TV MAC, sets the adapter's IP, builds the watcher, and pairs with the TV (accept the prompt on the TV once). Needs Xcode Command Line Tools.

## Behavior

| Mac | TV |
|---|---|
| Wake, screen wake, unlock | On (Wake-on-LAN) |
| Lock | Off, and the display sleeps so a key press brings the TV back |
| Screen sleep (including Escape at lock screen) | Off |
| Sleep | Off |

Log: `~/Library/Logs/lg-tv-wake.log`

## Manual control

```
python3 ~/.lg-tv-wake/tvctl.py on|off|status|pair
```

## Uninstall

```
./uninstall.sh
```
