#!/bin/bash
# mpv-infused installer: Homebrew mpv + config + scripts + a Finder-friendly mpv.app.
# Safe to re-run: personal settings (OpenSubtitles key, saved window position) are never overwritten.
#
#   ./install.sh            install everything
#   ./install.sh --no-app   skip building /Applications/mpv.app
#
# Environment overrides (mainly for testing): MPV_CONFIG_DIR, MPV_APP_DIR

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CONF="${MPV_CONFIG_DIR:-$HOME/.config/mpv}"
APP_DIR="${MPV_APP_DIR:-/Applications}"
BUILD_APP=1
[ "${1:-}" = "--no-app" ] && BUILD_APP=0

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "mpv-infused is for macOS"
command -v brew >/dev/null || die "Homebrew is required: https://brew.sh"
command -v swiftc >/dev/null || die "Xcode Command Line Tools are required: xcode-select --install"

if ! brew list --formula mpv >/dev/null 2>&1; then
    say "Installing mpv from Homebrew"
    brew install mpv
fi
MPV="$(brew --prefix)/bin/mpv"
[ -x "$MPV" ] || die "mpv not found at $MPV"

# Back up an existing config once, before the first install touches it.
if [ -d "$CONF" ] && [ ! -f "$CONF/.mpv-infused" ]; then
    backup="$CONF.backup-$(date +%Y%m%d-%H%M%S)"
    say "Backing up existing config to $backup"
    cp -Rp "$CONF" "$backup"
fi

say "Installing config and scripts into $CONF"
mkdir -p "$CONF/scripts" "$CONF/script-opts" "$CONF/bin"
cp "$REPO/config/mpv.conf" "$REPO/config/input.conf" "$CONF/"
cp "$REPO"/config/scripts/*.lua "$CONF/scripts/"
cp "$REPO/config/script-opts/context_menu.conf" "$CONF/script-opts/"
if [ ! -f "$CONF/script-opts/opensubtitles.conf" ]; then
    cp "$REPO/config/script-opts/opensubtitles.conf.example" "$CONF/script-opts/opensubtitles.conf"
    chmod 600 "$CONF/script-opts/opensubtitles.conf"
fi
[ -f "$CONF/window-geometry.conf" ] || printf '# Written by scripts/remember-window.lua\n' > "$CONF/window-geometry.conf"
touch "$CONF/.mpv-infused"

say "Building the window-position helper"
swiftc -O -o "$CONF/bin/mpv-winbounds" "$REPO/tools/mpv-winbounds.swift"

if [ "$BUILD_APP" = 1 ]; then
    APP="$APP_DIR/mpv.app"
    say "Building $APP"
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$REPO/app/Info.plist" "$APP/Contents/"
    sed "s#/opt/homebrew/bin/mpv#$MPV#" "$REPO/app/launcher.c" > "$work/launcher.c"
    clang -O2 -mmacosx-version-min=11.0 -o "$APP/Contents/MacOS/mpv" "$work/launcher.c"

    # Icon from mpv's own SVG, drawn on the macOS icon grid.
    svg="$(brew --prefix mpv)/share/icons/hicolor/scalable/apps/mpv.svg"
    if [ -f "$svg" ]; then
        swift "$REPO/app/render-icon.swift" "$svg" "$work/icon1024.png"
        mkdir "$work/mpv.iconset"
        for s in 16 32 128 256 512; do
            sips -z $s $s "$work/icon1024.png" --out "$work/mpv.iconset/icon_${s}x${s}.png" >/dev/null
            sips -z $((s*2)) $((s*2)) "$work/icon1024.png" --out "$work/mpv.iconset/icon_${s}x${s}@2x.png" >/dev/null
        done
        iconutil -c icns "$work/mpv.iconset" -o "$APP/Contents/Resources/mpv.icns"
    fi

    codesign --force --deep --sign - "$APP"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
fi

say "Done."
if ! grep -q '^api_key=.' "$CONF/script-opts/opensubtitles.conf"; then
    echo "    Next: add your free OpenSubtitles API key to $CONF/script-opts/opensubtitles.conf"
fi
