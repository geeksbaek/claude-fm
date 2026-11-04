#!/bin/sh
# 한국어 발음 읽기를 예문으로 검사한다. 낱말이나 줄을 넘기면 읽은 결과만 보여 준다.
#   ./scripts/reading.sh                 # 모든 예문 검사
#   ./scripts/reading.sh "I love you"    # 읽은 결과만 보기
set -e
cd "$(dirname "$0")/.."
mkdir -p .build/tools
swiftc -O scripts/reading/*.swift Sources/ClaudeFM/HangulReading*.swift -o .build/tools/reading
.build/tools/reading "$@"
