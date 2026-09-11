#!/bin/bash
# 한 줄 설치:
#   curl -fsSL https://raw.githubusercontent.com/minsujang0/sessiondock/main/install.sh | bash
#
# 소스를 받아 이 기계에서 빌드한다. 미리 빌드한 번들을 내려받지 않는 이유는
# 공증 때문만이 아니다. git 과 curl 은 격리 속성을 붙이지 않으므로 받은 앱이
# Gatekeeper 검사를 건너뛰게 되는데, 서명 없는 번들을 그렇게 들여보내는 것은
# 검사를 우회하는 짓이다. 여기서 실행되는 코드는 전부 이 저장소에서 왔고,
# 컴파일도 여기서 한다.
set -euo pipefail

REPO="${SESSIONDOCK_REPO:-https://github.com/minsujang0/sessiondock.git}"
SRC="${SESSIONDOCK_SRC:-$HOME/.local/share/sessiondock/src}"
DEST="${SESSIONDOCK_DEST:-$HOME/Applications}"
APP="$DEST/SessionDock.app"

say() { printf '  %s\n' "$*"; }

# 필요한 것부터 본다. 없는 채로 절반쯤 진행해 두는 것이 제일 나쁘다.
[ "$(uname -s)" = "Darwin" ] || { say "macOS 전용입니다."; exit 1; }
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 13 ]; then
    say "macOS 13 이상이 필요합니다. 지금은 $(sw_vers -productVersion) 입니다."; exit 1
fi
command -v git >/dev/null || { say "git 이 필요합니다."; exit 1; }
if ! command -v swiftc >/dev/null; then
    say "swiftc 가 없습니다. 커맨드라인 도구를 먼저 설치하세요:"
    say "  xcode-select --install"
    exit 1
fi

if [ -d "$SRC/.git" ]; then
    say "소스 갱신: $SRC"
    git -C "$SRC" fetch --quiet --tags origin
    git -C "$SRC" checkout --quiet main
    git -C "$SRC" pull --quiet --ff-only origin main
else
    say "소스 받는 중: $SRC"
    mkdir -p "$(dirname "$SRC")"
    git clone --quiet "$REPO" "$SRC"
fi

say "빌드 중"
"$SRC/build.sh" >/dev/null

pkill -f "SessionDock.app/Contents/MacOS/SessionDock" 2>/dev/null || true
sleep 0.5
mkdir -p "$DEST"
rm -rf "$APP"
ditto "$SRC/build/SessionDock.app" "$APP"
open "$APP"

VERSION="$(tr -d ' \n' < "$SRC/VERSION")"
echo
say "설치 완료: $APP ($VERSION)"
say "훅을 걸면 상태가 즉시 반영됩니다. README 의 '훅 연결' 을 보세요:"
say "  $SRC/README.md"
