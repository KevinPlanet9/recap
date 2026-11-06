#!/bin/bash
# Runs the speech engine on real files, on this Mac (not in CI: it needs the language model).
#   scripts/check-real-files.sh          spoken script, silence, broken and fake files, Cancel
#   LONG=1 scripts/check-real-files.sh   also a 4 hour file, with time and memory
# Uses `say` for speech. ffmpeg (FFMPEG=/path/to/ffmpeg, or on PATH) adds the silence, no-sound video,
# two-track and 4 hour cases; without it those are skipped. Nothing here opens a window.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/Recap"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/recap-real.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FF="${FFMPEG:-$(command -v ffmpeg || true)}"
pass=0; fail=0
ok() { echo "  pass: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1" >&2; fail=$((fail + 1)); }

# Runs the app on a file; sets CODE, OUT and ERR.
run() { set +e; "$BIN" --transcribe "$@" --locale en_US >"$WORK/out.txt" 2>"$WORK/err.txt"; CODE=$?; set -e
        OUT="$(cat "$WORK/out.txt")"; ERR="$(cat "$WORK/err.txt")"; }

SCRIPT="Good morning everyone. This is the weekly operations review. We have three items today. First, the new scheduling system goes live on Tuesday. Second, the budget for the quarter is on track. Third, please finish your training by Friday. Thank you."
say -o "$WORK/known.m4a" --file-format=m4af "$SCRIPT"

echo "Spoken script"
run "$WORK/known.m4a"
# Compare words, ignoring case, punctuation, and "three" written as "3".
norm() { tr '[:upper:]' '[:lower:]' | sed -E 's/\[[0-9:]+\]//g; s/[^a-z0-9 ]+/ /g; s/[[:<:]]3[[:>:]]/three/g' | tr -s ' ' '\n' | grep -v '^$'; }
expected="$(echo "$SCRIPT" | norm)"
got="$(echo "$OUT" | norm)"
total=$(echo "$expected" | wc -l | tr -d ' ')
missing=$(comm -23 <(echo "$expected" | sort -u) <(echo "$got" | sort -u) | wc -l | tr -d ' ')
if [ "$CODE" -eq 0 ] && [ "$missing" -le 2 ]; then ok "all but $missing of $total words heard"; else bad "exit $CODE, $missing of $total words missing"; fi
grep -q '^\[0:00\]' <<<"$OUT" && ok "lines carry times" || bad "no times on lines"

echo "Exports"
for f in srt vtt json md; do
    set +e; "$BIN" --transcribe "$WORK/known.m4a" --locale en_US --format "$f" >"$WORK/x.$f" 2>/dev/null; c=$?; set -e
    [ $c -eq 0 ] && [ -s "$WORK/x.$f" ] && ok "$f export" || bad "$f export"
done
/usr/bin/python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$WORK/x.json" && ok "json export parses" || bad "json export doesn't parse"

echo "Damaged and fake files"
SZ=$(stat -f%z "$WORK/known.m4a"); head -c $((SZ / 2)) "$WORK/known.m4a" >"$WORK/cutoff.m4a"
run "$WORK/cutoff.m4a"
if [ "$CODE" -eq 0 ]; then ok "cut-off file: transcribed what was there"
elif grep -q "couldn't read" <<<"$ERR"; then ok "cut-off file: plain message"
else bad "cut-off file (exit $CODE: $ERR)"; fi
echo "this is not audio" >"$WORK/fake.m4a"
run "$WORK/fake.m4a"; [ "$CODE" -eq 1 ] && grep -q "couldn't read" <<<"$ERR" && ok "fake file: plain message" || bad "fake file (exit $CODE: $ERR)"

if [ -n "$FF" ]; then
    echo "Silence, no sound, two tracks"
    "$FF" -nostdin -v error -y -f lavfi -t 60 -i anullsrc=r=16000:cl=mono -c:a aac "$WORK/silence.m4a"
    run "$WORK/silence.m4a"; [ "$CODE" -eq 3 ] && grep -q "No speech found" <<<"$ERR" && ok "60 s of silence: No speech found" || bad "silence (exit $CODE)"
    "$FF" -nostdin -v error -y -f lavfi -t 5 -i color=c=black:s=320x240 -an "$WORK/nosound.mp4"
    run "$WORK/nosound.mp4"; [ "$CODE" -eq 1 ] && grep -q "no sound" <<<"$ERR" && ok "video with no sound: plain message" || bad "no-sound video (exit $CODE)"
    "$FF" -nostdin -v error -y -f lavfi -t 16 -i anullsrc=r=44100:cl=mono -i "$WORK/known.m4a" -map 0:a -map 1:a -c:a aac "$WORK/twotrack.mov"
    run "$WORK/twotrack.mov"; [ "$CODE" -eq 0 ] && grep -q "training by Friday" <<<"$OUT" && ok "silent first track: second track heard" || bad "two-track file lost speech"

    echo "Cancel"
    "$FF" -nostdin -v error -y -i "$WORK/known.m4a" -c:a aac -b:a 48k "$WORK/known-aac.m4a"
    "$FF" -nostdin -v error -y -stream_loop 120 -i "$WORK/known-aac.m4a" -c copy "$WORK/half-hour.m4a"
    set +e; start=$(date +%s); "$BIN" --transcribe "$WORK/half-hour.m4a" --locale en_US --cancel-after 2 >/dev/null 2>"$WORK/err.txt"; c=$?; end=$(date +%s); set -e
    [ $c -eq 4 ] && [ $((end - start)) -le 6 ] && ok "Cancel stopped a long job in $((end - start)) s" || bad "Cancel (exit $c after $((end - start)) s)"

    if [ "${LONG:-}" = "1" ]; then
        echo "4 hour file"
        "$FF" -nostdin -v error -y -stream_loop 940 -i "$WORK/known-aac.m4a" -c copy "$WORK/long.m4a"
        /usr/bin/time -l "$BIN" --transcribe "$WORK/long.m4a" --locale en_US >/dev/null 2>"$WORK/long.err" && ok "4 hour file" || bad "4 hour file"
        grep -E "Transcribed|peak memory" "$WORK/long.err" | sed 's/^/    /'
    fi
else
    echo "ffmpeg not found: skipped silence, no-sound video, two tracks, Cancel and the 4 hour file"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
