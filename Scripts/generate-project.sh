#!/bin/bash
# Генерирует .xcodeproj через xcodegen (если установлен).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen не найден. Установи: brew install xcodegen"
  echo "Либо собирай без Xcode: ./Scripts/build.sh"
  exit 1
fi

xcodegen generate
echo "✓ MacIsland.xcodeproj создан"
echo "  Открой в Xcode или: xcodebuild -scheme 'Mac Island' -configuration Release build"
