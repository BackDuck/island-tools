#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
killall MacIsland 2>/dev/null || true
./Scripts/build.sh
open ".build/app/Mac Island.app"
echo "→ Mac Island перезапущен"
