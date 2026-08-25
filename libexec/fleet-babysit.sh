# fleet babysit — keep the machine awake, watch the fleet, notify when it settles.
# Sourced by fleet.

_notify() { # title, message
  local topic="${FLEET_NTFY_TOPIC:-}"
  [ -n "$topic" ] || return 0
  curl -s -m 15 \
    -H "Title: $1" \
    -H "Priority: ${3:-default}" \
    -H "Tags: ${4:-robot}" \
    -d "$2" "https://ntfy.sh/$topic" >/dev/null 2>&1 || true
}

cmd_babysit() {
  local interval=30 topic="${FLEET_NTFY_TOPIC:-}" once=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --topic)    topic="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --test)     once=1; shift ;;
      *) echo "usage: fleet babysit [--topic <ntfy-topic>] [--interval <secs>] [--test]" >&2; return 1 ;;
    esac
  done
  export FLEET_NTFY_TOPIC="$topic"

  if [ -z "$topic" ]; then
    echo "fleet: no ntfy topic set. Add FLEET_NTFY_TOPIC to ~/.config/fleet/config" >&2
    echo "       or pass --topic <name>. Install the ntfy app and subscribe to it." >&2
    return 1
  fi

  if [ "$once" = 1 ]; then
    _notify "fleet test" "If you see this on your phone, notifications are working." default white_check_mark
    echo "sent a test notification to ntfy.sh/$topic"
    return 0
  fi

  # keep the Mac awake for as long as this runs
  caffeinate -i -w $$ &
  local caff=$!
  trap 'kill $caff 2>/dev/null' EXIT INT TERM

  echo "babysitting — topic: $topic, every ${interval}s. Ctrl-C to stop."
  local seen_blocked="" summary n_work n_block n_idle

  while true; do
    local snapshot
    snapshot=$(herdr agent list 2>/dev/null | python3 -c "
import sys,json
try: a=json.load(sys.stdin)['result']['agents']
except Exception: a=[]
for x in a:
    print((x.get('name') or x['pane_id']), x['agent_status'], sep='|')" 2>/dev/null)

    # only consider named agents (the ones fleet dispatched)
    local named
    named=$(printf '%s\n' "$snapshot" | grep -v '^[a-zA-Z0-9]*:p[0-9]*|' || true)
    [ -n "$named" ] || { echo "no dispatched agents to watch"; return 0; }

    n_work=$(printf '%s\n' "$named" | grep -c '|working$' || true)
    n_block=$(printf '%s\n' "$named" | grep -c '|blocked$' || true)
    n_idle=$(printf '%s\n' "$named" | grep -cE '\|(idle|done)$' || true)

    # notify once per newly-blocked agent — these need a human now
    local a
    for a in $(printf '%s\n' "$named" | awk -F'|' '$2=="blocked"{print $1}'); do
      case " $seen_blocked " in
        *" $a "*) ;;
        *) _notify "fleet: $a needs you" "Agent '$a' is blocked and waiting for input." high warning
           seen_blocked="$seen_blocked $a"
           echo "  [blocked] $a — notified" ;;
      esac
    done

    if [ "${n_work:-0}" -eq 0 ]; then
      summary=$(printf '%s\n' "$named" | awk -F'|' '{printf "%s: %s\n", $1, $2}')
      _notify "fleet: all tasks settled" "$(printf '%s' "$summary" | head -c 400)" high white_check_mark
      echo "all settled — notified"
      printf '%s\n' "$summary" | sed 's/^/  /'
      return 0
    fi

    printf '\r  %s working, %s blocked, %s done   ' "${n_work:-0}" "${n_block:-0}" "${n_idle:-0}"
    sleep "$interval"
  done
}
