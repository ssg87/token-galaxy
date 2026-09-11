#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
APP="$ROOT/Outputs/Token Galaxy.app"
if [[ "$(uname -s)" != Darwin ]]; then
  print -u2 "Token Galaxy requires macOS 15 or later."; exit 1
fi
if [[ ! -x "$APP/Contents/MacOS/TokenGalaxy" ]]; then
  xcrun --find swiftc >/dev/null || { print -u2 "Install Apple Command Line Tools: xcode-select --install"; exit 1; }
  "$ROOT/build.sh"
fi
open "$APP"
print "Opened Token Galaxy. Use the sparkles menu to show the orb or view tasks."
