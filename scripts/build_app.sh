#!/usr/bin/env bash
set -euo pipefail

PROJECT="MLXBox.xcodeproj"
SCHEME="MLXBox"
DERIVED_DATA="build"
CONFIGURATION="Release"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

echo "Built app bundle:"
echo "$DERIVED_DATA/Build/Products/$CONFIGURATION/MLXBox.app"
