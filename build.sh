#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p build
swiftc Sources/Layout.swift Sources/Shortcuts.swift Sources/DragController.swift Sources/WindowControl.swift Sources/RestoreSlot.swift Tests/main.swift -o build/check-layout
build/check-layout
app=build/Goodwin.app
mkdir -p "$app/Contents/MacOS"
swiftc -O Sources/*.swift -o "$app/Contents/MacOS/Goodwin"
if [[ ! -f build/Goodwin.icns || Assets/Goodwin.png -nt build/Goodwin.icns || scripts/package-icon.sh -nt build/Goodwin.icns ]]; then
    scripts/package-icon.sh
fi
mkdir -p "$app/Contents/Resources"
cp build/Goodwin.icns "$app/Contents/Resources/Goodwin.icns"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "Built: $PWD/$app"
