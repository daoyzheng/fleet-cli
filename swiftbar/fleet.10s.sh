#!/bin/bash
# <xbar.title>Fleet</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Dao Zheng</xbar.author>
# <xbar.desc>Live state of AI coding agents dispatched with fleet</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin"
FLEET="$HOME/.local/bin/fleet"
PLIST="$HOME/Library/LaunchAgents/dev.fleet.babysit.plist"
TOGGLE="$HOME/.config/raycast-scripts/fleet-babysit-toggle.sh"

herdr status >/dev/null 2>&1 || { echo "fleet : off"; echo "---"; echo "herdr is not running"; exit 0; }

AGENTS=$(herdr agent list 2>/dev/null | python3 -c "
import sys,json
try: a=json.load(sys.stdin)['result']['agents']
except Exception: a=[]
for x in a:
    if not x.get('name'): continue
    t=(x.get('terminal_title_stripped') or '').strip()
    print('\t'.join([x['name'], x['agent_status'], x['agent'], x['cwd'], t[:60]]))
" 2>/dev/null)

WORK=$(printf '%s\n' "$AGENTS" | grep -c $'\tworking\t' || true)
BLOCK=$(printf '%s\n' "$AGENTS" | grep -c $'\tblocked\t' || true)
DONE=$(printf '%s\n' "$AGENTS" | grep -cE $'\t(idle|done)\t' || true)
[ -z "$AGENTS" ] && { WORK=0; BLOCK=0; DONE=0; }

if [ "$BLOCK" -gt 0 ]; then
  echo "◆ $BLOCK needs you | color=#c9524f"
elif [ "$WORK" -gt 0 ]; then
  echo "◐ $WORK working | color=#b07d2b"
elif [ "$DONE" -gt 0 ]; then
  echo "✓ $DONE ready | color=#2f7d57"
else
  echo "◇ fleet | color=#8a8a8a"
fi

echo "---"

if [ -n "$AGENTS" ]; then
  echo "AGENTS | size=11 color=#8a8a8a"
  while IFS=$'\t' read -r name st kind cwd title; do
    [ -n "$name" ] || continue
    case "$st" in
      blocked) icon="◆"; col="#c9524f" ;;
      working) icon="◐"; col="#b07d2b" ;;
      *)       icon="✓"; col="#2f7d57" ;;
    esac
    echo "$icon $name — $st | color=$col"
    [ -n "$title" ] && echo "--$title | size=11 color=#8a8a8a"
    echo "--[$kind] ${cwd/#$HOME/~} | size=11 color=#8a8a8a"
    echo "-----"
    echo "--Focus this agent | bash='herdr' param1='agent' param2='focus' param3=\"$name\" terminal=false"
    echo "--Copy full handoff | bash='/bin/bash' param1='-c' param2=\"$FLEET handoff '$name' | pbcopy\" terminal=false"
  done <<< "$AGENTS"
else
  echo "no dispatched agents | color=#8a8a8a"
fi

PREV=$("$FLEET" preview --list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep 'http' || true)
if [ -n "$PREV" ]; then
  echo "---"
  echo "PREVIEWS | size=11 color=#8a8a8a"
  while read -r pname purl ppath; do
    [ -n "$pname" ] || continue
    echo "$pname | href=$purl"
    echo "--$purl | size=11"
  done <<< "$PREV"
fi

echo "---"
if launchctl list 2>/dev/null | grep -q "dev.fleet.babysit"; then
  echo "🛎️ Babysit: on | color=#2f7d57"
  echo "--Stop babysit | bash=\"$TOGGLE\" terminal=false refresh=true"
else
  echo "🛑 Babysit: off | color=#c9524f"
  echo "--Start babysit | bash=\"$TOGGLE\" terminal=false refresh=true"
fi
echo "Refresh | refresh=true"
