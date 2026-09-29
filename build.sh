#!/bin/zsh
# Builds Wheedgets.app: compiles with SwiftPM, assembles the bundle and signs it.
#
#   ./build.sh              release build → build/Wheedgets.app
#   ./build.sh --run        …and launch it
#   ./build.sh --install    …copy to /Applications and launch from there
#   ./build.sh --universal  arm64 + x86_64 binary (for published releases)
#
# Signing, in order of preference:
#   1. "Developer ID Application" certificate (hardened runtime + timestamp; notarizable)
#   2. the stable local identity from Tools/setup-signing.sh
#   3. ad-hoc — works, but macOS drops the Accessibility grant on every rebuild
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Wheedgets"
LOCAL_IDENTITY="Wheedgets Local Signing"
LOCAL_KEYCHAIN="$HOME/Library/Keychains/wheedgets-signing.keychain-db"
LOCAL_KEYCHAIN_PASSWORD="wheedgets-signing"

RUN=0
INSTALL=0
UNIVERSAL=0
for arg in "$@"; do
    case "$arg" in
        --run) RUN=1 ;;
        --install) INSTALL=1 ;;
        --universal) UNIVERSAL=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 64 ;;
    esac
done

ARCH_FLAGS=()
(( UNIVERSAL )) && ARCH_FLAGS=(--arch arm64 --arch x86_64)

echo "▸ Compiling…"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

# Stage outside the project: folders synced by iCloud/File Provider (Desktop,
# Documents) attach extended attributes that make codesign fail.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/$APP_NAME.app"

echo "▸ Assembling bundle…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi
xattr -cr "$APP"

developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/' || true
}

local_identity_works() {
    security unlock-keychain -p "$LOCAL_KEYCHAIN_PASSWORD" "$LOCAL_KEYCHAIN" 2>/dev/null || true
    local probe
    probe="$(mktemp)"
    cp /usr/bin/true "$probe"
    local result=1
    codesign --force --sign "$LOCAL_IDENTITY" "$probe" >/dev/null 2>&1 && result=0
    rm -f "$probe"
    return $result
}

echo "▸ Signing…"
DEVELOPER_ID="$(developer_id_identity)"
if [[ -n "$DEVELOPER_ID" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
    echo "  Developer ID: $DEVELOPER_ID"
elif local_identity_works; then
    codesign --force --options runtime --sign "$LOCAL_IDENTITY" "$APP"
    echo "  Local identity: $LOCAL_IDENTITY"
else
    codesign --force --options runtime --sign - "$APP"
    echo "  ⚠ Ad-hoc signature. Accessibility access will reset after each rebuild." >&2
    echo "    Run ./Tools/setup-signing.sh once to create a stable local identity." >&2
fi
codesign --verify --strict "$APP"

mkdir -p build
rm -rf "build/$APP_NAME.app"
ditto "$APP" "build/$APP_NAME.app"
echo "✓ build/$APP_NAME.app"

TARGET="build/$APP_NAME.app"
if (( INSTALL )); then
    pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP" "/Applications/$APP_NAME.app"
    TARGET="/Applications/$APP_NAME.app"
    echo "✓ Installed to $TARGET"
fi

if (( RUN || INSTALL )); then
    pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
    open "$TARGET"
fi
