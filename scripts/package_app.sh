#!/bin/bash
set -e

echo "Packaging Vaaka..."

# Create app bundle structure
mkdir -p build/Vaaka.app/Contents/MacOS
mkdir -p build/Vaaka.app/Contents/Resources

# Use release build if it exists, otherwise debug
if [ -f .build/release/Vaaka ]; then
    cp .build/release/Vaaka build/Vaaka.app/Contents/MacOS/Vaaka
    echo "Using release build"
elif [ -f .build/debug/Vaaka ]; then
    cp .build/debug/Vaaka build/Vaaka.app/Contents/MacOS/Vaaka
    echo "Using debug build"
else
    echo "Error: No built executable found. Run 'swift build' first."
    exit 1
fi

# Make executable
chmod +x build/Vaaka.app/Contents/MacOS/Vaaka

# Copy resources
if [ -d Resources ]; then
    cp -R Resources/ build/Vaaka.app/Contents/Resources/
fi

# Use the SwiftPM target resource as the single source of truth for default sites
if [ -f Sources/Vaaka/Resources/whitelist.json ]; then
    cp Sources/Vaaka/Resources/whitelist.json build/Vaaka.app/Contents/Resources/whitelist.json
fi

# Copy Info.plist from wherever it actually is
if [ -f Info.plist ]; then
    cp Info.plist build/Vaaka.app/Contents/Info.plist
elif [ -f Resources/Info.plist ]; then
    cp Resources/Info.plist build/Vaaka.app/Contents/Info.plist
else
    echo "Warning: Info.plist not found"
fi

# Stamp version from the nearest git tag (e.g. "v0.3" → "0.3")
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
if [ -n "$GIT_TAG" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GIT_TAG" build/Vaaka.app/Contents/Info.plist
    echo "Version stamped: $GIT_TAG"
else
    echo "Warning: no git tag found, Info.plist version unchanged"
fi

# Copy SwiftPM resource bundles so Bundle.module works at runtime
for bundle_path in .build/release/Vaaka_*.bundle .build/debug/Vaaka_*.bundle; do
    [ -d "$bundle_path" ] && cp -R "$bundle_path" build/Vaaka.app/Contents/MacOS/ && echo "Copied $bundle_path"
done

# Ad-hoc sign so UNUserNotificationCenter works on macOS 14+
codesign --force --deep --sign - build/Vaaka.app

echo "✅ App packaged at build/Vaaka.app"