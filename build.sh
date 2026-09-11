#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
exec "$ROOT/plugins/token-galaxy/build.sh" "$@"
