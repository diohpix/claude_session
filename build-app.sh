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

# 빌드하는 Mac에 설치된 Claude / Codex 앱의 아이콘을 번들에 담아 둔다.
# 그래야 해당 앱이 없는 PC에서도 같은 아이콘이 보인다.
bundle_icon() {
    local name=$1; shift
    local id app iconfile
    for id in "$@"; do
        app=$(mdfind "kMDItemCFBundleIdentifier == '$id'" 2>/dev/null | head -1)
        [[ -z "$app" ]] && for c in /Applications/*.app ~/Applications/*.app(N); do
            [[ $(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$c/Contents/Info.plist" 2>/dev/null) == "$id" ]] && app=$c && break
        done
        [[ -z "$app" ]] && continue
        iconfile=$(/usr/libexec/PlistBuddy -c "Print CFBundleIconFile" "$app/Contents/Info.plist" 2>/dev/null) || continue
        [[ "$iconfile" == *.icns ]] || iconfile="$iconfile.icns"
        if sips -s format png -Z 128 "$app/Contents/Resources/$iconfile" --out "$APP/Contents/Resources/$name.png" >/dev/null 2>&1; then
            echo "아이콘 포함: $name ← $app"
            return
        fi
    done
    echo "경고: $name 아이콘을 찾지 못함 (기호로 대신 표시됨)"
}
bundle_icon source-claude com.anthropic.claudefordesktop
bundle_icon source-codex com.openai.codex com.openai.chat

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
