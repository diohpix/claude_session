#!/bin/zsh
# 릴리스 빌드 후 ClaudeSessions.app 번들을 만든다.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="ClaudeSessions.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeSessions "$APP/Contents/MacOS/ClaudeSessions"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude 세션</string>
    <key>CFBundleDisplayName</key><string>Claude 세션</string>
    <key>CFBundleIdentifier</key><string>local.claude-sessions</string>
    <key>CFBundleExecutable</key><string>ClaudeSessions</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "완료: $(pwd)/$APP"
