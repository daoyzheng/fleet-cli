#!/usr/bin/env bash
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$PREFIX/bin" "$PREFIX/libexec"
install -m 0755 "$SRC/bin/fleet"          "$PREFIX/bin/fleet"
install -m 0755 "$SRC/bin/secret-scan"    "$PREFIX/bin/secret-scan"
install -m 0644 "$SRC/libexec/fleet-fmt.py" "$PREFIX/libexec/fleet-fmt.py"

echo "installed:"
echo "  $PREFIX/bin/fleet"
echo "  $PREFIX/bin/secret-scan"
echo "  $PREFIX/libexec/fleet-fmt.py"

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) echo; echo "warning: $PREFIX/bin is not on your PATH." ;;
esac

for d in herdr git python3; do
  command -v "$d" >/dev/null 2>&1 || echo "warning: missing dependency '$d'"
done
