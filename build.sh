#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=YourTurn.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp Icon/AppIcon.icns $APP/Contents/Resources/
swiftc -O -parse-as-library main.swift Physics.swift -o $APP/Contents/MacOS/YourTurn
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>YourTurn</string>
<key>CFBundleIdentifier</key><string>local.yourturn</string>
<key>CFBundleName</key><string>Your Turn</string>
<key>CFBundleDisplayName</key><string>Your Turn</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign -s - --force $APP
echo "Built $APP"
