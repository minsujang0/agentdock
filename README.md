# SessionDock

로컬에서 도는 Claude Code·Codex 세션이 지금 무슨 상태인지 한 자리에 띄우는
macOS 독. 작업 중인 것, 입력을 기다리는 것, 조용해진 것을 구분해서 보여주고,
줄을 누르면 그 대화를 원래 있던 앱에서 연다.

macOS 알림 배너와 같은 재질(`NSGlassEffectView`)을 쓰고, 모든 움직임은 Core
Animation 이 맡아서 유휴 상태 CPU 는 0% 대다.

## 하는 일

- **상태 판정** — 전사 기록을 읽어 작업 중 / 입력 대기 / 유휴를 가른다. 훅이
  놓친 세션은 주기적인 전체 스캔이 줍는다.
- **정확한 라우팅** — 세션을 기록한 앱 복사본으로 딥링크를 보낸다. Codex 도
  Claude 도 복제본이 여러 개면 같은 URL 스킴을 다 같이 등록하기 때문에, 그냥
  열면 대화를 가진 적 없는 복사본이 받아간다.
- **안 본 것 표시** — 아직 확인하지 않은 대기 세션에 파문이 인다.
- **기다림 회계** — 각 상태로 보낸 시간을 날짜별로 적어 둔다.
- **접기** — 우하단 탭 하나로 접힌다. 누르면 열리고 다시 누르면 닫힌다.

## 설치

```bash
git clone https://github.com/minsujang0/agentdock.git
cd agentdock
./build.sh
cp -R build/SessionDock.app ~/Applications/
open ~/Applications/SessionDock.app
```

macOS 13 이상, Xcode 커맨드라인 도구(`swiftc`)가 필요하다. Liquid Glass 재질은
macOS 26 이상에서만 나오고, 그 아래에서는 `NSVisualEffectView` 로 물러난다.

### 훅 연결

훅 없이도 전체 스캔만으로 동작하지만, 훅을 걸면 상태가 즉시 반영된다.

Claude Code 는 `~/.claude/settings.json` 에 이벤트마다 한 줄씩 넣는다.

```json
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command",
      "command": "/usr/bin/python3 /경로/agentdock/hooks/record.py SessionStart"}]}]
  }
}
```

같은 방식으로 `UserPromptSubmit`, `Stop`, `Notification`, `PermissionRequest`,
`SessionEnd` 를 걸면 된다.

Codex 는 `~/.codex/config.toml` 의 `notify` 에 `hooks/codex-notify.sh` 를 건다.
이 스크립트는 원래 걸려 있던 notify 를 그대로 이어서 호출하므로, 쓰던 것이
멈추지 않는다.

## 업데이트

메뉴의 **업데이트 확인…** 이 GitHub 릴리스를 보고, 새 버전이 있으면 받아서
다시 빌드한 뒤 앱을 새로 띄운다. 터미널에서는 이렇게 한다.

```bash
./update.sh ~/Applications/SessionDock.app v0.2.0
```

앱 번들을 릴리스 자산으로 배포하지 않는 이유는 서명과 공증 때문이다. 공증 없이
받은 `.app` 은 Gatekeeper 가 막고, 격리 속성을 지우라고 안내하는 것은 소스에서
빌드하라는 것보다 나쁜 조언이다. 그래서 네트워크에서 가져오는 것은 버전 문자열
하나이고, 코드는 원래 있던 remote 에서 그 태그를 체크아웃해 온다. 태그는 git
인자가 되기 전에 형식을 검사하고, 커밋하지 않은 변경이 체크아웃에 있으면
덮어쓰지 않고 멈춘다.

## 무엇을 읽고 무엇을 남기나

네트워크로 나가는 것은 업데이트 확인 한 곳뿐이다. 대화 내용은 이 기계를 떠나지
않는다.

**읽는 것**

- `~/.claude/projects/**/*.jsonl` — Claude Code 전사 기록
- `~/Library/Application Support/Claude*/claude-code-sessions` 와 Parallelly
  프로필 안의 같은 디렉터리 — 대화 제목과 앱이 매긴 세션 id
- `~/.codex*/state_5.sqlite` 와 rollout 파일 — Codex 스레드 목록과 전사 기록
- 설치된 앱 번들의 `Info.plist` — 어느 복사본이 어느 홈을 쓰는지

**남기는 것** (전부 `700` 디렉터리 안에 `600` 으로)

- `~/.local/state/chat-sessions/*.json` — 세션 한 건당 한 파일. 제목, 작업
  디렉터리, 상태, 그리고 마지막 발화 앞부분 120자가 들어간다.
- `~/.local/state/chat-sessions/titles.sqlite`, `ledger.json`
- `~/Library/Logs/sessiondock.log` — 무엇을 열었는지만 남고 대화 내용은 안 남는다.

백업이나 동기화 대상에 홈 디렉터리를 통째로 넣는다면 위 기록도 같이 나간다는
점은 알고 있어야 한다.

**권한**

접근성 권한은 선택이다. 있으면 대화 제목으로 창을 찾아 앞으로 가져오고, 없으면
딥링크로만 연다. 딥링크가 대부분의 경우 더 정확하므로 없어도 큰 차이는 없다.

## 라이선스

MIT.
