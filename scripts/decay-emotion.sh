#!/bin/bash
# decay-emotion.sh — Return emotional state toward baseline over time
# Usage: ./decay-emotion.sh [--dry-run]
# Run via cron (e.g., every 6 hours) to gradually normalize emotions

set -e

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
STATE_FILE="$WORKSPACE/memory/emotional-state.json"

if [ ! -f "$STATE_FILE" ]; then
  echo "❌ No emotional state found"
  exit 1
fi

DRY_RUN=false
[ "$1" = "--dry-run" ] && DRY_RUN=true

# Decay rate: how much to move toward baseline each run
# 0.1 means 10% of the distance to baseline
DECAY_RATE=0.1

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "🎭 Emotional Decay"
echo "─────────────────────"
echo ""

# Get current and baseline values
for DIM in valence arousal connection curiosity energy; do
  CURRENT=$(jq -r ".dimensions.$DIM" "$STATE_FILE")
  BASELINE=$(jq -r ".baseline.$DIM" "$STATE_FILE")
  
  # Calculate decay: move DECAY_RATE toward baseline
  # new = current + (baseline - current) * rate
  DIFF=$(echo "$BASELINE - $CURRENT" | bc -l)
  CHANGE=$(echo "$DIFF * $DECAY_RATE" | bc -l)
  NEW=$(echo "$CURRENT + $CHANGE" | bc -l)
  
  # Round to 2 decimal places
  NEW=$(printf "%.2f" $NEW)
  
  if [ "$DRY_RUN" = true ]; then
    echo "$DIM: $CURRENT → $NEW (baseline: $BASELINE)"
  else
    # Update the state file
    jq ".dimensions.$DIM = $NEW" "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    echo "$DIM: $CURRENT → $NEW"
  fi
done

# Update timestamp
if [ "$DRY_RUN" = false ]; then
  jq ".lastUpdated = \"$NOW\"" "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
  echo ""
  echo "✅ State decayed toward baseline"
else
  echo ""
  echo "(dry run - no changes made)"
fi

# Clear old emotions from recent list (older than 24h)
if [ "$DRY_RUN" = false ]; then
  CUTOFF=$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "24 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
  jq ".recentEmotions = [.recentEmotions[] | select(.timestamp > \"$CUTOFF\")]" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null && mv "$STATE_FILE.tmp" "$STATE_FILE" || true
  
  # Sync to AMYGDALA_STATE.md for auto-injection
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  "$SCRIPT_DIR/sync-state.sh"
fi
