#!/usr/bin/env bash
# Install fleet. Scripts are copied; UI integrations point back at this repo,
# so `git pull` updates them with no second copy to drift.
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$PREFIX/bin" "$PREFIX/libexec"
install -m 0755 "$SRC/bin/fleet"       "$PREFIX/bin/fleet"
install -m 0755 "$SRC/bin/secret-scan" "$PREFIX/bin/secret-scan"
for f in "$SRC"/libexec/*; do install -m 0644 "$f" "$PREFIX/libexec/$(basename "$f")"; done
echo "installed fleet + secret-scan into $PREFIX/bin"

case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) echo "warning: $PREFIX/bin is not on your PATH" ;; esac
for d in herdr git python3; do
  command -v "$d" >/dev/null 2>&1 || echo "warning: missing dependency '$d'"
done

# --- optional integrations -------------------------------------------------
if [ "${1:-}" = "--ui" ]; then
  # launch agent: watch the fleet and push to your phone
  PLIST="$HOME/Library/LaunchAgents/dev.fleet.babysit.plist"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/state/fleet"
  sed "s|__HOME__|$HOME|g" "$SRC/dev.fleet.babysit.plist.in" > "$PLIST"
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST" 2>/dev/null && echo "loaded launch agent dev.fleet.babysit"

  # SwiftBar reads this repo's swiftbar/ directly — no copy
  if [ -d "/Applications/SwiftBar.app" ]; then
    defaults write com.ameba.SwiftBar PluginDirectory -string "$SRC/swiftbar"
    echo "SwiftBar plugin directory -> $SRC/swiftbar"
  else
    echo "SwiftBar not installed (brew install --cask swiftbar) — skipped"
  fi

  echo
  echo "Raycast: Settings > Extensions > Script Commands > Add Directory:"
  echo "  $SRC/raycast-scripts"
fi
