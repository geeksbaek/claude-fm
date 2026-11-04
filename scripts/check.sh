#!/bin/bash
# 화면 없이 확인할 수 있는 로직(가사 분석, 박 시계, 폭죽, 전광판)을 검사한다.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .build/tools
SOURCES=$(ls Sources/ClaudeFM/*.swift | grep -v '/main.swift$')
swiftc -O -module-name ClaudeFM scripts/check/main.swift $SOURCES -o .build/tools/check
.build/tools/check
