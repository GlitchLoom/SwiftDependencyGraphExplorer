#!/bin/sh
# Builds the `sdge` CLI in Release and packages the resulting single binary as a tarball,
# ready for a GitHub Release asset.
#
# Unlike the GUI (see build-gui.sh), a CLI tool is just one Mach-O binary -- no app bundle, no
# Info.plist, no bundled resources -- so plain `swift build -c release` is already the full
# build step; this script only adds ad-hoc signing and packaging on top.
#
# This produces an UNSIGNED (ad-hoc signed) binary: there's no Apple Developer account involved,
# so Gatekeeper will still flag it for anyone who downloads it. They'll need to run
# `xattr -d com.apple.quarantine sdge` once (or right-click -> Open won't apply here since it's
# a bare binary, not an app).
set -eu

cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
DIST_DIR="dist"
ARCHIVE_NAME="sdge-$VERSION-macOS.tar.gz"

echo "==> Building sdge (Release, unsigned) for version $VERSION"
swift build -c release --product sdge

BUILT_BINARY=".build/release/sdge"
if [ ! -x "$BUILT_BINARY" ]; then
    echo "error: build did not produce $BUILT_BINARY" >&2
    exit 1
fi

echo "==> Ad-hoc signing (no Apple Developer account needed, but Gatekeeper will still warn on other Macs)"
mkdir -p "$DIST_DIR"
cp "$BUILT_BINARY" "$DIST_DIR/sdge"
codesign --force --sign - "$DIST_DIR/sdge"

ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
echo "==> Archiving to $ARCHIVE_PATH"
rm -f "$ARCHIVE_PATH"
tar -C "$DIST_DIR" -czf "$ARCHIVE_PATH" sdge

echo "==> Done"
echo "    Binary:  $DIST_DIR/sdge"
echo "    Archive: $ARCHIVE_PATH"
