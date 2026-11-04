#!/bin/bash
# 무대를 크롬캐스트로 보내는 일을 화면 없이 검사한다.
#  1) 핵심(CASTV2 메시지, 영상 굽기, HLS 서버, 세션): 앱 화면 코드 없이 핵심 파일만 엮어, 핵심이 AppKit 에 기대지 않는 것도 확인한다.
#  2) TV 무대: 앱과 같은 감독·그림판·엔코더로 몇 초 구워 TV 가 받을 그림을 본다.
# 폴더를 넘기면 구운 표본(mp4·재생 목록·조각·TV 화면 그림)을 거기에 남긴다.
#   ./scripts/cast-check.sh [미리보기 폴더]
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .build/tools
CORE=(
  Sources/ClaudeFM/CastProtocol.swift
  Sources/ClaudeFM/CastDevice.swift
  Sources/ClaudeFM/CastSession.swift
  Sources/ClaudeFM/StageStream.swift
  Sources/ClaudeFM/StageStreamStore.swift
  Sources/ClaudeFM/StageStreamServer.swift
)
swiftc -O -module-name CastCheck scripts/cast-check/main.swift "${CORE[@]}" -o .build/tools/cast-check
.build/tools/cast-check "$@"

SOURCES=$(ls Sources/ClaudeFM/*.swift | grep -v '/main.swift$')
swiftc -Onone -module-name ClaudeFM scripts/cast-check/stage/main.swift $SOURCES -o .build/tools/cast-stage
.build/tools/cast-stage "$@"
