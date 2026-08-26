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

_sessions() { # -> "name<TAB>socket" for every running herdr session
  herdr session list 2>/dev/null | awk 'NR>1 && $2=="running" {print $1"\t"$NF}'
}

_all_agents() { # -> name|status|kind|session  across every running session
  local nm sock
  while IFS=$'\t' read -r nm sock; do
    [ -n "$sock" ] || continue
    HERDR_SOCKET_PATH="$sock" herdr agent list 2>/dev/null | python3 -c "
import sys,json
try: a=json.load(sys.stdin)['result']['agents']
except Exception: sys.exit()
for x in a:
    if not x.get('name'): continue
    print('|'.join([x['name'], x['agent_status'], x.get('agent',''), '$nm']))" 2>/dev/null
  done < <(_sessions)
}

_agent_gist() { # name [socket] -> "[kind] what the agent is on about"
  HERDR_SOCKET_PATH="${2:-$HERDR_SOCKET_PATH}" herdr agent list 2>/dev/null | python3 -c "
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

_agent_ask() { # name [socket] -> the question an agent is blocked on
  HERDR_SOCKET_PATH="${2:-$HERDR_SOCKET_PATH}" herdr agent read "$1" --source visible --lines 40 --format text 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -vE '^\s*$|^[─╭╰│╮╯]|^\s*❯|shift\+tab|for shortcuts|auto mode|manual mode' \
    | tail -4 | tr '\n' ' ' | cut -c1-180
}


# --- inbound relay: answer an agent by publishing to <topic>-in from your phone --
_agent_names() { _all_agents | awk -F'|' '{print $1}' | sort; }

_resolve_agent() { # accepts an exact name, a number from the roster, or a unique prefix
  local want="$1" names n hit
  names=$(_agent_names)
  [ -n "$names" ] || return 1
  # exact
  printf '%s\n' "$names" | grep -qx "$want" && { printf '%s' "$want"; return 0; }
  # roster number
  case "$want" in
    ''|*[!0-9]*) ;;
    *) n=$(printf '%s\n' "$names" | sed -n "${want}p"); [ -n "$n" ] && { printf '%s' "$n"; return 0; }; return 1 ;;
  esac
  # unique case-insensitive prefix / substring
  hit=$(printf '%s\n' "$names" | grep -i -- "$want" || true)
  [ "$(printf '%s\n' "$hit" | grep -c .)" = "1" ] && { printf '%s' "$hit"; return 0; }
  return 1
}

_relay_state() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/fleet/relay-since"; }

_relay_poll() { # read new messages on the inbound topic and feed them to agents
  local topic="${FLEET_NTFY_TOPIC:-}-in" st since msgs
  [ -n "${FLEET_NTFY_TOPIC:-}" ] || return 0
  st=$(_relay_state)
  if [ ! -f "$st" ]; then
    # first run: start from now so a restart never replays the day's messages
    printf '%s' "$(date +%s)" > "$st"
  fi
  since=$(cat "$st" 2>/dev/null || date +%s)

  msgs=$(curl -s -m 20 "https://ntfy.sh/${topic}/json?poll=1&since=${since}" 2>/dev/null | python3 -c "
import sys,json
last=None
out=[]
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    if d.get('event')!='message': continue
    last=d.get('id')
    out.append((d.get('message') or '').replace(chr(10),' '))
for m in out: print('MSG	'+m)
if last: print('LAST	'+last)
" 2>/dev/null)
  [ -n "$msgs" ] || return 0

  local kind rest agent text
  while IFS=$'\t' read -r kind rest; do
    case "$kind" in
      LAST) printf '%s' "$rest" > "$st" ;;
      MSG)
        local trimmed roster names n_names
        trimmed="$(printf '%s' "$rest" | sed 's/^ *//;s/ *$//')"

        # "?" or "who" -> push the current roster instead of prompting anyone
        case "$trimmed" in
          "?"|who|list|agents|status)
            roster=""; local i=0 rn2
            while read -r rn2; do
              [ -n "$rn2" ] || continue
              i=$((i+1))
              roster="${roster}${i}. ${rn2} — $(_agent_gist "$rn2")
"
            done <<EOR
$(_agent_names)
EOR
            _notify "🗒 agents" "${roster:-nothing dispatched}" default clipboard
            echo "  [relay] roster sent"
            continue ;;
        esac

        agent="${trimmed%%:*}"; text="${trimmed#*:}"
        agent="$(printf '%s' "$agent" | tr -d '[:space:]')"
        [ "${#agent}" -gt 40 ] && agent="$trimmed"
        if [ "$agent" != "$trimmed" ]; then
          local resolved
          if resolved=$(_resolve_agent "$agent"); then
            agent="$resolved"
          else
            _notify "no match for '$agent'" "Send ? for the numbered list." high question
            echo "  [relay] could not resolve '$agent'"
            continue
          fi
        fi
        text="$(printf '%s' "$text" | sed 's/^ *//')"

        # No "agent:" prefix? Route it for them.
        if [ "$agent" = "$trimmed" ] || [ -z "$text" ]; then
          text="$trimmed"
          names=$(_all_agents | awk -F'|' '{print $1}')
          n_names=$(printf '%s\n' "$names" | grep -c . || true)
          agent=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/fleet/last-asked" 2>/dev/null || true)
          # the agent we last alerted about, if it still exists
          if [ -z "$agent" ] || ! printf '%s\n' "$names" | grep -qx "$agent"; then
            if [ "${n_names:-0}" -eq 1 ]; then
              agent="$(printf '%s' "$names" | tr -d '[:space:]')"
            else
              roster=$(printf '%s\n' "$names" | awk '{print NR". "$0}' | tr '\n' ' ')
              _notify "which agent?" "Reply like  2: your message   —  $roster" high question
              echo "  [relay] ambiguous, asked which agent"
              continue
            fi
          fi
          echo "  [relay] no prefix — routing to '$agent'"
        fi
        if [ -z "$agent" ] || [ -z "$text" ]; then
          echo "  [relay] ignored: ${rest:0:60}"
          continue
        fi
        # only ever target an agent that actually exists
        local sock found=""
        while IFS=$'\t' read -r sname ssock; do
          [ -n "$ssock" ] || continue
          if HERDR_SOCKET_PATH="$ssock" herdr agent list 2>/dev/null | grep -q "\"name\":\"$agent\""; then
            found="$ssock"; break
          fi
        done < <(_sessions)
        if [ -z "$found" ]; then
          echo "  [relay] no agent named '$agent'"
          _notify "relay: no agent '$agent'" "Nothing dispatched under that name." default warning
          continue
        fi
        HERDR_SOCKET_PATH="$found" herdr agent prompt "$agent" "$text" >/dev/null 2>&1 || true
        sleep 2
        HERDR_SOCKET_PATH="$found" herdr agent send-keys "$agent" Enter >/dev/null 2>&1 || true
        echo "  [relay] -> $agent: ${text:0:60}"
        _notify "➡️ sent to $agent" "${text:0:150}" default incoming_envelope
        # a fresh answer means it may block again; allow a new alert
        seen_blocked="${seen_blocked// $agent / }"
        ;;
    esac
  done <<EOS
$msgs
EOS
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
      --toggle)
        local P="$HOME/Library/LaunchAgents/dev.fleet.babysit.plist"
        if launchctl list 2>/dev/null | grep -q "dev.fleet.babysit"; then
          launchctl unload "$P" 2>/dev/null
          pkill -f "caffeinate -i -w" 2>/dev/null || true
          rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/fleet/babysit.lock"
          echo "🛑 babysit stopped — no phone notifications"
        elif [ -f "$P" ]; then
          launchctl load "$P" 2>/dev/null; sleep 2
          if launchctl list 2>/dev/null | grep -q "dev.fleet.babysit"; then
            echo "🛎️ babysit running — Mac stays awake, phone gets pushes"
          else
            echo "⚠️ failed to start — see ~/.local/state/fleet/babysit.err"
          fi
        else
          echo "⚠️ no launch agent installed at $P"
        fi
        return 0 ;;
      --status)
        launchctl list 2>/dev/null | grep -q "dev.fleet.babysit" && echo on || echo off
        return 0 ;;
      --stop)
        local L="${XDG_STATE_HOME:-$HOME/.local/state}/fleet/babysit.lock"
        if [ -f "$L" ] && kill -0 "$(cat "$L" 2>/dev/null)" 2>/dev/null; then
          kill "$(cat "$L")" 2>/dev/null || true; pkill -f "caffeinate -i -w" 2>/dev/null || true
          rm -f "$L"; echo "babysit stopped"
        else
          rm -f "$L"; echo "babysit was not running"
        fi
        return 0 ;;
      *) echo "usage: fleet babysit [--topic <t>] [--interval <s>] [--grace <s>] [--keep] [--test] [--stop|--toggle|--status]" >&2; return 1 ;;
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
    local named
    named=$(_all_agents)
    if [ -z "$named" ]; then
      [ "$keep" -eq 1 ] && { printf '\r  no dispatched agents   '; sleep "$interval"; elapsed=$((elapsed+interval)); continue; }
      echo "no dispatched agents to watch"; return 0
    fi

    n_work=$(printf '%s\n' "$named" | awk -F'|' '$2=="working"' | wc -l | tr -d ' ')
    n_block=$(printf '%s\n' "$named" | awk -F'|' '$2=="blocked"' | wc -l | tr -d ' ')
    n_idle=$(printf '%s\n' "$named" | awk -F'|' '$2=="idle"||$2=="done"' | wc -l | tr -d ' ')

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
           printf '%s' "$a" > "${XDG_STATE_HOME:-$HOME/.local/state}/fleet/last-asked"
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

    _relay_poll
    printf '\r  %s working, %s blocked, %s done   ' "${n_work:-0}" "${n_block:-0}" "${n_idle:-0}"
    sleep "$interval"
    elapsed=$((elapsed+interval))
  done
}
