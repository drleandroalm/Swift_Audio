#!/usr/bin/env bash
set -euo pipefail
SWIFT=swift
# Run the CLI script with xcrun swift to ensure Xcode toolchain
xcrun "$SWIFT" Scripts/RecorderSmokeCLI/main.swift "$@"
