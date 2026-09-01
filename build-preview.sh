#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$DIR/build/preview.png}"
mkdir -p "$DIR/build"
swiftc -O -o "$DIR/build/preview-tool" \
    "$DIR/src/Log.swift" "$DIR/src/Session.swift" "$DIR/src/Settings.swift" "$DIR/src/Route.swift" \
    "$DIR/src/Dock.swift" "$DIR/preview/main.swift"
"$DIR/build/preview-tool" "$OUT"
