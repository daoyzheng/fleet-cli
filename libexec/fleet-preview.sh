# fleet preview — start a repo's dev server on a free, deterministic port.
# Sourced by fleet; not meant to run standalone.

PREVIEW_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/fleet/previews"

_pm() { # package manager for a repo
  [ -f "$1/pnpm-lock.yaml" ] && { echo pnpm; return; }
  [ -f "$1/yarn.lock" ]      && { echo yarn; return; }
  echo npm
}

_kill_preview() { # kills the process group, then any straggler on the port
  kill -TERM -"$PV_PID" 2>/dev/null || kill -TERM "$PV_PID" 2>/dev/null || true
  sleep 1
  local left; left=$(lsof -nP -iTCP:"$PV_PORT" -sTCP:LISTEN -t 2>/dev/null || true)
  [ -n "$left" ] && printf '%s\n' "$left" | while read -r pid; do kill -TERM "$pid" 2>/dev/null || true; done
  return 0
}

_port_free() { ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

_pick_port() { # deterministic from name, then walk until free
  local name="$1" base
  base=$(printf '%s' "$name" | cksum | awk '{print 3100 + ($1 % 700)}')
  local p="$base" tries=0
  while ! _port_free "$p"; do p=$((p+1)); tries=$((tries+1)); [ "$tries" -gt 200 ] && { echo "" ; return 1; }; done
  echo "$p"
}

_detect() { # -> "kind|command" using $PORT
  local dir="$1" pm; pm=$(_pm "$dir")
  local pkg="$dir/package.json"
  if [ -f "$pkg" ]; then
    if grep -q '"@strapi/strapi"' "$pkg"; then echo "strapi|$pm run dev"; return; fi
    if grep -q '"nuxt"' "$pkg";           then echo "nuxt|$pm run dev";   return; fi
    if grep -q '"quasar"' "$pkg" && grep -q '"start:ui"' "$pkg"; then echo "quasar|$pm run start:ui -- --port %PORT%"; return; fi
    if grep -q '"dev"' "$pkg";            then echo "node|$pm run dev";   return; fi
  fi
  [ -n "$(find "$dir" -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null)" ] && { echo "dotnet|"; return; }
  echo "|"
}

cmd_preview() {
  local action="" target="" dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --list|--stop-all) action="$1"; shift ;;
      --stop|--logs)     action="$1"; target="${2:-}"; shift 2 ;;
      --dry-run)         dry=1; shift ;;
      *)                 target="$1"; shift ;;
    esac
  done
  mkdir -p "$PREVIEW_STATE"

  case "$action" in
    --list)
      local any=0
      for f in "$PREVIEW_STATE"/*.env; do
        [ -f "$f" ] || continue
        . "$f"
        if kill -0 "$PV_PID" 2>/dev/null; then printf "  %-24s http://localhost:%-6s %s\n" "$PV_NAME" "$PV_PORT" "$PV_DIR"; any=1
        else rm -f "$f"; fi
      done
      [ "$any" = 0 ] && echo "  no previews running"
      return 0 ;;
    --stop)
      local f="$PREVIEW_STATE/$target.env"
      [ -f "$f" ] || { echo "no preview named '$target'" >&2; return 1; }
      . "$f"; _kill_preview; echo "stopped $PV_NAME (port $PV_PORT)"
      rm -f "$f"; return 0 ;;
    --stop-all)
      for f in "$PREVIEW_STATE"/*.env; do [ -f "$f" ] || continue; . "$f"; _kill_preview; rm -f "$f"; echo "stopped $PV_NAME"; done
      return 0 ;;
    --logs)
      local f="$PREVIEW_STATE/$target.env"
      [ -f "$f" ] || { echo "no preview named '$target'" >&2; return 1; }
      . "$f"; tail -f "$PV_LOG" ;;
  esac

  # --- start ---
  [ -n "$target" ] || { echo "usage: fleet preview <repo-or-worktree-path> | --list | --stop <name> | --logs <name> | --stop-all" >&2; return 1; }
  local dir="${target/#\~/$HOME}"
  [ -d "$dir" ] || { echo "no such directory: $dir" >&2; return 1; }
  dir="$(cd "$dir" && pwd)"

  local name kind cmd port log
  name="$(basename "$(dirname "$dir")")-$(basename "$dir")"
  name="${name//[^A-Za-z0-9._-]/-}"
  IFS='|' read -r kind cmd <<EOF
$(_detect "$dir")
EOF
  [ -n "$kind" ] || { echo "fleet: don't know how to start a dev server in $dir" >&2; return 1; }
  [ -n "$cmd" ]  || { echo "fleet: '$kind' projects have no local dev server here" >&2; return 1; }

  port=$(_pick_port "$name") || { echo "fleet: no free port found" >&2; return 1; }
  log="$PREVIEW_STATE/$name.log"

  if [ "$dry" = 1 ]; then
    echo "  dir  : $dir"; echo "  kind : $kind"; echo "  port : $port"
    echo "  cmd  : PORT=$port NUXT_PORT=$port ${cmd//%PORT%/$port}"
    return 0
  fi

  local runcmd="${cmd//%PORT%/$port}"
  ( set -m; cd "$dir" && PORT="$port" NUXT_PORT="$port" nohup sh -c "$runcmd" >"$log" 2>&1 & echo $! > "$PREVIEW_STATE/$name.pid" )
  local pid; pid=$(cat "$PREVIEW_STATE/$name.pid"); rm -f "$PREVIEW_STATE/$name.pid"
  cat > "$PREVIEW_STATE/$name.env" <<EOS
PV_NAME="$name"
PV_DIR="$dir"
PV_PORT="$port"
PV_PID="$pid"
PV_LOG="$log"
EOS
  echo "$name  http://localhost:$port  ($kind, pid $pid)"
  echo "  logs: fleet preview --logs $name"
}
