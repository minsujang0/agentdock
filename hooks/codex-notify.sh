#!/bin/bash
# Codex notify hook: record the session, then pass the event on to whatever
# notify was configured before, so nothing that already worked stops working.
RECORD="/Users/minsujang/PycharmProjects/chat-sessions/hooks/record.py"
PREVIOUS_FILE="$HOME/.codex/.sessiondock-previous-notify"

/usr/bin/python3 "$RECORD" turn-ended "$@" >/dev/null 2>&1 || true

# chain: the saved value is a TOML array of strings
if [ -f "$PREVIOUS_FILE" ]; then
    mapfile -t PARTS < <(python3 -c "
import json, sys
raw = open('$PREVIOUS_FILE').read().strip()
try:
    for item in json.loads(raw):
        print(item)
except Exception:
    pass
" 2>/dev/null) || true
    if [ "${#PARTS[@]}" -gt 0 ]; then
        "${PARTS[@]}" "$@" >/dev/null 2>&1 || true
    fi
fi
exit 0
