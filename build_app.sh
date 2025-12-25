#!/bin/bash

# SSHTools macOS App Bundle Builder
# This script compiles the project and packages it into a .app bundle.

set -e

APP_NAME="SSHTools"
BUNDLE_ID="com.sshtools.macos"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE_NAME="SSHTools"

echo "🚀 Starting build process for $APP_NAME..."

# 1. Build the executable using Swift Package Manager
echo "📦 Compiling executable..."
swift build -c release --arch arm64 --arch x86_64

# 2. Create the bundle structure
echo "🏗️  Creating .app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy the executable
# The release path might vary depending on the environment, but standard SPM release path is used here.
BINARY_PATH=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$EXECUTABLE_NAME

if [ -f "$BINARY_PATH" ]; then
    cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/"
else
    echo "❌ Error: Could not find compiled binary at $BINARY_PATH"
    exit 1
fi

# 4. Copy Resources
echo "🖼️  Adding assets..."
if [ -f "Sources/SSHTools/AppIcon.icns" ]; then
    cp "Sources/SSHTools/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy SPM generated resource bundles
# Finding the build directory used by SPM (it might vary slightly based on platform)
SPM_BUILD_DIR=".build/apple/Products/Release"
if [ ! -d "$SPM_BUILD_DIR" ]; then
    # Fallback for some environments
    SPM_BUILD_DIR=".build/release" 
fi

if [ -d "$SPM_BUILD_DIR/SSHTools_SSHTools.bundle" ]; then
    echo "   - Copying SSHTools resources..."
    cp -R "$SPM_BUILD_DIR/SSHTools_SSHTools.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# Also check for other dependency bundles (like SwiftTerm or others if they generate bundles)
for bundle in "$SPM_BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ] && [ "$(basename "$bundle")" != "SSHTools_SSHTools.bundle" ]; then
        echo "   - Copying dependency resource: $(basename "$bundle")..."
        cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    fi
done

# 5. Create Info.plist
echo "📝 Generating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 6. Codesign (Ad-hoc signing)
echo "🔐 Codesigning..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Success! Application bundle created at: $APP_BUNDLE"
echo "📂 You can now move it to your Applications folder or run it directly."
