#!/bin/bash
# Собирает Mac Island.app через swiftc (без полного Xcode).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Island"
EXEC_NAME="MacIsland"
BUILD_DIR="$ROOT/.build/app"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
SRC_DIR="$ROOT/MacIsland/Sources"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" ]]; then
  TARGET="x86_64-apple-macos14.0"
else
  TARGET="arm64-apple-macos14.0"
fi

echo "→ SDK: $SDK"
echo "→ Target: $TARGET"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# Собираем список исходников (совместимо с bash 3.2)
SOURCES=()
while IFS= read -r f; do
  SOURCES+=("$f")
done <<EOF
$(find "$SRC_DIR" -name '*.swift' | sort)
EOF

if [[ ${#SOURCES[@]} -eq 0 ]]; then
  echo "Нет .swift файлов в $SRC_DIR"
  exit 1
fi

echo "→ Файлов Swift: ${#SOURCES[@]}"

swiftc \
  "${SOURCES[@]}" \
  -sdk "$SDK" \
  -target "$TARGET" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Cocoa \
  -framework QuartzCore \
  -framework Foundation \
  -O \
  -o "$MACOS_DIR/$EXEC_NAME"

cp "$ROOT/MacIsland/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if command -v codesign >/dev/null; then
  codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
fi

echo "✓ Готово: $APP_DIR"
echo "  Запуск: open \"$APP_DIR\""
