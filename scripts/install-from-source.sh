#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="OpenWispr"
BUNDLE_ID="com.human37.open-wispr"
LABEL="$BUNDLE_ID"
APP_DIR="$HOME/Applications/$APP_NAME.app"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PATH="$AGENT_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/OpenWispr"
BUILD_DIR="$REPO_ROOT/.build"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openwispr-install.XXXXXX")"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "OpenWispr requires macOS."
fi

if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew is required. Install it from https://brew.sh, then run this script again."
fi

if ! command -v swift >/dev/null 2>&1; then
    fail "Swift is required. Install Xcode Command Line Tools with: xcode-select --install"
fi

if ! brew list --versions whisper-cpp >/dev/null 2>&1; then
    printf 'Installing whisper-cpp with Homebrew...\n'
    brew install whisper-cpp
fi

VERSION="$(sed -nE 's/^[[:space:]]*static let version = "([^"]+)"/\1/p' "$REPO_ROOT/Sources/OpenWispr/main.swift" | head -1)"
[[ -n "$VERSION" ]] || fail "Could not read the application version from Sources/OpenWispr/main.swift."

printf 'Building OpenWispr %s...\n' "$VERSION"
swift build --package-path "$REPO_ROOT" -c release

BUNDLE_PATH="$TEMP_DIR/$APP_NAME.app"
bash "$REPO_ROOT/scripts/bundle-app.sh" \
    "$BUILD_DIR/release/open-wispr" "$BUNDLE_PATH" "$VERSION"

mkdir -p "$HOME/Applications" "$AGENT_DIR" "$LOG_DIR"
printf 'Installing %s...\n' "$APP_DIR"

# Stop a previous LaunchAgent before replacing its executable.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -TERM -x open-wispr 2>/dev/null || true
sleep 1
rm -rf "$APP_DIR"
ditto "$BUNDLE_PATH" "$APP_DIR"

cat > "$AGENT_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_DIR/Contents/MacOS/open-wispr</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/app.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/error.log</string>
</dict>
</plist>
PLIST

plutil -lint "$AGENT_PATH" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$AGENT_PATH"

cat <<EOF2

OpenWispr is installed and starts when you log in.

Finish first-time setup in macOS System Settings:
  1. Allow microphone access when prompted.
  2. In Privacy & Security > Accessibility, enable OpenWispr.
  3. If the Globe/Fn key opens emoji or switches input language, disable that
     assignment in Keyboard or your input method settings.

The small Whisper model downloads automatically on first launch. The menu bar
icon changes to the waveform when setup is complete. Choose Quit in that menu
when you want to stop OpenWispr; it stays closed until you open it from the Dock
or log in again.

Logs: $LOG_DIR/app.log
EOF2
