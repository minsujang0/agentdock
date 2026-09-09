#!/bin/bash
# 새 릴리스로 갈아 끼우고 다시 띄운다.
#
# 사용법: update.sh <설치된 SessionDock.app 경로> <태그>
#
# 앱이 스스로를 덮어쓸 수는 없으므로, 앱은 이 스크립트를 떼어놓고 실행한 뒤
# 종료한다. 여기서 앱이 완전히 내려가기를 기다렸다가 교체하고 다시 연다.
set -euo pipefail

APP="${1:?설치된 앱 경로가 필요합니다}"
TAG="${2:?태그가 필요합니다}"
# 앱 번들 안으로 복사될 때 build.sh 가 체크아웃 경로를 여기에 새긴다. 체크아웃
# 에서 직접 실행하면 그대로 자기 자리를 쓴다.
REPO="__REPO__"
DIR="${3:-$REPO}"
if [ "$DIR" = "__REPO__" ] || [ ! -d "$DIR/.git" ]; then
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ ! -d "$DIR/.git" ]; then
    echo "체크아웃을 찾지 못했습니다: $DIR"; exit 1
fi
LOG="$HOME/Library/Logs/sessiondock-update.log"

exec >>"$LOG" 2>&1
echo "── $(date '+%Y-%m-%d %H:%M:%S') $TAG 로 업데이트"

# 태그는 곧 git 인자가 되므로 모양을 먼저 본다.
if ! [[ "$TAG" =~ ^v?[0-9]+(\.[0-9]+){0,3}(-[0-9A-Za-z.]+)?$ ]]; then
    echo "태그 형식이 올바르지 않습니다: $TAG"; exit 1
fi

# 커밋 안 된 작업을 업데이트가 대신 버려주지는 않는다.
if [ -n "$(git -C "$DIR" status --porcelain)" ]; then
    echo "체크아웃에 커밋 안 된 변경이 있어 멈춥니다."; exit 1
fi

git -C "$DIR" fetch --tags --quiet origin
git -C "$DIR" checkout --quiet "tags/$TAG"

"$DIR/build.sh"

# 앱이 내려가기를 기다린다. 실행 중인 번들을 덮어쓰면 그 프로세스가 깨진다.
for _ in $(seq 1 40); do
    pgrep -f "SessionDock.app/Contents/MacOS/SessionDock" >/dev/null || break
    sleep 0.25
done
pkill -f "SessionDock.app/Contents/MacOS/SessionDock" 2>/dev/null || true
sleep 0.5

rm -rf "$APP"
ditto "$DIR/build/SessionDock.app" "$APP"
open "$APP"
echo "완료: $TAG"
