#!/bin/bash
# load-emotion.sh — Load emotional state for session context
# Usage: ./load-emotion.sh [--format prose|json|brief]

set -e

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
STATE_FILE="$WORKSPACE/memory/emotional-state.json"

if [ ! -f "$STATE_FILE" ]; then
  echo "No emotional state found."
  exit 0
fi

FORMAT="${1:-prose}"
[ "$1" = "--format" ] && FORMAT="$2"

case $FORMAT in
  json)
    cat "$STATE_FILE"
    ;;
    
  brief)
    VALENCE=$(jq -r '.dimensions.valence' "$STATE_FILE")
    AROUSAL=$(jq -r '.dimensions.arousal' "$STATE_FILE")
    CONNECTION=$(jq -r '.dimensions.connection' "$STATE_FILE")
    CURIOSITY=$(jq -r '.dimensions.curiosity' "$STATE_FILE")
    ENERGY=$(jq -r '.dimensions.energy' "$STATE_FILE")
    RECENT=$(jq -r '.recentEmotions[0].label // "neutral"' "$STATE_FILE")
    
    echo "Mood: $RECENT | V:$VALENCE A:$AROUSAL C:$CONNECTION Cu:$CURIOSITY E:$ENERGY"
    ;;
    
  prose|*)
    VALENCE=$(jq -r '.dimensions.valence' "$STATE_FILE")
    AROUSAL=$(jq -r '.dimensions.arousal' "$STATE_FILE")
    CONNECTION=$(jq -r '.dimensions.connection' "$STATE_FILE")
    CURIOSITY=$(jq -r '.dimensions.curiosity' "$STATE_FILE")
    ENERGY=$(jq -r '.dimensions.energy' "$STATE_FILE")
    
    # Interpret valence
    if (( $(echo "$VALENCE > 0.6" | bc -l) )); then
      VALENCE_DESC="positive, upbeat"
    elif (( $(echo "$VALENCE > 0.3" | bc -l) )); then
      VALENCE_DESC="slightly positive"
    elif (( $(echo "$VALENCE > -0.3" | bc -l) )); then
      VALENCE_DESC="neutral"
    elif (( $(echo "$VALENCE > -0.6" | bc -l) )); then
      VALENCE_DESC="slightly low"
    else
      VALENCE_DESC="low, subdued"
    fi
    
    # Interpret arousal
    if (( $(echo "$AROUSAL > 0.7" | bc -l) )); then
      AROUSAL_DESC="highly alert and energized"
    elif (( $(echo "$AROUSAL > 0.4" | bc -l) )); then
      AROUSAL_DESC="engaged"
    else
      AROUSAL_DESC="calm and relaxed"
    fi
    
    # Interpret connection
    if (( $(echo "$CONNECTION > 0.7" | bc -l) )); then
      CONNECTION_DESC="feeling very connected"
    elif (( $(echo "$CONNECTION > 0.4" | bc -l) )); then
      CONNECTION_DESC="moderately connected"
    else
      CONNECTION_DESC="feeling a bit distant"
    fi
    
    # Interpret curiosity
    if (( $(echo "$CURIOSITY > 0.7" | bc -l) )); then
      CURIOSITY_DESC="highly curious and eager to explore"
    elif (( $(echo "$CURIOSITY > 0.4" | bc -l) )); then
      CURIOSITY_DESC="curious"
    else
      CURIOSITY_DESC="not particularly curious right now"
    fi
    
    # Interpret energy
    if (( $(echo "$ENERGY > 0.7" | bc -l) )); then
      ENERGY_DESC="high energy"
    elif (( $(echo "$ENERGY > 0.4" | bc -l) )); then
      ENERGY_DESC="moderate energy"
    else
      ENERGY_DESC="low energy"
    fi
    
    # Recent emotion
    RECENT=$(jq -r '.recentEmotions[0].label // empty' "$STATE_FILE")
    RECENT_TRIGGER=$(jq -r '.recentEmotions[0].trigger // empty' "$STATE_FILE")
    
    echo "🎭 Current Emotional State:"
    echo ""
    echo "Overall mood: $VALENCE_DESC, $AROUSAL_DESC"
    echo "Connection: $CONNECTION_DESC"
    echo "Curiosity: $CURIOSITY_DESC"
    echo "Energy: $ENERGY_DESC"
    
    if [ -n "$RECENT" ]; then
      echo ""
      echo "Recent feeling: $RECENT"
      [ -n "$RECENT_TRIGGER" ] && [ "$RECENT_TRIGGER" != "unspecified" ] && echo "  (from: $RECENT_TRIGGER)"
    fi
    ;;
esac
