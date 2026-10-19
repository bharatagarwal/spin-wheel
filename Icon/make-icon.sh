#!/bin/zsh
set -e
cd "$(dirname "$0")"
TMP=$(mktemp -d)
swiftc -O make-icon.swift -o $TMP/make-icon
$TMP/make-icon $TMP/AppIcon.iconset
iconutil -c icns $TMP/AppIcon.iconset -o AppIcon.icns
cp $TMP/AppIcon.iconset/icon_512x512@2x.png preview.png
rm -r $TMP
echo "wrote Icon/AppIcon.icns"
