#!/bin/bash
# Run locally while the desktop is idle. Never sends keys when another app is frontmost.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/qa
swiftc Tests/Acceptance/main.swift -o build/qa/acceptance
exec build/qa/acceptance "${1:-3}" "${2:-normal}"
