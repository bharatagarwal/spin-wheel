#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=HotPotato.app
MIN_MACOS=26.0
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp Icon/AppIcon.icns $APP/Contents/Resources/
swiftc -O -parse-as-library -target arm64-apple-macos$MIN_MACOS *.swift -o $APP/Contents/MacOS/HotPotato
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HotPotato</string>
<key>CFBundleIdentifier</key><string>local.hotpotato</string>
<key>CFBundleName</key><string>Hot Potato</string>
<key>CFBundleDisplayName</key><string>Hot Potato</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign -s - --force $APP
echo "Built $APP"
