#!/bin/zsh
set -e
cd "$(dirname "$0")"
swiftc -O -assert-config Debug Physics.swift Turns.swift Tests/Unit/main.swift -o /tmp/hotpotato-unit
/tmp/hotpotato-unit
