#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Toggle Fleet Babysit
# @raycast.mode inline
# @raycast.icon 🛎️
# @raycast.packageName Fleet
# @raycast.description Start or stop the background watcher that pushes to your phone

export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
fleet babysit --toggle
