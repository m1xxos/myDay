#!/bin/bash
set -e

# Close any running instance to release file locks & prevent macOS TCC permission caching issues
if pgrep -x "MyDay" > /dev/null 2>&1; then
    echo "🛑 Terminating currently running MyDay instance to avoid code signature invalidation..."
    pkill -x "MyDay" || true
    sleep 0.5
fi

echo "🔨 Building release binary for MyDay..."
swift build -c release

BIN_PATH=$(find .build -type f -name MyDay -perm +111 | grep -i release | head -n 1)
if [ -z "$BIN_PATH" ]; then
    BIN_PATH=$(find .build -type f -name MyDay -perm +111 | head -n 1)
fi

echo "Found binary at: $BIN_PATH"

APP_DIR="MyDay.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating $APP_DIR bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/MyDay"
chmod +x "$MACOS_DIR/MyDay"

# Ensure icon exists
if [ ! -f "Resources/AppIcon.icns" ]; then
    echo "🎨 Generating AppIcon.icns..."
    swift scripts/generate_icon.swift
fi

cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MyDay</string>
    <key>CFBundleIdentifier</key>
    <string>com.m1xxos.myday</string>
    <key>CFBundleName</key>
    <string>MyDay</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MyDay использует запись экрана для создания автоматического таймлайна вашей работы.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MyDay определяет активные окна приложений для каталогизации рабочего времени.</string>
</dict>
</plist>
EOF

echo "🔐 Codesigning $APP_DIR with stable bundle identifier com.m1xxos.myday..."
codesign --force --deep --sign - --identifier "com.m1xxos.myday" -r='designated => identifier "com.m1xxos.myday"' "$APP_DIR"

# Touch bundle to notify Finder / LaunchServices of icon update
touch "$APP_DIR"

echo "✅ Successfully created and signed $APP_DIR with custom AppIcon!"
echo "🚀 You can now launch it via: open MyDay.app"
