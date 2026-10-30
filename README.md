# Claude FM

헤드폰을 쓴 Clawd 가 메뉴바에서 음악을 듣는 macOS 메뉴바 앱. YouTube 의 [Claude FM 라이브](https://www.youtube.com/watch?v=tRsQsTMvPNg)를 재생한다.

- 재생 중에는 Clawd 가 눈을 감고 고개를 까딱이고, 옆으로 음표가 떠오른다. 멈추면 눈을 뜨고 가만히 있다.
- 메뉴바 아이콘 클릭: 영상, 재생/일시정지(스페이스), 음량, YouTube 에서 열기, 종료
- 우클릭(또는 control 클릭): 재생/일시정지, YouTube 에서 열기, 종료
- 팝오버를 닫아도 재생은 계속된다. 영상이 내려가면 Claude 채널의 현재 라이브로 넘어간다.

## 빌드

```sh
./scripts/build.sh            # build/Claude FM.app
./scripts/build.sh --install  # ~/Applications/Claude FM.app 로 설치
open ~/Applications/"Claude FM.app"
```

macOS 13 이상, Xcode 명령줄 도구가 필요하다. 로그인 시 자동 실행은 시스템 설정 > 일반 > 로그인 항목에서 추가한다.

## 구조

- `Sources/ClaudeFM/ClawdSprite.swift` — Clawd 픽셀 스프라이트와 애니메이션 프레임
- `Sources/ClaudeFM/RadioPlayer.swift` — 보이지 않는 창의 WKWebView 에서 YouTube IFrame API 로 재생
- `Sources/ClaudeFM/PopoverView.swift` — 팝오버 UI
- `Sources/ClaudeFM/AppDelegate.swift` — 메뉴바 아이템, 팝오버, 우클릭 메뉴
- `scripts/render/` — 스프라이트로 앱 아이콘과 미리보기 시트를 그리는 도구

## 디버그

`CLAUDE_FM_DEBUG=1` 로 실행하면 플레이어 상태를 로그로 남기고, 아래 분산 알림을 받는다.

- `io.github.geeksbaek.claude-fm.toggle` — 재생/일시정지
- `io.github.geeksbaek.claude-fm.popover` — 팝오버 열기/닫기
