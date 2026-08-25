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

_agent_gist() { # name -> "[kind] what the agent is on about"
  herdr agent list 2>/dev/null | python3 -c "
import sys,json,re
try: a=json.load(sys.stdin)['result']['agents']
except Exception: sys.exit()
m=next((x for x in a if (x.get('name') or x['pane_id'])=='$1'), None)
if not m: sys.exit()
t=m.get('terminal_title_stripped') or m.get('terminal_title','')
t=re.sub(r'^[^A-Za-z0-9]*','',t).strip()
k=m.get('agent','')
print((f'[{k}] ' if k else '')+t[:100])" 2>/dev/null
}

_agent_ask() { # name -> the question/prompt an agent is blocked on
  herdr agent read "$1" --source visible --lines 40 --format text 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -vE '^\s*$|^[─╭╰│╮╯]|^\s*❯|shift\+tab|for shortcuts|auto mode|manual mode' \
    | tail -4 | tr '\n' ' ' | cut -c1-180
}

cmd_babysit() {
  local interval=30 topic="${FLEET_NTFY_TOPIC:-}" once=0 keep=0 grace=120
  while [ $# -gt 0 ]; do
    case "$1" in
      --topic)    topic="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --grace)    grace="$2"; shift 2 ;;
      --keep)     keep=1; shift ;;
      --test)     once=1; shift ;;
      *) echo "usage: fleet babysit [--topic <t>] [--interval <s>] [--grace <s>] [--keep] [--test]" >&2; return 1 ;;
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

  # only one babysit at a time, or every notification goes out twice
  local lock="${XDG_STATE_HOME:-$HOME/.local/state}/fleet/babysit.lock"
  mkdir -p "$(dirname "$lock")"
  if [ -f "$lock" ] && kill -0 "$(cat "$lock" 2>/dev/null)" 2>/dev/null; then
    echo "fleet: babysit is already running (pid $(cat "$lock")). One instance watches everything." >&2
    return 1
  fi
  echo $$ > "$lock"

  # keep the Mac awake for as long as this runs
  caffeinate -i -w $$ &
  FLEET_CAFF_PID=$!
  trap '[ -n "${FLEET_CAFF_PID:-}" ] && kill "$FLEET_CAFF_PID" 2>/dev/null; return 0' INT TERM
  trap '[ -n "${FLEET_CAFF_PID:-}" ] && kill "$FLEET_CAFF_PID" 2>/dev/null; rm -f "'"$lock"'"' EXIT

  echo "babysitting — topic: $topic, every ${interval}s${keep:+, staying up}. Ctrl-C to stop."
  local seen_blocked="" summary n_work n_block n_idle
  local elapsed=0 ever_worked=0 quiet=0 announced=0

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
        *) local ask gist
           gist=$(_agent_gist "$a"); ask=$(_agent_ask "$a")
           _notify "❓ $a needs an answer" "${gist:+$gist
}${ask:-Blocked and waiting for input.}" high question
           seen_blocked="$seen_blocked $a"
           echo "  [blocked] $a — notified" ;;
      esac
    done

    [ "${n_work:-0}" -gt 0 ] && { ever_worked=1; quiet=0; announced=0; }

    if [ "${n_work:-0}" -eq 0 ]; then
      # Agents can read as idle for a moment right after dispatch, before they
      # pick up the prompt. Require two consecutive quiet polls, and don't call
      # it settled until we have actually seen work happen (or grace expires).
      quiet=$((quiet+1))
      if [ "$quiet" -ge 2 ] && { [ "$ever_worked" -eq 1 ] || [ "$elapsed" -ge "$grace" ]; }; then
        if [ "$announced" -eq 0 ]; then
          summary=""
          local nm st
          while IFS='|' read -r nm st; do
            [ -n "$nm" ] || continue
            summary="${summary}${nm} — $(_agent_gist "$nm")
"
          done <<EOS
$named
EOS
          if [ "${n_block:-0}" -gt 0 ]; then
            _notify "⚠️ fleet done, $n_block still need you" "$(printf '%s' "$summary" | head -c 380)" high warning
          else
            _notify "✅ ready for your review" "$(printf '%s' "$summary" | head -c 380)" high white_check_mark
          fi
          echo ""
          echo "all settled — notified"
          printf '%s\n' "$summary" | sed 's/^/  /'
          announced=1
        fi
        [ "$keep" -eq 0 ] && { kill "${FLEET_CAFF_PID:-0}" 2>/dev/null; rm -f "$lock"; return 0; }
      fi
    fi

    printf '\r  %s working, %s blocked, %s done   ' "${n_work:-0}" "${n_block:-0}" "${n_idle:-0}"
    sleep "$interval"
    elapsed=$((elapsed+interval))
  done
}
