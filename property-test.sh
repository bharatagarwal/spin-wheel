#!/bin/zsh
set -e
cd "$(dirname "$0")"
PB_VERSION=2.0.1
PB_COMMIT=7d405e77a7b729390ed1d9a66e1f80a707fd03c4
PB_SHA256=a705dab85a3556874a2b25f483bd097811b6f667c491e800121cd17f6935bc99
PB_DIR=.verify/tools/swift-property-based-$PB_VERSION
BUILD=.verify/properties
CLT=/Library/Developer/CommandLineTools
FRAMEWORKS=$CLT/Library/Developer/Frameworks
TESTING_PLUGINS=$CLT/usr/lib/swift/host/plugins/testing
TARGET=arm64-apple-macos26.0
[[ $(swiftc -print-target-info) == *\"runtimeResourcePath\":\ \"$CLT/usr/lib/swift\"* ]] ||
    { print "swiftc is not the Command Line Tools compiler; run: sudo xcode-select -s $CLT"; exit 2 }

if [[ ! -d $PB_DIR/src ]]; then
    mkdir -p $PB_DIR
    curl -sSL -o $PB_DIR/src.tar.gz https://github.com/x-sheep/swift-property-based/archive/$PB_COMMIT.tar.gz
    [[ $(shasum -a 256 $PB_DIR/src.tar.gz | cut -d' ' -f1) == $PB_SHA256 ]] || { print "swift-property-based checksum mismatch"; exit 2 }
    mkdir $PB_DIR/src
    tar -xzf $PB_DIR/src.tar.gz -C $PB_DIR/src --strip-components 1
fi
mkdir -p $BUILD
if [[ ! -f $BUILD/libPropertyBased.a ]]; then
    swiftc -O -swift-version 6 -parse-as-library -target $TARGET -D EnableShrinking \
        -emit-module -emit-library -static -module-name PropertyBased -F $FRAMEWORKS -plugin-path $TESTING_PLUGINS \
        -emit-module-path $BUILD/PropertyBased.swiftmodule -o $BUILD/libPropertyBased.a $PB_DIR/src/Sources/PropertyBased/*.swift
fi
swiftc -O -assert-config Debug -enable-testing -parse-as-library -target $TARGET \
    -emit-module -emit-library -static -module-name HotPotatoCore \
    -emit-module-path $BUILD/HotPotatoCore.swiftmodule -o $BUILD/libHotPotatoCore.a Physics.swift Turns.swift
swiftc -O -swift-version 6 -target $TARGET -I $BUILD -L $BUILD -lPropertyBased -lHotPotatoCore \
    -F $FRAMEWORKS -framework Testing -plugin-path $TESTING_PLUGINS \
    -Xlinker -rpath -Xlinker $FRAMEWORKS -Xlinker -rpath -Xlinker $CLT/Library/Developer/usr/lib \
    Tests/Properties/*.swift -o $BUILD/properties
$BUILD/properties "$@"
