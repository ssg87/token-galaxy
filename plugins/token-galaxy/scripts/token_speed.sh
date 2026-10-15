#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PREVIEW_ROOT="$ROOT/Outputs/TokenSpeedPreview"
APP="$PREVIEW_ROOT/Token Galaxy.app"
BINARY="$APP/Contents/MacOS/TokenGalaxy"
CACHE_STAMP="$PREVIEW_ROOT/.build-fingerprint"
STATE_DIR="$PREVIEW_ROOT/State"
MODE=show
FORCE_BUILD=0
DURATION=15
WINDOW=10
PROVIDER=all
TASK_ID=""
DEMO_DIR=""
HAS_SAMPLE_OPTION=0
HAS_STATE_OPTION=0
typeset -A SEEN_OPTIONS

usage() {
  cat <<'HELP'
Usage: token_speed.sh [show|sample|demo|build] [options]

  show                         Open the native Token speed preview window (default).
  sample                       Print one local observation as JSON.
  demo OUTPUT_DIR              Render synthetic native demo screenshots.
  build                        Build or reuse the current local preview only.

Sample options:
  --seconds N                  Observe for 1..300 seconds (default: 15).
  --window N                   Rate window: 10, 30, or 60 seconds (default: 10).
  --provider NAME              all, codex, or claude (default: all).
  --task-id ID                 Select one task; requires codex or claude provider.

Show/sample options:
  --state-dir PATH             Set the startup preview status directory.

Common options:
  --build                      Force a fresh preview build.
  -h, --help                   Show this help without building or reading sessions.

Builds stay in plugins/token-galaxy/Outputs/TokenSpeedPreview. The launcher
checks source/build-input and app fingerprints before reusing a preview.
Sample stdout is JSON only; build messages go to stderr.
Show reuses an open preview; its startup status directory stays in effect.
HELP
}

fail_usage() {
  print -u2 -- "Token speed: $1"
  print -u2 -- 'Run token_speed.sh --help for usage.'
  exit 2
}

require_value() {
  (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail_usage "$1 requires a value."
}

mark_option() {
  [[ -z "${SEEN_OPTIONS[$1]-}" ]] || fail_usage "Duplicate option: $1."
  SEEN_OPTIONS[$1]=1
}

if (( $# )); then
  case "$1" in
    show|sample|demo|build) MODE="$1"; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) ;;
    *) fail_usage 'Unknown command.' ;;
  esac
fi

while (( $# )); do
  case "$1" in
    --seconds)
      mark_option "$1"
      require_value "$@"
      DURATION="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    --window)
      mark_option "$1"
      require_value "$@"
      WINDOW="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    --provider)
      mark_option "$1"
      require_value "$@"
      PROVIDER="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    --task-id)
      mark_option "$1"
      require_value "$@"
      TASK_ID="$2"; HAS_SAMPLE_OPTION=1; shift 2 ;;
    --state-dir)
      mark_option "$1"
      require_value "$@"
      STATE_DIR="$2"; HAS_STATE_OPTION=1; shift 2 ;;
    --build) mark_option "$1"; FORCE_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) fail_usage 'Unknown option.' ;;
    *)
      [[ "$MODE" == demo && -z "$DEMO_DIR" ]] || fail_usage 'Unexpected positional argument.'
      DEMO_DIR="$1"; shift ;;
  esac
done

[[ "$DURATION" =~ '^[0-9]{1,3}$' ]] || fail_usage '--seconds must be an integer from 1 to 300.'
(( 10#$DURATION >= 1 && 10#$DURATION <= 300 )) || fail_usage '--seconds must be from 1 to 300.'
DURATION="$((10#$DURATION))"
case "$WINDOW" in 10|30|60) ;; *) fail_usage '--window must be 10, 30, or 60.' ;; esac
case "$PROVIDER" in all|codex|claude) ;; *) fail_usage '--provider must be all, codex, or claude.' ;; esac
[[ -z "$TASK_ID" || "$PROVIDER" != all ]] || fail_usage '--task-id requires --provider codex or claude.'
[[ "$MODE" == sample || "$HAS_SAMPLE_OPTION" == 0 ]] || fail_usage 'Sampling options require the sample command.'
[[ "$MODE" == show || "$MODE" == sample || "$HAS_STATE_OPTION" == 0 ]] || fail_usage '--state-dir requires show or sample.'
[[ "$MODE" != demo || -n "$DEMO_DIR" ]] || fail_usage 'demo requires an output directory.'
STATE_DIR="${STATE_DIR:A}"
[[ -z "$DEMO_DIR" ]] || DEMO_DIR="${DEMO_DIR:A}"

[[ "$(uname -s)" == Darwin ]] || { print -u2 'Token speed requires macOS 15 or later.'; exit 1; }
MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
(( ${MACOS_VERSION%%.*} >= 15 )) || { print -u2 'Token speed requires macOS 15 or later.'; exit 1; }
BUILD_ARCH="${TOKEN_GALAXY_ARCH:-$(uname -m)}"
case "$BUILD_ARCH" in arm64|x86_64) ;; *) fail_usage 'TOKEN_GALAXY_ARCH must be arm64 or x86_64.' ;; esac
/usr/bin/xcrun --find swiftc >/dev/null || { print -u2 'Install Apple Command Line Tools: xcode-select --install'; exit 1; }
[[ "${PREVIEW_ROOT:A}" == "$PREVIEW_ROOT" && ! -L "$APP" ]] || {
  print -u2 'Refusing a preview output path that redirects through a symlink.'
  exit 1
}

source_fingerprint() {
  local -a inputs
  inputs=("$ROOT/build.sh" "$ROOT/scripts/prepare_sparkle.sh" "$ROOT/LICENSE" "$ROOT/NOTICE"
          "$ROOT"/Sources/**/*(.N) "$ROOT"/Resources/**/*(.N))
  {
    print -r -- "preview=1 architecture=$BUILD_ARCH"
    /usr/bin/xcode-select -p
    /usr/bin/xcrun --sdk macosx --show-sdk-version
    /usr/bin/xcrun swiftc --version
    /usr/bin/shasum -a 256 -- "${inputs[@]}"
  } | /usr/bin/shasum -a 256 | /usr/bin/cut -d ' ' -f 1
}

app_fingerprint() {
  local -a files
  files=("$APP"/**/*(.DN))
  (( ${#files} )) || return 1
  /usr/bin/shasum -a 256 -- "${files[@]}" | /usr/bin/shasum -a 256 | /usr/bin/cut -d ' ' -f 1
}

is_preview_bundle() {
  [[ -x "$BINARY" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)" == local.token-galaxy.speed-preview ]]
}

ensure_preview() {
  local source_before source_after combined_fingerprint
  source_before="$(source_fingerprint)"
  if (( ! FORCE_BUILD )) && [[ -f "$CACHE_STAMP" ]] && is_preview_bundle; then
    combined_fingerprint="$source_before"$'\n'"$(app_fingerprint)"
    [[ "$(<"$CACHE_STAMP")" == "$combined_fingerprint" ]] && return 0
  fi
  mkdir -p "$PREVIEW_ROOT"
  BUILD_LOCK="$PREVIEW_ROOT/.build-lock"
  mkdir "$BUILD_LOCK" 2>/dev/null || {
    print -u2 'Another Token speed preview build is in progress. Retry after it finishes.'
    exit 1
  }
  trap 'rmdir "$BUILD_LOCK" 2>/dev/null || true' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  rm -f -- "$CACHE_STAMP"
  print -u2 'Building the local Token speed preview…'
  TOKEN_GALAXY_PREVIEW=1 TOKEN_GALAXY_BUILD_DIR="$PREVIEW_ROOT" TOKEN_GALAXY_ARCH="$BUILD_ARCH" "$ROOT/build.sh" >&2
  is_preview_bundle || { print -u2 'Build did not produce the expected isolated preview bundle; refusing to launch.'; exit 1; }
  source_after="$(source_fingerprint)"
  [[ "$source_before" == "$source_after" ]] || {
    print -u2 'Build inputs changed during compilation. Retry when edits have finished.'
    exit 1
  }
  combined_fingerprint="$source_after"$'\n'"$(app_fingerprint)"
  print -r -- "$combined_fingerprint" > "$CACHE_STAMP.tmp.$$"
  mv -- "$CACHE_STAMP.tmp.$$" "$CACHE_STAMP"
  rmdir "$BUILD_LOCK"
  trap - EXIT INT TERM
}

ensure_preview
case "$MODE" in
  build) print -r -- "$APP" ;;
  show)
    /usr/bin/open "$APP" --args --speed-only --state-dir "$STATE_DIR"
    print 'Requested the native Token speed preview window.' ;;
  sample)
    args=(--speed-json --seconds "$DURATION" --window "$WINDOW" --provider "$PROVIDER" --state-dir "$STATE_DIR")
    [[ -z "$TASK_ID" ]] || args+=(--task-id "$TASK_ID")
    exec "$BINARY" "${args[@]}" ;;
  demo) exec "$BINARY" --speed-demo "$DEMO_DIR" ;;
esac
