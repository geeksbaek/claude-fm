#!/bin/bash
# 말풍선·메뉴바 Clawd·무대를 상태별로 PNG 로 그린다. 인자로 받은 폴더(기본 build/previews)에 쓴다.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/previews}"
mkdir -p .build/tools "$OUT"
SOURCES=$(ls Sources/ClaudeFM/*.swift | grep -v '/main.swift$')
swiftc -O -module-name ClaudeFM scripts/preview/main.swift $SOURCES -o .build/tools/preview
.build/tools/preview "$OUT"
