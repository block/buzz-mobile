#!/bin/bash
# Compile the UIKit control's production geometry without Flutter or a simulator.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -r "$fixture"' EXIT
xcrun swiftc \
  "$repo_root/ios/Runner/ThemePaginationGeometry.swift" \
  "$repo_root/ios/NativeControlTests/ThemePaginationGeometryTests.swift" \
  -o "$fixture/pagination-tests"
"$fixture/pagination-tests"
