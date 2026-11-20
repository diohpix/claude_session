# AI 세션

이 Mac에 쌓인 Claude Code와 Codex CLI 세션을 한 창에서 찾아보고, 대화 내용을 읽고, 터미널에서 다시 여는 macOS 앱입니다.

Claude는 `~/.claude/projects` 의 세션 기록(jsonl)과 `~/.claude/sessions` 의 실행 중 세션 정보를, Codex는 `~/.codex/sessions` 의 세션 기록과 `~/.codex/session_index.jsonl` 의 제목을 읽어서 보여 줍니다. 기록 파일은 읽기만 하며, 바꾸는 동작은 휴지통으로 옮기는 삭제뿐입니다.

## 기능

- **세션 목록**: 전체 세션, 지금 열려 있는 세션, 도구별(Claude / Codex) 세션, 프로젝트별 세션을 사이드바에서 골라 봅니다. 열린 세션이 맨 위에 오고 나머지는 최근 순입니다. 같은 폴더에서 쓴 Claude와 Codex 세션은 한 프로젝트로 묶이고, 각 세션에는 도구 아이콘이 붙습니다. 이 아이콘과 사이드바의 아이콘은 이 Mac에 설치된 Claude 앱과 Codex 앱의 아이콘을 가져다 쓰며, 앱이 없으면 기본 기호로 표시합니다.
- **실행 상태 표시**: 열려 있는 Claude 세션에는 작업 중, 대기, 셸 실행 중 배지가 붙습니다.
- **대화 보기**: 세션을 고르면 내가 쓴 요청과 Claude 또는 Codex의 응답이 말풍선으로 나옵니다. 도구 호출은 이름과 횟수로 요약합니다. 응답의 마크다운(제목, 목록, 코드 블록, 표, 인용, 굵게·링크 등)을 서식대로 보여 주고, 마우스로 끌어서 여러 줄을 선택해 복사할 수 있습니다.
- **검색**: 제목, 첫 요청, 작업 폴더 경로, 세션 ID, git 브랜치, 세션 이름으로 찾습니다.
- **터미널에서 이어 열기**: 세션의 작업 폴더에서 `claude --resume <세션 ID>` (Codex 세션은 `codex resume <세션 ID>`) 를 새 터미널 창으로 실행합니다.
- **터미널로 이동**: 이미 열려 있는 세션은 그 세션을 띄운 터미널 앱을 앞으로 가져옵니다.
- **메시지 보내기 (tterm)**: tterm에서 열려 있는 Claude 세션은 대화 화면 아래에 입력창이 생깁니다. Return을 누르면 tterm의 그 세션에 입력하고 Enter까지 보냅니다(줄바꿈은 Option+Return). tterm의 제어 소켓(`$TMPDIR/tterm/control.sock`)을 쓰므로 이 기능이 들어간 tterm이 필요합니다.
- **그 밖의 동작**: 이어 열기 명령 복사, Finder에서 작업 폴더 열기, 세션 기록을 휴지통으로 이동.
- **작업 완료 알림**: 열려 있는 Claude 세션이 작업 중에서 대기로 바뀌면 macOS 알림을 보냅니다. 알림을 누르면 그 세션의 터미널로 이동합니다. 설정에서 끌 수 있습니다. macOS 알림 권한이 없으면(ad-hoc 서명 앱은 권한이 거부될 수 있습니다) 화면 오른쪽 위에 앱이 직접 알림 창을 띄웁니다. `--notify-check` 를 붙여 실행하면 어느 쪽으로 가는지 출력하고 시험 알림을 띄웁니다.
- **자동 새로 고침**: 폴더 변경을 감시하다가 바뀌면 바로 반영하고, 5초마다 한 번 더 확인합니다.

동작들은 목록의 오른쪽 클릭 메뉴와 대화 화면 위쪽 버튼에 모두 있습니다.

## 요구 사항

- macOS 14 이상
- Swift 5.9 이상 (Xcode 15 또는 Command Line Tools)
- 이어 열기를 쓰려면 `claude` 명령(Codex 세션은 `codex` 명령)이 로그인 셸의 `PATH` 에 있어야 합니다.

## 빌드와 실행

앱 번들을 만들려면:

```sh
./build-app.sh
open ClaudeSessions.app
```

릴리스 빌드를 한 뒤 `ClaudeSessions.app` 을 만들고 ad-hoc 서명을 합니다.

번들 없이 바로 실행하려면:

```sh
swift run
```

화면을 띄우지 않고 스캔 결과만 확인하려면 `--dump` 를 붙입니다. 프로젝트·세션·열린 세션 개수와 최근 세션 15개를 출력합니다.

```sh
swift run ClaudeSessions --dump
```

## 설정

메뉴의 설정(`⌘,`)에서 이어 열 때 쓸 터미널을 고릅니다.

| 터미널 | 비고 |
| --- | --- |
| tterm | 기본값 |
| 터미널 (Terminal.app) | |
| Alacritty | |

tterm에서 띄운 세션은 "터미널로 이동"을 누르면 해당 창과 탭까지 선택됩니다. 다른 터미널은 앱만 앞으로 옵니다.

## 알아 둘 점

- 실행 중인 세션은 삭제할 수 없습니다. 먼저 세션을 종료해야 합니다.
- Codex는 실행 중인 세션을 알려 주는 파일이 없어서 열린 세션 표시, 터미널로 이동, 실행 중 삭제 방지가 Codex 세션에는 적용되지 않습니다.
- 삭제하면 기록 파일과 같은 이름의 부속 폴더가 함께 휴지통으로 가며, 휴지통에서 되돌릴 수 있습니다.
- 작업 폴더가 지워진 세션은 이어 열 수 없습니다.
- 아주 긴 메시지는 20,000자까지만 표시합니다.
- 이어 열 때 `$TMPDIR/ClaudeSessions/` 에 `resume-<세션 ID>.command` 스크립트를 만들어 실행합니다 (tterm, Terminal.app).

## 소스 구성

```
Sources/ClaudeSessions/
├── App.swift               진입점, 설정 창, --dump
├── Models.swift            세션·메시지 모델
├── SessionStore.swift      디스크 스캔, 캐시, 삭제
├── TranscriptParser.swift  Claude jsonl 기록 파싱
├── CodexTranscriptParser.swift  Codex jsonl 기록 파싱
├── DirectoryWatcher.swift  FSEvents 폴더 감시
├── Notifier.swift          작업 완료 알림
├── TerminalLauncher.swift  이어 열기, 터미널로 이동
└── Views/                  사이드바, 세션 목록, 대화 화면
```

외부 의존성은 없습니다.
