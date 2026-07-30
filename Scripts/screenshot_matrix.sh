#!/usr/bin/env bash
#
# screenshot_matrix.sh — snapshot every tool screen across a device / appearance
# / Dynamic-Type matrix, for layout QA.
#
# It drives the app through its own deep-link launch arguments
# (`-openTool <tool> -skipOnboarding`), so each run lands straight on a tool
# screen with onboarding out of the way. Appearance and Dynamic Type are set
# with `simctl ui appearance` / `simctl ui content_size`, so no code changes are
# needed to sweep light/dark and text sizes.
#
# Output is a tree of PNGs plus an index.html contact sheet:
#   <out>/<device>/<appearance>/<content-size>/<tool>.png
#
# Examples:
#   Scripts/screenshot_matrix.sh                      # iPhone 17 Pro, light+dark, size "large"
#   Scripts/screenshot_matrix.sh --tools "ping dns tlsInspector"
#   Scripts/screenshot_matrix.sh --sizes "large accessibility-extra-large"
#   Scripts/screenshot_matrix.sh --device "iPad Pro 13-inch (M5)" --appearances dark
#   Scripts/screenshot_matrix.sh --lang de            # long-translation clipping check
#   Scripts/screenshot_matrix.sh --full                # every tool, both appearances, two sizes
#
# --lang takes an AppLanguage raw value: en ru de fr es it ja ko tr ar hi zhHans ptBR.
# It sets the app's own in-app language (the reliable lever for this app); omit it
# to use whatever language the simulator is already configured for.
#
set -euo pipefail

# ── Locations ────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUNDLE_ID="com.chrsnv.checknet"
SCHEME="CheckNet"
PROJECT="CheckNet.xcodeproj"
DERIVED="build"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/CheckNet.app"
TOOL_SOURCE="App/Catalog/Tool.swift"

# ── Defaults (override via flags) ────────────────────────────────────────────
DEVICE_NAME="iPhone 17 Pro"
UDID=""
APPEARANCES="light dark"
SIZES="large"
TOOLS=""                # empty → all tools from Tool.swift
LANG_CODE=""            # e.g. ru, de, ar — empty keeps the sim's own language
OUT="screens/matrix"
SETTLE=3                # seconds to let a screen render before the shot
RUN=0                   # add -run to auto-start the check (non-deterministic; off by default)
DO_BUILD=1
INCLUDE_CATALOG=1       # also snap the catalog root per appearance/size

usage() { sed -n '2,25p' "$0"; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)       DEVICE_NAME="$2"; shift 2 ;;
    --udid)         UDID="$2"; shift 2 ;;
    --appearances)  APPEARANCES="$2"; shift 2 ;;
    --sizes)        SIZES="$2"; shift 2 ;;
    --tools)        TOOLS="$2"; shift 2 ;;
    --lang)         LANG_CODE="$2"; shift 2 ;;
    --out)          OUT="$2"; shift 2 ;;
    --settle)       SETTLE="$2"; shift 2 ;;
    --run)          RUN=1; shift ;;
    --no-build)     DO_BUILD=0; shift ;;
    --no-catalog)   INCLUDE_CATALOG=0; shift ;;
    --full)         APPEARANCES="light dark"; SIZES="large accessibility-extra-large"; TOOLS=""; shift ;;
    -h|--help)      usage 0 ;;
    *) echo "Unknown flag: $1" >&2; usage 1 ;;
  esac
done

log() { printf '\033[1;36m•\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }

# ── Resolve the tool list from the source of truth ───────────────────────────
# Pull the `case …` lines between `enum Tool` and its `var id`, so the matrix
# never drifts from the actual enum. Comment lines (// Reachability) are ignored.
if [[ -z "$TOOLS" ]]; then
  TOOLS="$(awk '
    /enum Tool/            { in_enum=1 }
    in_enum && /var id/    { exit }
    in_enum && /^[[:space:]]*case[[:space:]]/ {
      sub(/\/\/.*/, "")            # strip trailing comments
      sub(/^[[:space:]]*case[[:space:]]+/, "")
      gsub(/[[:space:]]/, "")
      n = split($0, a, ",")
      for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
    }
  ' "$TOOL_SOURCE" | tr '\n' ' ')"
fi
read -r -a TOOL_ARR <<< "$TOOLS"
if [[ ${#TOOL_ARR[@]} -eq 0 ]]; then
  echo "No tools resolved from $TOOL_SOURCE — pass --tools explicitly." >&2
  exit 1
fi

# ── Resolve the simulator UDID ───────────────────────────────────────────────
if [[ -z "$UDID" ]]; then
  # The trailing " (" disambiguates "iPhone 17 Pro" from "iPhone 17 Pro Max".
  # UUIDs are 36-char uppercase hex-with-dashes; grep keeps this awk-portable.
  UDID="$(xcrun simctl list devices available \
    | grep -F "$DEVICE_NAME (" | head -1 \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)"
fi
if [[ -z "$UDID" ]]; then
  echo "Could not find an available simulator named \"$DEVICE_NAME\"." >&2
  echo "Available:" >&2
  xcrun simctl list devices available | grep -iE "iphone|ipad" >&2
  exit 1
fi
DEVICE_SLUG="$(echo "$DEVICE_NAME" | tr ' ' '-' | tr -cd 'A-Za-z0-9-')"
# The app drives its own language: a Bundle.main swap (App/Common/LanguageBundle)
# reads the in-app choice `checknet.language` and defeats the standard
# `-AppleLanguages` argument override, so we set the app's own preference instead
# (via cfprefsd, which the app reads — a direct plist write is cache-stale).
# Codes are AppLanguage raw values: en ru de fr es it ja ko tr ar hi zhHans ptBR.
[[ -n "$LANG_CODE" ]] && DEVICE_SLUG="$DEVICE_SLUG-$LANG_CODE"
log "Device: $DEVICE_NAME ($UDID)${LANG_CODE:+ · lang $LANG_CODE}"
log "Tools (${#TOOL_ARR[@]}): ${TOOL_ARR[*]}"
log "Appearances: $APPEARANCES · Sizes: $SIZES · Run: $RUN"

# ── Build once (one iphonesimulator product serves iPhone and iPad sims) ──────
if [[ "$DO_BUILD" -eq 1 || ! -d "$APP_PATH" ]]; then
  log "Building $SCHEME for simulator…"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" build >/tmp/checknet-matrix-build.log 2>&1 \
    || { echo "Build failed — see /tmp/checknet-matrix-build.log"; tail -20 /tmp/checknet-matrix-build.log; exit 1; }
fi
[[ -d "$APP_PATH" ]] || { echo "App not found at $APP_PATH"; exit 1; }

# ── Boot + install ───────────────────────────────────────────────────────────
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
log "Installing app…"
xcrun simctl install "$UDID" "$APP_PATH"
# Try to pre-grant location so its permission alert never covers a screen
# mid-shot (current-Wi-Fi / Wi-Fi analysis raise it; a stale alert then bleeds
# onto later tools). `simctl privacy grant location` is best-effort — on some
# runtimes CoreLocation ignores it. If a location alert still appears, answer it
# once by hand ("При использовании приложения"); the choice persists on the
# simulator, so every later run stays clean.
xcrun simctl privacy "$UDID" grant location-always "$BUNDLE_ID" >/dev/null 2>&1 || true
# Set the in-app language through cfprefsd so every cold launch below reads it.
if [[ -n "$LANG_CODE" ]]; then
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" checknet.language -string "$LANG_CODE" >/dev/null 2>&1 \
    || warn "could not set checknet.language=$LANG_CODE"
fi

shoot() { # <appearance> <size> <label> [launch-args…]
  local appear="$1" size="$2" label="$3"; shift 3
  local dir="$OUT/$DEVICE_SLUG/$appear/$size"
  mkdir -p "$dir"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -skipOnboarding "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot "$dir/$label.png" >/dev/null 2>&1
  printf '  %-24s %s/%s\n' "$label" "$appear" "$size"
}

# ── Sweep the matrix ─────────────────────────────────────────────────────────
for appear in $APPEARANCES; do
  xcrun simctl ui "$UDID" appearance "$appear" >/dev/null 2>&1 || warn "appearance $appear not supported"
  for size in $SIZES; do
    xcrun simctl ui "$UDID" content_size "$size" >/dev/null 2>&1 || warn "content_size $size not supported"
    log "Sweeping $appear / $size"
    [[ "$INCLUDE_CATALOG" -eq 1 ]] && shoot "$appear" "$size" "00-catalog"
    for tool in "${TOOL_ARR[@]}"; do
      if [[ "$RUN" -eq 1 ]]; then
        shoot "$appear" "$size" "$tool" -openTool "$tool" -run
      else
        shoot "$appear" "$size" "$tool" -openTool "$tool"
      fi
    done
  done
done

# reset the sim to defaults so a later manual run isn't stuck on huge text /
# a forced language
xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1 || true
[[ -n "$LANG_CODE" ]] && xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" checknet.language -string system >/dev/null 2>&1 || true

# ── Contact sheet ────────────────────────────────────────────────────────────
INDEX="$OUT/index.html"
{
  echo '<!doctype html><meta charset="utf-8"><title>CheckNet layout matrix</title>'
  echo '<style>body{font:14px -apple-system,sans-serif;margin:24px;background:#111;color:#eee}'
  echo 'h2{margin-top:32px}.row{display:flex;flex-wrap:wrap;gap:16px}'
  echo 'figure{margin:0}img{width:220px;border:1px solid #333;border-radius:8px;background:#000}'
  echo 'figcaption{font-size:12px;color:#aaa;margin-top:4px;text-align:center}</style>'
  echo "<h1>CheckNet layout matrix — $DEVICE_SLUG</h1>"
  for appear in $APPEARANCES; do
    for size in $SIZES; do
      echo "<h2>$appear · $size</h2><div class=row>"
      for f in "$OUT/$DEVICE_SLUG/$appear/$size"/*.png; do
        [[ -e "$f" ]] || continue
        rel="${f#$OUT/}"
        echo "<figure><a href=\"$rel\"><img src=\"$rel\"></a><figcaption>$(basename "$f" .png)</figcaption></figure>"
      done
      echo "</div>"
    done
  done
} > "$INDEX"

COUNT="$(find "$OUT/$DEVICE_SLUG" -name '*.png' | wc -l | tr -d ' ')"
log "Done: $COUNT screenshots → $OUT"
log "Contact sheet: $INDEX"
