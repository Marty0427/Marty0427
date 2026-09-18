#!/usr/bin/env bash
#
# Build and unit test PocketPass on a simulator.
#
# Usage:
#   Scripts/test.sh                 # iPhone 16 simulator, latest OS
#   Scripts/test.sh "iPhone 15 Pro" # a different device
set -euo pipefail

DEVICE="${1:-iPhone 16}"
cd "$(dirname "$0")/.."

exec xcodebuild test \
  -project PocketPass.xcodeproj \
  -scheme PocketPass \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  CODE_SIGNING_ALLOWED=NO
