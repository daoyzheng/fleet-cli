#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Toggle Fleet Babysit
# @raycast.mode inline
# @raycast.icon 🛎️
# @raycast.packageName Fleet
# @raycast.description Start or stop the background watcher that pushes to your phone

PLIST="$HOME/Library/LaunchAgents/dev.fleet.babysit.plist"
if launchctl list 2>/dev/null | grep -q "dev.fleet.babysit"; then
  launchctl unload "$PLIST" 2>/dev/null
  pkill -f "caffeinate -i -w" 2>/dev/null
  rm -f "$HOME/.local/state/fleet/babysit.lock"
  echo "🛑 babysit stopped — no phone notifications"
else
  launchctl load "$PLIST" 2>/dev/null
  sleep 2
  if launchctl list 2>/dev/null | grep -q "dev.fleet.babysit"; then
    echo "🛎️ babysit running — Mac stays awake, phone gets pushes"
  else
    echo "⚠️ failed to start — check ~/.local/state/fleet/babysit.err"
  fi
fi
