#!/bin/bash
# Package an already-built local app. Keep DMGs outside the source tree in build/.
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/Goodwin.app
codesign --verify --strict "$app"
version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
archs=$(lipo -archs "$app/Contents/MacOS/Goodwin" | tr ' ' '-')
out="$PWD/build/Goodwin-$version-$archs.dmg"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/payload"
ditto "$app" "$tmp/payload/Goodwin.app"
ln -s /Applications "$tmp/payload/Applications"
hdiutil create -quiet -fs HFS+ -format UDZO -volname Goodwin -srcfolder "$tmp/payload" "$tmp/Goodwin.dmg"
hdiutil verify "$tmp/Goodwin.dmg" >/dev/null
mv "$tmp/Goodwin.dmg" "$out"
(cd build && shasum -a 256 "${out##*/}" > "${out##*/}.sha256")
printf 'Packaged: %s\n' "$out"
