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

# Copy Info.plist from wherever it actually is
if [ -f Info.plist ]; then
    cp Info.plist build/Vaaka.app/Contents/Info.plist
elif [ -f Resources/Info.plist ]; then
    cp Resources/Info.plist build/Vaaka.app/Contents/Info.plist
else
    echo "Warning: Info.plist not found"
fi

echo "✅ App packaged at build/Vaaka.app"