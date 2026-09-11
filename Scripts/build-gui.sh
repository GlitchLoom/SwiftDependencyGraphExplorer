#!/bin/sh
# Builds SwiftDependencyGraphExplorer in Release and wraps the raw SPM executable into a
# proper double-clickable .app bundle, ready to zip for a GitHub Release asset.
#
# `swift build -c release` (and even `xcodebuild` against a bare Package.swift) only produces
# a plain Mach-O binary plus a sibling resource bundle -- there is no macOS app bundling step,
# since that's normally Xcode project territory, not SwiftPM's. This script does that wrapping
# by hand: Info.plist, Contents/MacOS, Contents/Resources, ad-hoc code signing.
#
# This produces an UNSIGNED (ad-hoc signed) app: there's no Apple Developer account involved,
# so Gatekeeper will still flag it for anyone who downloads it. They'll need to right-click ->
# Open the first time (or `xattr -d com.apple.quarantine SwiftDependencyGraphExplorer.app`).
set -eu

cd "$(dirname "$0")/.."

APP_NAME="SwiftDependencyGraphExplorer"
BUNDLE_ID="com.glitchloom.swiftdependencygraphexplorer"
VERSION="${1:-0.1.0}"
DERIVED_DATA=".build/xcode-release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "==> Building $APP_NAME (Release, unsigned) for version $VERSION"
xcodebuild \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Release"
BUILT_EXECUTABLE="$PRODUCTS_DIR/$APP_NAME"
RESOURCE_BUNDLE="$PRODUCTS_DIR/${APP_NAME}_MermaidRenderer.bundle"

if [ ! -x "$BUILT_EXECUTABLE" ]; then
    echo "error: build did not produce $BUILT_EXECUTABLE" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILT_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Swift Dependency Graph Explorer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing (no Apple Developer account needed, but Gatekeeper will still warn on other Macs)"
codesign --force --deep --sign - "$APP_BUNDLE"

ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS.zip"
echo "==> Zipping to $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Done"
echo "    App:  $APP_BUNDLE"
echo "    Zip:  $ZIP_PATH"
