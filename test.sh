#!/bin/zsh
set -e
cd "$(dirname "$0")"
swiftc -O Physics.swift Tests/main.swift -o /tmp/hotpotato-fairness
/tmp/hotpotato-fairness "$@"
