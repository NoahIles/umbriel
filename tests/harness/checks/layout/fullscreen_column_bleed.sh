#!/usr/bin/env bash
# harness: outputs=1
# A fullscreen column in the scrolling strip is presented at full output width. When focus moves to a neighbor, the
# fullscreen window must not cover the neighbor's column, even past a side dock's exclusive zone.
set -euo pipefail

readonly CLIENT="${UMBRIEL_UNMAP_CLIENT:-./build-debug/tests/unmap-client}"
readonly LAYER_CLIENT="${UMBRIEL_LAYER_CLIENT:-./build-debug/tests/layer-client}"
readonly DOCK_LOG="$UMBRIEL_RUNTIME_DIR/fullscreen-column-bleed-dock.log"

cat >> "$UMBRIEL_CONFIG" <<'CFG'

[animation]
enabled = false

[appearance]
border_width = 2

[layout]
mode = "scrolling"
gap = 10
CFG
"$UMBRIEL" msg config-reload > /dev/null

"$LAYER_CLIENT" HEADLESS-1 68 dock-right > "$DOCK_LOG" 2>&1 &
for _ in $(seq 60); do
  grep -q '^ready$' "$DOCK_LOG" && break
  sleep 0.05
done
if ! grep -q '^ready$' "$DOCK_LOG"; then
  echo "dock did not map: $(< "$DOCK_LOG")"
  exit 1
fi

field() {
  "$UMBRIEL" windows --json | jq -r --arg title "$1" --arg field "$2" '.[] | select(.title == $title) | .[$field]'
}

spawn() {
  FOLLOW_CONFIGURES=1 "$CLIENT" "$1" > "$UMBRIEL_RUNTIME_DIR/$1.log" 2>&1 &
  for _ in $(seq 60); do
    [[ -n $(field "$1" id) ]] && break
    sleep 0.05
  done
  "$UMBRIEL" settle
}

spawn bleed-left
spawn bleed-mid
spawn bleed-right
"$UMBRIEL" msg window-focus-warp "$(field bleed-mid id)" > /dev/null
"$UMBRIEL" msg window-toggle-fullscreen > /dev/null
"$UMBRIEL" settle

for neighbor in bleed-right bleed-left; do
  "$UMBRIEL" msg window-focus-warp "$(field "$neighbor" id)" > /dev/null
  "$UMBRIEL" settle
  if [[ $(field bleed-mid fullscreen) != true ]]; then
    echo "bleed-mid left fullscreen when $neighbor took focus: $("$UMBRIEL" windows --json)"
    exit 1
  fi
  fs_x=$(field bleed-mid x) fs_w=$(field bleed-mid w)
  left_end=$(($(field bleed-left x) + $(field bleed-left w)))
  right_x=$(field bleed-right x)
  if ((fs_x < left_end || fs_x + fs_w > right_x)); then
    echo "with $neighbor focused, fullscreen [$fs_x, $((fs_x + fs_w))) overlaps neighbors ending $left_end / starting $right_x"
    exit 1
  fi
done

echo "a fullscreen column reserves its full output width in the strip"
