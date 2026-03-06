#!/bin/bash

echo "Restoring macOS disabled services..."

sudo launchctl enable system/com.apple.metadata.mds
sudo launchctl enable system/com.apple.analyticsd
sudo launchctl enable system/com.apple.diagnosticsd
sudo launchctl enable system/com.apple.softwareupdated
sudo launchctl enable system/com.apple.bluetoothd

UID=$(id -u)

launchctl enable gui/$UID/com.apple.assistantd
launchctl enable gui/$UID/com.apple.SiriNCService
launchctl enable gui/$UID/com.apple.suggestd
launchctl enable gui/$UID/com.apple.gamed
launchctl enable gui/$UID/com.apple.photoanalysisd
launchctl enable gui/$UID/com.apple.photolibraryd
launchctl enable gui/$UID/com.apple.mediaanalysisd
launchctl enable gui/$UID/com.apple.sharingd
launchctl enable gui/$UID/com.apple.AirPlayXPCHelper
launchctl enable gui/$UID/com.apple.handoffd

echo "Services restored. Reboot recommended."
