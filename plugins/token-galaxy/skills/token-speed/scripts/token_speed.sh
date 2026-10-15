#!/bin/zsh
set -euo pipefail

MODE=show
DURATION=15
WINDOW=10
PROVIDER=all
TASK_ID=""
STATE_DIR=""
DEMO_DIR=""
HAS_SAMPLE_OPTION=0
typeset -A SEEN_OPTIONS

usage() {
  cat <<'HELP'
Usage: token_speed.sh [show|sample|demo] [options]

  show                         Open the installed app's native Token speed window.
  sample                       Print a bounded local observation as JSON.
  demo OUTPUT_DIR              Render synthetic native screenshots.

Sample options:
  --seconds N                  Observe for 1..300 seconds after baseline (default: 15).
  --window N                   Rate window: 10, 30, or 60 seconds (default: 10).
  --provider NAME              all, codex, or claude (default: all).
  --task-id ID                 One task; requires codex or claude provider.
  --state-dir PATH             Forward an explicit isolated sampling state path.

  -h, --help                   Show help without opening the app or reading sessions.

Uses ~/Applications/Token Galaxy.app, then /Applications/Token Galaxy.app.
Set TOKEN_GALAXY_APP to select another installed app path.
Requires Token Galaxy 0.10.0 (build 38) or later. Never builds from source.
Show reuses the running app; sample runs its headless JSON command.
HELP
}

fail() { print -u2 -- "Token speed: $1"; exit 2; }
require_value() { (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail "$1 requires a value."; }
mark_option() {
  [[ -z "${SEEN_OPTIONS[$1]-}" ]] || fail "Duplicate option: $1."
  SEEN_OPTIONS[$1]=1
}

if (( $# )); then
  case "$1" in
    show|sample|demo) MODE="$1"; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) ;;
    *) fail 'Unknown command. Run token_speed.sh --help.' ;;
  esac
fi
while (( $# )); do
  case "$1" in
    --seconds) mark_option "$1"; require_value "$@"; DURATION="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    --window) mark_option "$1"; require_value "$@"; WINDOW="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    --provider) mark_option "$1"; require_value "$@"; PROVIDER="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    --task-id) mark_option "$1"; require_value "$@"; TASK_ID="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    --state-dir) mark_option "$1"; require_value "$@"; STATE_DIR="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) fail 'Unknown option. Run token_speed.sh --help.' ;;
    *) [[ "$MODE" == demo && -z "$DEMO_DIR" ]] || fail 'Unexpected positional argument.'; DEMO_DIR="$1"; shift ;;
  esac
done
[[ "$DURATION" =~ '^[0-9]{1,3}$' ]] && (( 10#$DURATION >= 1 && 10#$DURATION <= 300 )) || fail '--seconds must be from 1 to 300.'
DURATION="$((10#$DURATION))"
case "$WINDOW" in 10|30|60) ;; *) fail '--window must be 10, 30, or 60.' ;; esac
case "$PROVIDER" in all|codex|claude) ;; *) fail '--provider must be all, codex, or claude.' ;; esac
[[ -z "$TASK_ID" || "$PROVIDER" != all ]] || fail '--task-id requires --provider codex or claude.'
[[ "$MODE" == sample || "$HAS_SAMPLE_OPTION" == 0 ]] || fail 'Sampling options require sample.'
[[ "$MODE" != demo || -n "$DEMO_DIR" ]] || fail 'demo requires an output directory.'

APP="${TOKEN_GALAXY_APP:-}"
if [[ -z "$APP" ]]; then
  for candidate in "$HOME/Applications/Token Galaxy.app" '/Applications/Token Galaxy.app'; do
    if [[ -d "$candidate" ]]; then APP="$candidate"; break; fi
  done
fi
[[ -n "$APP" && -d "$APP" ]] || fail 'Install Token Galaxy 0.10.0 or later, or set TOKEN_GALAXY_APP to its app path.'
APP="${APP:A}"
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/TokenGalaxy"
[[ -f "$PLIST" && -x "$BINARY" ]] || fail 'The selected app is incomplete.'
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null)" || fail 'The selected app has no bundle identifier.'
[[ "$IDENTIFIER" == local.token-galaxy.native ]] || fail 'Select the formal Token Galaxy app, not an isolated preview.'
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)" || fail 'The selected app has no version.'
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null)" || fail 'The selected app has no build number.'
[[ "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$APP_BUILD" =~ '^[0-9]+$' ]] || fail 'The selected app has unsupported version metadata.'
MAJOR="${APP_VERSION%%.*}"
REMAINDER="${APP_VERSION#*.}"
MINOR="${REMAINDER%%.*}"
(( (10#$MAJOR > 0 || 10#$MINOR >= 10) && 10#$APP_BUILD >= 38 )) || fail 'Update the installed Token Galaxy app to 0.10.0 (build 38) or later.'

case "$MODE" in
  show)
    SCHEME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$PLIST" 2>/dev/null)" || fail 'The installed app has no Token speed URL entry.'
    [[ "$SCHEME" == token-galaxy ]] || fail 'The installed app has an unsupported Token speed URL entry.'
    /usr/bin/open -a "$APP" 'token-galaxy://speed'
    print 'Requested the installed Token Galaxy speed window.' ;;
  sample)
    args=(--speed-json --seconds "$DURATION" --window "$WINDOW" --provider "$PROVIDER")
    [[ -z "$TASK_ID" ]] || args+=(--task-id "$TASK_ID")
    [[ -z "$STATE_DIR" ]] || args+=(--state-dir "${STATE_DIR:A}")
    exec "$BINARY" "${args[@]}" ;;
  demo) exec "$BINARY" --speed-demo "${DEMO_DIR:A}" ;;
esac
