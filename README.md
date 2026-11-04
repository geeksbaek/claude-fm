# Claude FM

헤드폰을 쓴 Clawd 가 메뉴바에서 음악을 듣는 macOS 메뉴바 앱. YouTube 의 [Claude FM 라이브](https://www.youtube.com/watch?v=tRsQsTMvPNg)를 재생한다.

- 재생 중에는 Clawd 가 눈을 감고 고개를 까딱이고, 옆으로 음표가 떠오른다. 박자가 잡히면 고개 끄덕임 대신 그 박에 맞춰 점프하고 옆스텝을 밟는다.
- Claude FM 을 멈춰 두었더라도, 맥에서 다른 소리가 나면 눈을 뜬 채로 그 박자에 맞춰 춤추고 음표도 떠오른다. 시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 시스템 오디오 녹음을 허용해야 한다. 소리는 저장하지 않고 박자만 본다.
- 분위기도 따라간다. 잔잔하면 살랑이고, 저음이 크면 바닥이 울리고, 고음이 밝으면 반짝이고, 빠르거나 세면 들썩인다.
- 음악 앱이 지금 곡을 알려 주면 Claude FM 재생을 자동으로 멈추고, 그 가사를 찾아 메뉴바 아래에 모든 데스크톱에서 보이는 말풍선으로 따라 부른다. 크롬의 유튜브 뮤직도 포함한다. 한국어는 그대로 두고, 다른 언어는 뜻 대신 한국어 발음으로 적는다. 원문과 번역이 함께 적힌 가사는 곡에서 줄 수가 가장 많은 언어만 남긴다. macOS 15.4 이후에는 시스템이 알려 주는 지금 곡을 `/usr/bin/osascript` 로 읽는다. 곡 제목과 가수 이름만 [LRCLIB](https://lrclib.net) 에 묻는다. 제목 뒤의 판본 표시와 괄호 안 다른 표기도 같이 찾는다. 가사 원문과 받은 가사는 디스크에 남기지 않는다. Claude FM 라이브는 곡 정보를 알리지 않아서 말풍선이 뜨지 않는다.
- 메뉴바 아이콘 클릭: 영상, 재생/일시정지(스페이스), 음량, YouTube 에서 열기, 종료
- 우클릭(또는 control 클릭): 재생/일시정지, YouTube 에서 열기, 종료
- 팝오버를 닫아도 재생은 계속된다. 영상이 내려가면 Claude 채널의 현재 라이브로 넘어간다.

## 빌드

```sh
./scripts/build.sh            # build/Claude FM.app
./scripts/build.sh --install  # /Applications/Claude FM.app 로 설치
open "/Applications/Claude FM.app"
```

macOS 13 이상, Xcode 명령줄 도구가 필요하다. 로그인 시 자동 실행은 시스템 설정 > 일반 > 로그인 항목에서 추가한다.

## 구조

- `Sources/ClaudeFM/ClawdSprite.swift` — Clawd 픽셀 스프라이트와 애니메이션 프레임
- `Sources/ClaudeFM/RadioPlayer.swift` — 보이지 않는 창의 WKWebView 에서 YouTube IFrame API 로 재생
- `Sources/ClaudeFM/PopoverView.swift` — 팝오버 UI
- `Sources/ClaudeFM/BeatClock.swift` — 대역 에너지로 박을 찾는 시계
- `Sources/ClaudeFM/SystemAudioTap.swift` — 시스템 오디오를 사적인 프로세스 탭으로 받아 에너지만 넘긴다
- `Sources/ClaudeFM/RhythmDance.swift` — 메뉴바와 팝오버가 같이 쓰는 춤 상태
- `Sources/ClaudeFM/HangulReading.swift` — 한글이 아닌 가사를 한국어 발음으로 읽기
- `Sources/ClaudeFM/Lyrics.swift` — 가사 시각과 LRCLIB 조회. 메모리에만 둔다
- `Sources/ClaudeFM/NowPlaying.swift` — 지금 재생 중인 곡의 제목과 위치
- `Sources/ClaudeFM/LyricBubble.swift` — 메뉴바 아래 가사 말풍선
- `Sources/ClaudeFM/LyricSinging.swift` — 곡이 바뀌면 가사를 찾아 현재 줄을 띄우기
- `Sources/ClaudeFM/AppDelegate.swift` — 메뉴바 아이템, 팝오버, 우클릭 메뉴
- `scripts/render/` — 스프라이트로 앱 아이콘과 미리보기 시트를 그리는 도구

## 디버그

`CLAUDE_FM_DEBUG=1` 로 실행하면 플레이어 상태를 로그로 남기고, 아래 분산 알림을 받는다.

- `io.github.geeksbaek.claude-fm.toggle` — 재생/일시정지
- `io.github.geeksbaek.claude-fm.popover` — 팝오버 열기/닫기
- `io.github.geeksbaek.claude-fm.lyric` — 예시 발음으로 가사 말풍선. `userInfo` 의 `line` 이 있으면 그 글을 띄운다
