#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Fleet — What Needs Me
# @raycast.mode fullOutput
# @raycast.icon ✅
# @raycast.packageName Fleet
# @raycast.description Agents that are idle or blocked, plus live preview URLs

export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
echo "── waiting on you ──"
fleet ready 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
echo
echo "── previews ──"
fleet preview --list 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
