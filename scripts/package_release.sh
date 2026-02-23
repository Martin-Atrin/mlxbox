#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="MLXBox.app"
BUILD_DIR="$ROOT_DIR/build/release"
DIST_DIR="$ROOT_DIR/dist"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

build_with_xcode() {
  xcodebuild \
    -project MLXBox.xcodeproj \
    -scheme MLXBox \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/derived" \
    build
  cp -R "$BUILD_DIR/derived/Build/Products/Release/$APP_NAME" "$BUILD_DIR/$APP_NAME"
}

build_manual() {
  local sdk
  sdk="$(xcrun --sdk macosx --show-sdk-path)"
  mkdir -p "$BUILD_DIR/module-cache"
  export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
  swiftc -O \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -sdk "$sdk" \
    -target arm64-apple-macos14.0 \
    MLXBox/App/*.swift MLXBox/Core/*.swift MLXBox/UI/*.swift \
    -o "$BUILD_DIR/MLXBox"

  mkdir -p "$BUILD_DIR/$APP_NAME/Contents/MacOS" "$BUILD_DIR/$APP_NAME/Contents/Resources"
  cp "$BUILD_DIR/MLXBox" "$BUILD_DIR/$APP_NAME/Contents/MacOS/MLXBox"
  chmod +x "$BUILD_DIR/$APP_NAME/Contents/MacOS/MLXBox"
  cat > "$BUILD_DIR/$APP_NAME/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>MLXBox</string>
  <key>CFBundleIdentifier</key><string>com.mlxbox.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>MLXBox</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.0</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSLocalNetworkUsageDescription</key><string>MLXBox scans local endpoints and sends chat requests to local model servers.</string>
</dict>
</plist>
PLIST
}

if xcodebuild -version >/dev/null 2>&1; then
  echo "Building with xcodebuild..."
  build_with_xcode
else
  echo "xcodebuild unavailable; using manual Swift build fallback..."
  build_manual
fi

echo "Signing app with identity: $SIGN_IDENTITY"
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$BUILD_DIR/$APP_NAME"
codesign --verify --deep --strict "$BUILD_DIR/$APP_NAME"

ZIP_PATH="$DIST_DIR/MLXBox-macOS.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$BUILD_DIR/$APP_NAME" "$ZIP_PATH"

echo "Release artifact:"
echo "$ZIP_PATH"
echo
echo "If using Developer ID signing, notarize before publishing:"
echo "xcrun notarytool submit \"$ZIP_PATH\" --wait --apple-id <id> --team-id <team> --password <app-specific-password>"
