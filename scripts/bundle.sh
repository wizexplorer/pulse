#!/bin/zsh
# Builds Pulse in release mode and wraps it in a signed .app bundle at build/Pulse.app.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Pulse.app"

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Pulse"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pulse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[[ "$CONFIG" == "release" ]] && strip -x "$APP/Contents/MacOS/Pulse"

# macOS ties the Accessibility grant to the code signature. An ad-hoc signature changes on every
# build, which silently revokes the grant; a stable self-signed identity keeps it across rebuilds.
# Create one with scripts/create-signing-identity.sh (or override with SIGN_IDENTITY=...).
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"Pulse Developer"'; then
    IDENTITY="Pulse Developer"
fi
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc (Accessibility must be re-granted after each rebuild; see README)."
fi
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
