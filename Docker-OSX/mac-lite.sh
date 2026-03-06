#!/bin/bash

# ==========================================================
# macOS Lite Optimization Script
# Disable non-essential background services
# SAFE for:
# - Safari browsing
# - Website fingerprinting (WebGL, Canvas, Fonts)
# - iCloud
# - Apple ID login
# ==========================================================

echo "Starting macOS background service optimization..."

# ----------------------------------------------------------
# Disable Siri & voice assistant services
# ----------------------------------------------------------
# assistantd        -> Core Siri daemon
# SiriNCService     -> Siri notification center integration
# suggestd          -> Siri suggestions / Spotlight suggestions

launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.assistantd.plist 2>/dev/null
launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.SiriNCService.plist 2>/dev/null
launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.suggestd.plist 2>/dev/null

echo "Siri services disabled"


# ----------------------------------------------------------
# Disable Spotlight indexing (heavy CPU usage)
# ----------------------------------------------------------
# mds         -> Spotlight metadata server
# mdworker    -> Metadata worker
# mds_stores  -> Spotlight storage service

sudo mdutil -a -i off

echo "Spotlight indexing disabled"


# ----------------------------------------------------------
# Disable macOS analytics & diagnostics
# ----------------------------------------------------------
# analyticsd     -> Apple analytics reporting
# diagnosticsd   -> diagnostic log reporting

sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.analyticsd.plist 2>/dev/null
sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.diagnosticsd.plist 2>/dev/null

echo "Analytics disabled"


# ----------------------------------------------------------
# Disable Game Center background service
# ----------------------------------------------------------
# gamed -> Apple Game Center daemon

launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.gamed.plist 2>/dev/null

echo "Game Center disabled"


# ----------------------------------------------------------
# Disable Photos background analysis
# ----------------------------------------------------------
# photoanalysisd -> AI photo analysis
# photolibraryd  -> Photo library management
# mediaanalysisd -> Video/photo content analysis

launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.photoanalysisd.plist 2>/dev/null
launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.photolibraryd.plist 2>/dev/null
launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.mediaanalysisd.plist 2>/dev/null

echo "Photos analysis disabled"


# ----------------------------------------------------------
# Disable AirPlay & file sharing helpers
# ----------------------------------------------------------
# sharingd          -> AirDrop / sharing service
# AirPlayXPCHelper  -> AirPlay background helper

launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.sharingd.plist 2>/dev/null
launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.AirPlayXPCHelper.plist 2>/dev/null

echo "AirDrop / AirPlay services disabled"


# ----------------------------------------------------------
# Disable Handoff / Continuity features
# ----------------------------------------------------------
# handoffd -> Apple device handoff service

launchctl bootout gui/$(id -u) /System/Library/LaunchAgents/com.apple.handoffd.plist 2>/dev/null

echo "Handoff disabled"


# ----------------------------------------------------------
# Disable automatic software update background checks
# ----------------------------------------------------------
# softwareupdated -> macOS update background service

sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.softwareupdated.plist 2>/dev/null

echo "Automatic updates disabled"


# ----------------------------------------------------------
# Disable Bluetooth daemon (optional)
# ----------------------------------------------------------
# bluetoothd -> Bluetooth device management

sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.bluetoothd.plist 2>/dev/null

echo "Bluetooth daemon disabled"


# ----------------------------------------------------------
# Disable widget suggestions & dashboard services
# ----------------------------------------------------------
# NotificationCenter widgets

defaults write com.apple.notificationcenterui widgets-enabled -bool false

killall NotificationCenter 2>/dev/null

echo "Widgets disabled"


echo ""
echo "==============================================="
echo "macOS optimization completed"
echo "Safari, iCloud and Apple ID remain unaffected"
echo "==============================================="
