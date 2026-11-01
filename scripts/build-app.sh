#!/bin/bash
# Builds build/Secure My Mac.app (signed for local use only).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/SecureMyMac"
APP="build/Secure My Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SecureMyMac"
cp -R Resources/en.lproj Resources/tr.lproj Resources/alert.wav "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Secure My Mac</string>
<key>CFBundleDisplayName</key><string>Secure My Mac</string>
<key>CFBundleIdentifier</key><string>com.local.SecureMyMac</string>
<key>CFBundleExecutable</key><string>SecureMyMac</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Secure My Mac uses Messages to send the security alerts you enable. / Secure My Mac, açtığınız güvenlik uyarılarını Mesajlar ile gönderir.</string>
</dict></plist>
PLIST
# A stable signing identity keeps Keychain and Full Disk Access permissions across rebuilds.
# Falls back to ad-hoc signing (permissions are asked again after every build).
IDENTITY="Secure My Mac Local"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc (no '$IDENTITY' certificate found)"
fi
echo "OK: $APP"
