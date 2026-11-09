#!/bin/sh
# Compiles and runs the logic checks.
set -e
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -swift-version 5 KeybindsUnlocked/Trigger.swift Tests/main.swift -o "$out/checks"
"$out/checks"
