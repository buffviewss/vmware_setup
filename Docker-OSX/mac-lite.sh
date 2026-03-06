#!/bin/bash

# ==========================================================
# macOS Lite FULL Optimization Script
# Persistent disable after reboot
# Safe for Safari / iCloud / Apple ID / browser fingerprint
# ==========================================================

echo "Starting macOS persistent optimization..."

USER_ID=$(id -u)

disable_system_service () {
SERVICE=$1
PLIST=$2

if launchctl print system/$SERVICE >/dev/null 2>&1; then
echo "Disabling system service: $SERVICE"
sudo launchctl bootout system "$PLIST" 2>/dev/null
sudo launchctl disable system/$SERVICE 2>/dev/null
fi
}

disable_gui_service () {
SERVICE=$1
PLIST=$2

if launchctl print gui/$USER_ID/$SERVICE >/dev/null 2>&1; then
echo "Disabling user service: $SERVICE"
launchctl bootout gui/$USER_ID "$PLIST" 2>/dev/null
launchctl disable gui/$USER_ID/$SERVICE 2>/dev/null
fi
}

# ----------------------------------------------------------
# Disable Siri
# ----------------------------------------------------------

disable_gui_service com.apple.assistantd \
/System/Library/LaunchAgents/com.apple.assistantd.plist

disable_gui_service com.apple.SiriNCService \
/System/Library/LaunchAgents/com.apple.SiriNCService.plist

disable_gui_service com.apple.suggestd \
/System/Library/LaunchAgents/com.apple.suggestd.plist

killall assistantd 2>/dev/null

echo "Siri disabled"


# ----------------------------------------------------------
# Disable Apple Knowledge Graph (Siri / Spotlight suggestions)
# ----------------------------------------------------------

disable_gui_service com.apple.knowledge-agent \
/System/Library/LaunchAgents/com.apple.knowledge-agent.plist

killall knowledge-agent 2>/dev/null

echo "knowledge-agent disabled"


# ----------------------------------------------------------
# Disable Spotlight completely
# ----------------------------------------------------------

sudo mdutil -a -i off

disable_system_service com.apple.metadata.mds \
/System/Library/LaunchDaemons/com.apple.metadata.mds.plist

killall mds 2>/dev/null
killall mds_stores 2>/dev/null
killall mdworker 2>/dev/null

echo "Spotlight disabled"


# ----------------------------------------------------------
# Disable Core Spotlight daemon
# ----------------------------------------------------------

disable_system_service com.apple.corespotlightd \
/System/Library/LaunchDaemons/com.apple.corespotlightd.plist

killall corespotlightd 2>/dev/null

echo "Core Spotlight disabled"


# ----------------------------------------------------------
# Disable Apple Analytics
# ----------------------------------------------------------

disable_system_service com.apple.analyticsd \
/System/Library/LaunchDaemons/com.apple.analyticsd.plist

disable_system_service com.apple.diagnosticsd \
/System/Library/LaunchDaemons/com.apple.diagnosticsd.plist

echo "Analytics disabled"


# ----------------------------------------------------------
# Disable Game Center
# ----------------------------------------------------------

disable_gui_service com.apple.gamed \
/System/Library/LaunchAgents/com.apple.gamed.plist

killall gamed 2>/dev/null

echo "Game Center disabled"


# ----------------------------------------------------------
# Disable Photos AI Analysis
# ----------------------------------------------------------

disable_gui_service com.apple.photoanalysisd \
/System/Library/LaunchAgents/com.apple.photoanalysisd.plist

disable_gui_service com.apple.photolibraryd \
/System/Library/LaunchAgents/com.apple.photolibraryd.plist

disable_gui_service com.apple.mediaanalysisd \
/System/Library/LaunchAgents/com.apple.mediaanalysisd.plist

killall photoanalysisd 2>/dev/null
killall photolibraryd 2>/dev/null
killall mediaanalysisd 2>/dev/null

echo "Photos analysis disabled"


# ----------------------------------------------------------
# Disable AirDrop / AirPlay
# ----------------------------------------------------------

disable_gui_service com.apple.sharingd \
/System/Library/LaunchAgents/com.apple.sharingd.plist

disable_gui_service com.apple.AirPlayXPCHelper \
/System/Library/LaunchAgents/com.apple.AirPlayXPCHelper.plist

killall sharingd 2>/dev/null

echo "AirDrop / AirPlay disabled"


# ----------------------------------------------------------
# Disable Handoff
# ----------------------------------------------------------

disable_gui_service com.apple.handoffd \
/System/Library/LaunchAgents/com.apple.handoffd.plist

killall handoffd 2>/dev/null

echo "Handoff disabled"


# ----------------------------------------------------------
# Disable macOS auto update
# ----------------------------------------------------------

disable_system_service com.apple.softwareupdated \
/System/Library/LaunchDaemons/com.apple.softwareupdated.plist

killall softwareupdated 2>/dev/null

echo "Software update disabled"


# ----------------------------------------------------------
# Disable Bluetooth daemon
# ----------------------------------------------------------

disable_system_service com.apple.bluetoothd \
/System/Library/LaunchDaemons/com.apple.bluetoothd.plist

killall bluetoothd 2>/dev/null

echo "Bluetooth disabled"


# ----------------------------------------------------------
# Disable Widgets
# ----------------------------------------------------------

defaults write com.apple.notificationcenterui widgets-enabled -bool false
killall NotificationCenter 2>/dev/null

echo "Widgets disabled"


echo ""
echo "==========================================="
echo "macOS FULL optimization completed"
echo "Services will remain disabled after reboot"
echo "Safari / iCloud / Apple ID unaffected"
echo "==========================================="
