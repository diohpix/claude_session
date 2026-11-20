# HANDOFF

## tterm 제어 소켓 연동 (검토 메모, 미구현)

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
| 터미널로 이동 (`focusTerminal(of:)`) | 세션 pid에서 tty를 찾아 tterm 전용 제어 시퀀스 `ESC _ T focus ESC \` 를 tty에 쓴다 (`requestTtermFocus`). 그다음 앱을 앞으로 가져온다. | "이 tty(또는 pid)의 탭에 포커스" 명령을 직접 보낸다. |
| 이어 열기 (`resume(_:in:)`) | `$TMPDIR/ClaudeSessions/resume-<세션 ID>.command` 스크립트를 만들어 `open -a tterm` 으로 실행한다. | "새 탭을 열고 이 폴더에서 이 명령 실행"을 직접 요청한다. 임시 파일이 필요 없다. |

### 소켓이 있어야 가능해지는 것

- 열린 세션에 텍스트 입력 보내기
- 탭 제목 바꾸기
- tterm이 가진 탭 목록을 받아 세션과 짝짓기

### tterm 쪽에서 정해야 할 것

- **소켓 경로**: 예를 들어 `~/Library/Application Support/tterm/control.sock` 처럼 고정 경로이거나, 환경 변수로 알려 주는 방식.
- **프로토콜**: 한 줄에 JSON 하나씩 주고받는 형식이 양쪽 구현이 가장 단순하다.
- **대상 지정 방법**: 탭을 tty 경로나 셸 pid로 가리킬 수 있어야 한다. AI 세션 앱은 세션의 pid를 알고 있어서 거기서 tty를 찾아낼 수 있다 (`processInfo(of:)` 의 `e_tdev` → `devname`).

### 보안

소켓 파일 권한은 본인만 접근 가능(0600)하게 둔다. 같은 Mac의 다른 사용자가 터미널에 명령을 넣을 수 있으면 안 된다.

### AI 세션 앱 쪽 구현 시 할 일

1. tterm 소켓 경로와 프로토콜이 정해지면 `TerminalLauncher` 에 소켓 클라이언트를 추가한다.
2. `focusTerminal(of:)` 와 `resume(_:in:)` 에서 소켓이 있으면 소켓을, 없으면 지금의 우회 방식을 쓰게 한다 (구버전 tterm 호환).
3. Codex 세션은 실행 중 세션 목록이 없어 pid를 모른다. 포커스·입력 보내기는 Claude 세션에만 해당한다.
