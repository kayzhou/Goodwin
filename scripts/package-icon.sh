#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
out=build/Goodwin.iconset
mkdir -p "$out"
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((points * scale)); suffix=''; [[ $scale -eq 1 ]] || suffix='@2x'
        sips -z "$px" "$px" Assets/Goodwin.png --out "$out/icon_${points}x${points}${suffix}.png" >/dev/null
    done
done
iconutil -c icns "$out" -o build/Goodwin.icns
