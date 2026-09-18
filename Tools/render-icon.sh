#!/bin/bash
# Regenerates the app icon. The artwork is code, so it can be changed by
# editing one number rather than by opening a drawing program.
set -e
cd "$(dirname "$0")"
OUT="../kivo/Assets.xcassets/AppIcon.appiconset"
swiftc -O -o /tmp/kivo-render-icon RenderIcon.swift
for size in 16 32 64 128 256 512 1024; do
    /tmp/kivo-render-icon "$size" "$OUT/icon_$size.png"
done
echo "rendered 7 sizes into $OUT"
