#!/bin/bash
set -e

echo "Building Transcriberino.app..."

# Build the executable
swift build -c release

# Create .app bundle structure
APP_NAME="Transcriberino.app"
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

# Copy executable
cp .build/release/Transcriberino "$APP_NAME/Contents/MacOS/"

# Copy Info.plist
cp Transcriberino/Info.plist "$APP_NAME/Contents/"

# Copy pre-built .icns directly (no actool processing)
cp AppIcon.icns "$APP_NAME/Contents/Resources/AppIcon.icns"

# Code sign (ad-hoc)
codesign --force --deep --sign - "$APP_NAME"

echo "✓ Built: $APP_NAME"
echo "You can now run: open $APP_NAME"
