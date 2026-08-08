#!/bin/bash
# Собирает zip для передачи другому человеку.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' MacIsland/Info.plist 2>/dev/null || echo 1.0.0)"
./Scripts/build.sh
rm -rf dist/staging
rm -f "dist/MacIsland-${VERSION}.zip"
mkdir -p dist/staging
cp -R ".build/app/Mac Island.app" "dist/staging/Mac Island.app"
xattr -cr "dist/staging/Mac Island.app"
codesign --force --deep --sign - "dist/staging/Mac Island.app"
cp "$ROOT/Scripts/package-INSTALL.txt" dist/staging/INSTALL.txt
( cd dist/staging && zip -r -y "../MacIsland-${VERSION}.zip" "Mac Island.app" INSTALL.txt )
rm -rf dist/staging
echo "✓ dist/MacIsland-${VERSION}.zip"
ls -lh "dist/MacIsland-${VERSION}.zip"
