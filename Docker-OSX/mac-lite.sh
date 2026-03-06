#!/bin/bash

# ==========================================================
# macOS Lite Optimization (Persistent Disable)
# These services remain disabled after reboot
# SAFE FOR:
# - Safari
# - WebGL / Canvas fingerprint
# - iCloud
# - Apple ID login
# ==========================================================

echo "Starting persistent macOS optimization..."

UID=$(id -u)

# ----------------------------------------------------------
# Disable Siri services
# ----------------------------------------------------------
# assistantd -> Siri core daemon
# SiriNCService -> Siri Notification Center integration
# suggestd -> Siri suggestions

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.assistantd.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.assistantd

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.SiriNCService.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.SiriNCService

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.suggestd.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.suggestd

echo "Siri disabled"


# ----------------------------------------------------------
# Disable Spotlight indexing and daemon
# ----------------------------------------------------------
# mds -> Spotlight metadata server
# mds_stores -> metadata storage
# mdworker -> indexing worker

sudo mdutil -a -i off

sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.metadata.mds.plist 2>/dev/null
sudo launchctl disable system/com.apple.metadata.mds

echo "Spotlight disabled"


# ----------------------------------------------------------
# Disable Apple analytics / telemetry
# ----------------------------------------------------------
# analyticsd -> Apple usage analytics
# diagnosticsd -> system diagnostics reporting

sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.analyticsd.plist 2>/dev/null
sudo launchctl disable system/com.apple.analyticsd

sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.diagnosticsd.plist 2>/dev/null
sudo launchctl disable system/com.apple.diagnosticsd

echo "Analytics disabled"


# ----------------------------------------------------------
# Disable Game Center daemon
# ----------------------------------------------------------
# gamed -> Apple Game Center background service

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.gamed.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.gamed

echo "Game Center disabled"


# ----------------------------------------------------------
# Disable Photos background AI analysis
# ----------------------------------------------------------
# photoanalysisd -> image AI analysis
# photolibraryd -> photo library manager
# mediaanalysisd -> video analysis

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.photoanalysisd.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.photoanalysisd

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.photolibraryd.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.photolibraryd

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.mediaanalysisd.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.mediaanalysisd

echo "Photos analysis disabled"


# ----------------------------------------------------------
# Disable AirDrop / AirPlay helpers
# ----------------------------------------------------------
# sharingd -> AirDrop / device sharing
# AirPlayXPCHelper -> AirPlay background service

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.sharingd.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.sharingd

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.AirPlayXPCHelper.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.AirPlayXPCHelper

echo "AirDrop / AirPlay disabled"


# ----------------------------------------------------------
# Disable Handoff (device continuity)
# ----------------------------------------------------------
# handoffd -> Apple device handoff

launchctl bootout gui/$UID /System/Library/LaunchAgents/com.apple.handoffd.plist 2>/dev/null
launchctl disable gui/$UID/com.apple.handoffd

echo "Handoff disabled"


# ----------------------------------------------------------
# Disable automatic macOS update service
# ----------------------------------------------------------
# softwareupdated -> background update checks

sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.softwareupdated.plist 2>/dev/null
sudo launchctl disable system/com.apple.softwareupdated

echo "Software update disabled"


# ----------------------------------------------------------
# Disable Bluetooth daemon
# ----------------------------------------------------------
# bluetoothd -> bluetooth device manager

sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.bluetoothd.plist 2>/dev/null
sudo launchctl disable system/com.apple.bluetoothd

echo "Bluetooth disabled"


# ----------------------------------------------------------
# Disable widgets
# ----------------------------------------------------------

defaults write com.apple.notificationcenterui widgets-enabled -bool false
killall NotificationCenter 2>/dev/null

echo "Widgets disabled"


echo ""
echo "======================================"
echo "Persistent optimization complete"
echo "Services will remain disabled after reboot"
echo "Safari / iCloud / Apple ID unaffected"
echo "======================================"
