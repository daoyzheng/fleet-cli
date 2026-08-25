# fleet space — scaffold a project workspace with the standard layout.
# Sourced by fleet; not meant to run standalone.
#
# Layout:
#   tab 1 "work"  pane1 agent | pane2 app (fleet preview) / pane3 shell
#   tab 2 "edit"  nvim
#   tab 3 "git"   lazygit
#
# Panes are created with HERDR_PANE_CMD, which ~/.zshrc pre-types at the prompt.

_ws_field() { python3 -c "import sys,json;print(json.load(sys.stdin)['result']$1)"; }

cmd_space() {
  local dir="" agent="" label="" no_edit=0 no_git=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent="$2"; shift 2 ;;
      --label) label="$2"; shift 2 ;;
      --no-edit) no_edit=1; shift ;;
      --no-git)  no_git=1;  shift ;;
      *) dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || { echo "usage: fleet space <repo-or-worktree-path> [--agent claude|cursor|none]  (default per FLEET_AGENT_DEFAULTS) [--label name] [--no-edit] [--no-git]" >&2; return 1; }
  dir="${dir/#\~/$HOME}"
  [ -d "$dir" ] || { echo "no such directory: $dir" >&2; return 1; }
  dir="$(cd "$dir" && pwd)"
  [ -n "$label" ] || label="$(basename "$dir")"
  [ -n "$agent" ] || agent=$(_default_kind "$dir")

  case "$agent" in claude|cursor|codex|gemini|copilot|opencode|amp|droid|none) ;;
    *) echo "fleet: unsupported --agent '$agent'" >&2; return 1 ;; esac

  local out ws p1
  out=$(herdr workspace create --cwd "$dir" --label "$label" --no-focus) || return 1
  ws=$(printf '%s' "$out" | _ws_field "['workspace']['workspace_id']")
  p1=$(printf '%s' "$out" | _ws_field "['root_pane']['pane_id']")

  # tab 1: app pane beside the agent, shell beneath it
  local p2
  p2=$(herdr pane split "$p1" --direction right --ratio 0.45 --cwd "$dir" \
        --env HERDR_PANE_CMD="fleet preview $dir" | _ws_field "['pane']['pane_id']")
  herdr pane split "$p2" --direction down --ratio 0.5 --cwd "$dir" >/dev/null
  herdr tab rename "${p1%%:*}:t1" work >/dev/null 2>&1 || true

  [ "$no_edit" = 0 ] && herdr tab create --workspace "$ws" --cwd "$dir" --label edit \
      --env HERDR_PANE_CMD="nvim ." --no-focus >/dev/null
  [ "$no_git" = 0 ]  && herdr tab create --workspace "$ws" --cwd "$dir" --label git \
      --env HERDR_PANE_CMD="lazygit" --no-focus >/dev/null

  if [ "$agent" != "none" ]; then
    herdr agent start "$label" --kind "$agent" --pane "$p1" --timeout 90000 >/dev/null \
      || echo "fleet: '$agent' did not start in $p1 (layout is still up)" >&2
  fi

  echo "$label  workspace $ws  ($dir)"
  echo "  tab 1 work: $agent | fleet preview / shell"
  [ "$no_edit" = 0 ] && echo "  tab 2 edit: nvim"
  [ "$no_git" = 0 ]  && echo "  tab 3 git:  lazygit"
  echo "  commands are pre-typed at each prompt — press Enter to run"
  return 0
}
