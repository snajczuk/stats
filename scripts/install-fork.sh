#!/bin/bash
#
# Builds this fork, signs it with your Apple Development certificate and installs it
# into /Applications, replacing what's there (the old copy goes to the Trash).
#
# Which certificate to sign with is personal, so it isn't stored in the repo. Set it once:
#   echo 'Apple Development: Your Name (ABCDE12345)' > scripts/signing.local
# or pass it for one run:
#   STATS_SIGN_IDENTITY='Apple Development: …' scripts/install-fork.sh
# List the certificates on this Mac with:
#   security find-identity -v -p codesigning
#
# Only the certificate's name is used. Its private key stays in your Keychain.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/install-fork"   # build/ is already ignored by git
APP="$BUILD/Build/Products/Release/Stats.app"
DEST="/Applications/Stats.app"

# --- which certificate ---------------------------------------------------------------
IDENTITY="${STATS_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f "$ROOT/scripts/signing.local" ]]; then
    IDENTITY="$(head -n 1 "$ROOT/scripts/signing.local")"
fi
if [[ -z "$IDENTITY" ]]; then
    echo "No signing certificate set. Pick one of these and save its name to scripts/signing.local:"
    security find-identity -v -p codesigning
    exit 1
fi
# the team ID is the certificate's OU field; the app's entitlements need it
TEAM="$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject -nameopt multiline | awk -F' = ' '/organizationalUnitName/ {print $2; exit}')"
if [[ -z "$TEAM" ]]; then
    echo "Couldn't find the certificate \"$IDENTITY\" in your Keychain."
    exit 1
fi
echo "Signing with: $IDENTITY (team $TEAM)"

# --- build ---------------------------------------------------------------------------
# Built unsigned: the project is set up for upstream's team and app IDs, so Xcode can't
# sign it with yours. It's signed below instead.
echo "Building…"
xcodebuild -project "$ROOT/Stats.xcodeproj" -scheme Stats -configuration Release \
    -derivedDataPath "$BUILD" build CODE_SIGNING_ALLOWED=NO -quiet

# --- sign, innermost parts first -----------------------------------------------------
echo "Signing…"
ENT="$(mktemp -d)"
trap 'rm -rf "$ENT"' EXIT
# the entitlement files use Xcode's $(TeamIdentifierPrefix), which only Xcode fills in
sed "s/\$(TeamIdentifierPrefix)/$TEAM./" "$ROOT/Stats/Supporting Files/Stats.entitlements" > "$ENT/app.plist"
sed "s/\$(TeamIdentifierPrefix)/$TEAM./" "$ROOT/Widgets/Supporting Files/Widgets.entitlements" > "$ENT/widgets.plist"
cp "$ROOT/LaunchAtLogin/LaunchAtLogin.entitlements" "$ENT/login.plist"

sign() { codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$@" 2>&1 | grep -v "replacing existing signature" || true; }

# frameworks, deepest first (the widget extension carries its own copies)
find "$APP" -name "*.framework" -type d | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2- |
    while IFS= read -r framework; do sign "$framework"; done
for helper in "$APP"/Contents/Library/LaunchServices/*; do sign "$helper"; done
sign --entitlements "$ENT/login.plist" "$APP/Contents/Library/LoginItems/LaunchAtLogin.app"
sign --entitlements "$ENT/widgets.plist" "$APP/Contents/PlugIns/WidgetsExtension.appex"
sign --entitlements "$ENT/app.plist" "$APP"
codesign --verify --deep --strict "$APP"

# --- install ---------------------------------------------------------------------------
echo "Installing…"
osascript -e 'quit app "Stats"' 2>/dev/null || true
for _ in {1..50}; do pgrep -qf "Stats.app/Contents/MacOS/Stats" || break; sleep 0.2; done
pkill -f "Stats.app/Contents/MacOS/Stats" 2>/dev/null || true

if [[ -d "$DEST" ]]; then
    OLD="$HOME/.Trash/Stats $(date '+%Y-%m-%d %H.%M.%S').app"
    mv "$DEST" "$OLD"
    echo "Previous version moved to the Trash: $(basename "$OLD")"
fi
ditto "$APP" "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
