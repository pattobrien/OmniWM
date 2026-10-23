#!/usr/bin/env bash
set -euo pipefail
DEMO=/Users/runner/demo-v2
LOGS="$DEMO/logs"
FF=/Users/runner/.dotnet/tools/ffmpeg
TAKE="$LOGS/take"
rc="$(cat "$LOGS/driver.rc")"
reset_at="$(awk -F '\t' 'NR == 1 { print $2 }' "$LOGS/sections.tsv")"
end="$(tail -n 1 "$LOGS/sections.tsv" | cut -f 2)"

card_pts="$("$FF" -nostdin -t 30 -i "$TAKE/raw.mov" -vf "scale=320:-1,signalstats,metadata=print:key=lavfi.signalstats.YAVG" -f null - 2>&1 \
  | grep -oE 'pts_time:[0-9.]+|YAVG=[0-9.]+' | paste - - | sed 's/pts_time://; s/YAVG=//' \
  | awk '$2 < 45 { print $1; exit }')"
[ -n "$card_pts" ] || { echo "extract: the intro card never darkened the first 30 s of the raw capture" >&2; exit 1; }
launch="$(awk -v r="$reset_at" -v p="$card_pts" 'BEGIN { printf "%.3f", r + 0.05 - p }')"
echo "$launch" > "$LOGS/launch"
clip_at() { awk -v a="$1" -v l="$launch" 'BEGIN { printf "%.2f", a - l }'; }

"$FF" -nostdin -loglevel error -y -i "$TAKE/raw.mov" -t "$(clip_at "$end")" -c copy "$TAKE/dryrun.mov"
probe="$("$FF" -nostdin -i "$TAKE/dryrun.mov" 2>&1 || true)"
duration="$(printf '%s\n' "$probe" | sed -n 's/.*Duration: \([0-9:.]*\).*/\1/p')"
resolution="$(printf '%s\n' "$probe" | sed -n 's/.*Video: .*, \([0-9][0-9]*x[0-9][0-9]*\).*/\1/p' | head -n 1)"

{
  printf 'clip %s duration %s resolution %s driver exit %s\n' "$TAKE/dryrun.mov" "$duration" "$resolution" "$rc"
  printf 'clip seconds; synced on the intro card, which first darkens the clip at %s s\n' "$card_pts"
  awk -F '\t' -v l="$launch" '
    { label[NR] = $1; t[NR] = $2; desc[NR] = $3 }
    END { for (i = 1; i < NR; i++) printf "%-12s %7.2f %7.2f  %s\n", label[i], t[i] - l, t[i + 1] - l, desc[i] }
  ' "$LOGS/sections.tsv"
} > "$TAKE/timestamps.txt"

rm -rf "$TAKE/frames"
mkdir -p "$TAKE/frames"
while IFS="$(printf '\t')" read -r label at; do
  "$FF" -nostdin -loglevel error -y -ss "$(clip_at "$at")" -i "$TAKE/dryrun.mov" -frames:v 1 "$TAKE/frames/$label.png"
done < "$LOGS/shots.tsv"

cp "$LOGS/driver.log" "$LOGS/hook-invocations.log" "$TAKE/"
cat "$TAKE/timestamps.txt"
ls "$TAKE/frames"
