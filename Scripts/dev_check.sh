#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/BarShelf.app"
APP_PROCESS="BarShelfApp"
CLI="$APP_DIR/Contents/MacOS/barshelf"
ARTIFACT_DIR="${BARSHELF_PEEKABOO_DIR:-$ROOT_DIR/tmp/peekaboo}"
KEEP_APP="${BARSHELF_KEEP_APP:-0}"

with_timeout() {
  local seconds="$1"
  shift
  /usr/bin/perl -e "alarm $seconds; exec @ARGV" "$@"
}

cleanup() {
  if [[ "$KEEP_APP" != "1" ]]; then
    pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cd "$ROOT_DIR"
mkdir -p "$ARTIFACT_DIR"

echo "==> Running Swift tests"
swift test --configuration debug --enable-code-coverage

echo "==> Building app bundle"
./Scripts/build_app.sh

if [[ ! -x "$CLI" ]]; then
  echo "Expected CLI not found at $CLI" >&2
  exit 1
fi

if ! command -v peekaboo >/dev/null 2>&1; then
  echo "Peekaboo is not installed. Install with: brew install steipete/tap/peekaboo" >&2
  exit 1
fi

echo "==> Checking Peekaboo permissions"
peekaboo permissions status --all-sources | tee "$ARTIFACT_DIR/permissions.txt"
if ! grep -Eq "Screen Recording .*Granted|Screen Recording \\(Required\\): Granted" "$ARTIFACT_DIR/permissions.txt"; then
  echo "Peekaboo needs Screen Recording permission before visual checks can run." >&2
  exit 2
fi
if ! grep -Eq "Accessibility .*Granted|Accessibility \\(Required\\): Granted" "$ARTIFACT_DIR/permissions.txt"; then
  echo "Accessibility is not granted; continuing with screenshot/window checks only." >&2
fi

echo "==> Launching BarShelf"
pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true
open -n "$APP_DIR"

for _ in {1..30}; do
  if pgrep -x "$APP_PROCESS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if ! pgrep -x "$APP_PROCESS" >/dev/null 2>&1; then
  echo "BarShelf did not launch." >&2
  exit 1
fi

echo "==> Exercising bundled CLI"
with_timeout 5 "$CLI" status --json > "$ARTIFACT_DIR/status.json"
with_timeout 5 "$CLI" open-settings > "$ARTIFACT_DIR/open-settings.txt"

echo "==> Waiting for a BarShelf window"
WINDOW_TITLE=""
for _ in {1..30}; do
  peekaboo window list --app BarShelf --json > "$ARTIFACT_DIR/windows.json"
  if grep -q '"window_title"[[:space:]]*:[[:space:]]*"BarShelf Settings"' "$ARTIFACT_DIR/windows.json"; then
    WINDOW_TITLE="BarShelf Settings"
    break
  fi
  if grep -q '"window_title"[[:space:]]*:[[:space:]]*"Set up BarShelf"' "$ARTIFACT_DIR/windows.json"; then
    WINDOW_TITLE="Set up BarShelf"
    break
  fi
  sleep 0.5
done

if [[ -z "$WINDOW_TITLE" ]]; then
  echo "No BarShelf setup/settings window was found." >&2
  cat "$ARTIFACT_DIR/windows.json" >&2
  exit 1
fi

echo "==> Capturing $WINDOW_TITLE"
peekaboo image \
  --app BarShelf \
  --window-title "$WINDOW_TITLE" \
  --path "$ARTIFACT_DIR/barshelf-window.png" \
  --json > "$ARTIFACT_DIR/capture.json"

if [[ ! -s "$ARTIFACT_DIR/barshelf-window.png" ]]; then
  echo "Peekaboo did not produce a screenshot." >&2
  exit 1
fi

sips -g pixelWidth -g pixelHeight "$ARTIFACT_DIR/barshelf-window.png" > "$ARTIFACT_DIR/image-info.txt" 2>/dev/null
cat "$ARTIFACT_DIR/image-info.txt"

echo "==> Capturing menu bar state"
peekaboo list menubar --json > "$ARTIFACT_DIR/menubar.json" || true
peekaboo image --app menubar --path "$ARTIFACT_DIR/menubar.png" --json > "$ARTIFACT_DIR/menubar-capture.json" || true

echo "Visual smoke check passed. Artifacts: $ARTIFACT_DIR"
