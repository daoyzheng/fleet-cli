#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Fleet Status
# @raycast.mode fullOutput
# @raycast.icon 🛠️
# @raycast.packageName Fleet
# @raycast.description Every agent, preview and task worktree

export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
if launchctl list 2>/dev/null | grep -q "dev.fleet.babysit"; then
  echo "babysit: RUNNING"
else
  echo "babysit: stopped"
fi
fleet 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
