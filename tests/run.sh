#!/usr/bin/env bash
# Headless tests: builds a scratch copy of the mod with tests/test.lua appended to control.lua,
# creates a save and runs a few ticks. Exit code 0 = all passed. FACTORIO overrides the game exe path.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-D:/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio.exe}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MOD="$WORK/mods/down-bad"
mkdir -p "$MOD"
cp -r "$REPO/info.json" "$REPO/settings.lua" "$REPO/locale" "$MOD/"
cat "$REPO/control.lua" "$REPO/tests/test.lua" > "$MOD/control.lua"

"$FACTORIO" --mod-directory "$WORK/mods" --create "$WORK/t.zip" --disable-audio > "$WORK/create.log" 2>&1
"$FACTORIO" --mod-directory "$WORK/mods" --benchmark "$WORK/t.zip" --benchmark-ticks 10 --disable-audio > "$WORK/run.log" 2>&1

grep -h "DOWNBAD-TEST" "$WORK/run.log" | sed 's/.*DOWNBAD-TEST //'
if ! grep -q "DOWNBAD-TEST DONE .* fail=0" "$WORK/run.log"; then
    echo "--- tests failed or did not finish; errors:"
    grep -hiE -A4 "error" "$WORK/create.log" "$WORK/run.log" | grep -v "^--$" | head -20
    exit 1
fi
