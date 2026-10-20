#!/bin/zsh
cd "$(dirname "$0")"
SC_VERSION=1.6.0
SC_SHA256=a54d2731acacbe912bb42f61b81836fe3c18dbbed12469fb812436a0d3f10ffb
SC_DIR=.verify/tools/swift-complexity-$SC_VERSION
SC=$SC_DIR/SwiftComplexityCLI-$SC_VERSION-macos-arm64/SwiftComplexityCLI
COMPLEXITY_LIMIT=15
SOURCES=(main.swift Session.swift Turns.swift Sound.swift Physics.swift)

if [[ ! -x $SC ]]; then
    mkdir -p $SC_DIR
    curl -sSL -o $SC_DIR/cli.tar.gz https://github.com/fummicc1/swift-complexity/releases/download/v$SC_VERSION/SwiftComplexityCLI-$SC_VERSION-macos-arm64.tar.gz
    [[ $(shasum -a 256 $SC_DIR/cli.tar.gz | cut -d' ' -f1) == $SC_SHA256 ]] || { print "swift-complexity checksum mismatch"; exit 2 }
    tar -xzf $SC_DIR/cli.tar.gz -C $SC_DIR
fi
[[ -d /Applications/Xcode.app ]] || export TOOLCHAIN_DIR=/Library/Developer/CommandLineTools

failed=()
leftovers() { ls ~/Library/Preferences | grep -i hotpotato | grep -v -x -e local.hotpotato.plist -e local.hotpotato.verify.plist }
leftovers_before=$(leftovers)
parses() {
    local script
    for script in "$@"; do zsh -n $script || return 1; done
}
step() {
    local name=$1; shift
    print "== $name"
    "$@" || failed+=($name)
}

step build ./build.sh
step lint swiftlint lint --strict --quiet
step python ruff check --quiet .
step shell parses *.sh Icon/*.sh Verification/*.sh .claude/skills/verify-hotpotato/bin/sw
step complexity $SC $SOURCES --threshold $COMPLEXITY_LIMIT
step unit ./unit-test.sh
step properties ./property-test.sh
[[ $1 == quick ]] || step fairness ./test.sh 1000
step model Verification/check.sh
step traces Verification/check.sh traces
step geometry Verification/prove-geometry.sh
step mutants python3 -I Verification/mutants.py
leaves_nothing() { [[ $(leftovers) == $leftovers_before ]] || { print "left behind in ~/Library/Preferences:"; leftovers; return 1 } }
step footprint leaves_nothing

print
if (( $#failed )); then print "FAILED: $failed"; exit 1; fi
print "all checks passed"
