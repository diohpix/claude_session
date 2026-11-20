# HANDOFF

## tterm 제어 소켓 연동

작성일: 2026-11-20

### 질문

tterm에 파일 소켓(유닉스 도메인 소켓)이 있다면 AI 세션 앱에서 그쪽으로 명령을 보낼 수 있는가?

### 결론

보낼 수 있다. AI 세션 앱은 샌드박스 없이 도는 일반 앱이라, tterm이 유닉스 도메인 소켓을 열어 두면 같은 사용자 권한으로 바로 연결해서 명령을 쓸 수 있다. Swift 표준 API(`socket`/`connect` 또는 Network 프레임워크)만으로 되고 외부 의존성은 필요 없다.

아직 구현한 것은 없다. tterm 쪽에 소켓이 실제로 있는지, 어떤 프로토콜인지는 확인하지 않았다.

### 현재 tterm 연동 방식 (우회)

코드는 `Sources/ClaudeSessions/TerminalLauncher.swift` 에 있다. tterm의 번들 ID는 `com.xiphoid.tterm` 이다.

| 동작 | 현재 방식 | 소켓이 생기면 |
| --- | --- | --- |
| 터미널로 이동 (`focusTerminal(of:)`) | 세션 pid에서 tty를 찾아 tterm 전용 제어 시퀀스 `ESC _ T focus ESC \` 를 tty에 쓴다 (`requestTtermFocus`). 그다음 앱을 앞으로 가져온다. 아래 "포커스 시퀀스 처리" 참고. | 지금 방식으로 충분하다. 소켓으로 옮길 필요는 낮다. |
| 이어 열기 (`resume(_:in:)`) | `$TMPDIR/ClaudeSessions/resume-<세션 ID>.command` 스크립트를 만들어 `open -a tterm` 으로 실행한다. | "새 탭을 열고 이 폴더에서 이 명령 실행"을 직접 요청한다. 임시 파일이 필요 없다. |

### 포커스 시퀀스 처리 (tterm, 2026-11-20 구현)

처음에는 tterm이 이 시퀀스를 처리하지 않아서 앱만 앞으로 오고 창·탭은 선택되지 않았다. tterm 쪽에 다음을 추가했다.

- `src/terminal/kitty_apc_filter.rs`: `ESC _ G`(Kitty) 외에 `ESC _ T` 도 가로챈다. 본문이 256바이트를 넘으면 버린다. `take_tterm_commands()` 로 꺼낸다.
- `src/terminal/ghostty_core.rs`: 본문이 `focus` 이면 `PtyEvent::FocusRequest` 를 보낸다.
- `src/app/sidebar_actions.rs`: `focus_terminal_in_layouts()` — 메인 창 → 추가 창 순으로 터미널이 든 탭을 찾아 탭·분할 패널을 선택하고 창을 앞으로 가져온다. 사이드바의 "터미널로 이동"도 이 함수를 쓴다.
- `src/app/events.rs`: `FocusRequest` 를 받으면 위 함수를 부르고, 어느 창에도 없는 분리(detached) 터미널이면 새 창으로 연다.

분할 패널마다 PTY가 따로 있어서 tty 하나가 터미널 하나와 정확히 짝지어지므로, 탭·분할 구조와 관계없이 시퀀스를 받은 패널이 곧 대상이다. 앱 활성화는 macOS의 활성화 제한 때문에 요청한 쪽(AI 세션 앱)이 `activate()` 로 맡는다.

남은 한계: tty에 쓰는 바이트가 세션 출력과 섞여 드물게 화면이 깨질 수 있다. 시퀀스를 받은 터미널이라면 어떤 프로그램이 출력했든 포커스가 옮겨진다 (창 이동만 하므로 위험은 낮다).

### 제어 소켓 (2026-11-20 구현)

- **tterm**: `src/core/control_socket.rs`(서버), `src/app/control.rs`(UI 스레드 처리). 경로 `$TMPDIR/tterm/control.sock`, 디렉터리 0700·소켓 0600, `getpeereid`로 같은 uid만 받는다. 이미 다른 tterm이 소켓을 쓰고 있으면 두 번째 tterm은 소켓을 열지 않는다.
- **프로토콜**: 한 줄에 JSON 하나. `list`, `focus {tty}`, `input {tty, text, submit}`. `input`은 tterm의 붙여넣기 경로(bracketed paste, ESC·Ctrl-C 필터)로 보내고 `submit`이면 `\r`를 이어 보낸다. 터미널은 tty 경로로 가리킨다 (PTY 생성 시 `ptsname`으로 기록).
- **AI 세션 앱**: `TtermControl.swift`(클라이언트), `Views/MessageComposer.swift`(입력창). 열린 Claude 세션이 tterm에서 돌 때만 대화 화면 아래에 입력창을 보인다. 포커스는 구버전 tterm 호환을 위해 계속 tty APC 방식을 쓴다.

확인할 것: 붙여넣기 직후 `\r`를 같은 순간에 보내므로, Claude Code가 붙여넣기와 Enter를 한 번에 받아도 제출되는지 실제로 확인해야 한다. 안 되면 tterm에서 `\r`를 짧게 늦춰 보낸다.

### 소켓이 있어야 가능해지는 것

- 열린 세션에 텍스트 입력 보내기
- 탭 제목 바꾸기
- tterm이 가진 탭 목록을 받아 세션과 짝짓기

### tterm 쪽에서 정해야 할 것

- **소켓 경로**: 예를 들어 `~/Library/Application Support/tterm/control.sock` 처럼 고정 경로이거나, 환경 변수로 알려 주는 방식.
- **프로토콜**: 한 줄에 JSON 하나씩 주고받는 형식이 양쪽 구현이 가장 단순하다.
- **대상 지정 방법**: tty 경로로 가리킨다. AI 세션 앱이 아는 것은 셸이 아닌 `claude` 프로세스의 pid라서 셸 pid는 맞지 않는다. tty는 AI 세션 앱(`e_tdev` → `devname`)과 tterm(PTY의 `ptsname`) 모두 알 수 있다.
- **소켓 경로 길이**: 유닉스 소켓 경로는 104바이트 제한이 있다. 사용자 이름이 길면 `~/Library/Application Support/...` 가 넘칠 수 있어 `$TMPDIR` 아래가 안전하다.

### 보안

소켓 파일 권한은 본인만 접근 가능(0600)하게 두고, 담는 디렉터리도 0700으로 둔다. 서버는 `getpeereid` 로 연결한 쪽의 uid를 확인한다. 같은 Mac의 다른 사용자가 터미널에 명령을 넣을 수 있으면 안 된다. "텍스트 입력 보내기"를 넣으면 같은 사용자의 아무 프로세스나 열린 셸에 명령을 넣을 수 있게 되므로 이를 받아들일지 따로 정한다.

### 남은 일

1. 이어 열기(`resume(_:in:)`)를 소켓의 "새 탭 열고 명령 실행" 요청으로 바꾸기. tterm에 그 명령이 아직 없다.
2. Codex 세션은 실행 중 세션 목록이 없어 pid를 모른다. 포커스·입력 보내기는 Claude 세션에만 해당한다.
