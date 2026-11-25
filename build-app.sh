#!/bin/zsh
# 릴리스 빌드 후 "AI Sessions.app" 번들을 만든다.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="AI Sessions.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeSessions "$APP/Contents/MacOS/ClaudeSessions"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # scripts/make-icon.swift 로 생성

# 세션 목록의 Claude / Codex 아이콘 (Lobe Icons, MIT). 해당 앱이 설치된 Mac에서는 설치된 앱의 아이콘이 먼저 쓰인다.
cp Resources/SourceIcons/source-*.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AI Sessions</string>
    <key>CFBundleDisplayName</key><string>AI Sessions</string>
    <key>CFBundleIdentifier</key><string>local.claude-sessions</string>
    <key>CFBundleExecutable</key><string>ClaudeSessions</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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
