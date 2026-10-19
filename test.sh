#!/bin/zsh
# Fairness check: ./test.sh [spins-per-size]
set -e
cd "$(dirname "$0")"
swiftc -O Physics.swift Tests/main.swift -o /tmp/spinwheel-fairness
/tmp/spinwheel-fairness "$@"
