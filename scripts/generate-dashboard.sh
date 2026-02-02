#!/bin/bash
# generate-dashboard.sh — Generate unified Brain Dashboard (Amygdala version)
#
# Each brain skill has its own generator. Shows all installed skills + install prompts for missing ones.

set -e

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
OUTPUT_FILE="$WORKSPACE/brain-dashboard.html"

# Data files
HIPPOCAMPUS_FILE="$WORKSPACE/memory/index.json"
AMYGDALA_FILE="$WORKSPACE/memory/emotional-state.json"
VTA_FILE="$WORKSPACE/memory/reward-state.json"

# Detect installed skills
HAS_HIPPOCAMPUS=false
HAS_AMYGDALA=false
HAS_VTA=false

[ -f "$HIPPOCAMPUS_FILE" ] && HAS_HIPPOCAMPUS=true
[ -f "$AMYGDALA_FILE" ] && HAS_AMYGDALA=true
[ -f "$VTA_FILE" ] && HAS_VTA=true

# Need at least amygdala (this is the amygdala generator)
if [ "$HAS_AMYGDALA" != "true" ]; then
    echo "❌ No amygdala data found at $AMYGDALA_FILE"
    exit 1
fi

# Auto-detect from IDENTITY.md
AGENT_NAME="Agent"
AVATAR_PATH=""
if [ -f "$WORKSPACE/IDENTITY.md" ]; then
    AGENT_NAME=$(grep -E "^\*\*Name:\*\*|^- \*\*Name:\*\*" "$WORKSPACE/IDENTITY.md" | head -1 | sed 's/.*Name:\*\* *//' | sed 's/`//g' | tr -d '\r')
    AVATAR_RAW=$(grep -E "^\*\*Avatar:\*\*|^- \*\*Avatar:\*\*" "$WORKSPACE/IDENTITY.md" | head -1 | sed 's/.*Avatar:\*\* *//' | sed 's/`//g' | tr -d '\r')
    if [ -n "$AVATAR_RAW" ]; then
        if [[ "$AVATAR_RAW" == /* ]] || [[ "$AVATAR_RAW" == ~/* ]]; then
            AVATAR_PATH="${AVATAR_RAW/#\~/$HOME}"
        else
            AVATAR_PATH="$WORKSPACE/$AVATAR_RAW"
        fi
    fi
fi
[ -z "$AGENT_NAME" ] && AGENT_NAME="Agent"

# Fallback avatar
if [ -z "$AVATAR_PATH" ] || [ ! -f "$AVATAR_PATH" ]; then
    for candidate in "$WORKSPACE/avatar.png" "$WORKSPACE/avatar.jpg"; do
        [ -f "$candidate" ] && AVATAR_PATH="$candidate" && break
    done
fi

# Convert avatar to base64
AVATAR_BASE64=""
if [ -n "$AVATAR_PATH" ] && [ -f "$AVATAR_PATH" ]; then
    MIME_TYPE="image/png"
    [[ "$AVATAR_PATH" == *.jpg ]] || [[ "$AVATAR_PATH" == *.jpeg ]] && MIME_TYPE="image/jpeg"
    AVATAR_BASE64="data:$MIME_TYPE;base64,$(base64 < "$AVATAR_PATH" | tr -d '\n')"
fi

# Read amygdala data
VALENCE=$(jq -r '.dimensions.valence // 0' "$AMYGDALA_FILE")
AROUSAL=$(jq -r '.dimensions.arousal // 0.3' "$AMYGDALA_FILE")
CONNECTION=$(jq -r '.dimensions.connection // 0.4' "$AMYGDALA_FILE")
CURIOSITY=$(jq -r '.dimensions.curiosity // 0.5' "$AMYGDALA_FILE")
ENERGY=$(jq -r '.dimensions.energy // 0.5' "$AMYGDALA_FILE")
ANTICIPATION=$(jq -r '.dimensions.anticipation // 0' "$AMYGDALA_FILE")
TRUST=$(jq -r '.dimensions.trust // 0.5' "$AMYGDALA_FILE")
RECENT_EMOTIONS=$(jq -c '[.recentEmotions[-5:] // [] | .[] | {label, intensity, trigger}]' "$AMYGDALA_FILE")

vi=$(echo "$VALENCE * 100" | bc | cut -d. -f1)
ai=$(echo "$AROUSAL * 100" | bc | cut -d. -f1)
if [ "$vi" -gt 70 ] && [ "$ai" -gt 60 ]; then MOOD_EMOJI="😄"; MOOD_LABEL="Energized"; MOOD_COLOR="#10b981"
elif [ "$vi" -gt 50 ] && [ "$ai" -le 40 ]; then MOOD_EMOJI="😌"; MOOD_LABEL="Content"; MOOD_COLOR="#6366f1"
elif [ "$vi" -gt 50 ]; then MOOD_EMOJI="🙂"; MOOD_LABEL="Positive"; MOOD_COLOR="#8b5cf6"
elif [ "$vi" -lt -10 ] && [ "$ai" -gt 60 ]; then MOOD_EMOJI="😤"; MOOD_LABEL="Stressed"; MOOD_COLOR="#ef4444"
elif [ "$vi" -lt -10 ]; then MOOD_EMOJI="😔"; MOOD_LABEL="Low"; MOOD_COLOR="#64748b"
else MOOD_EMOJI="😐"; MOOD_LABEL="Neutral"; MOOD_COLOR="#94a3b8"; fi

# Read hippocampus if available
MEMORY_COUNT=0 CORE_COUNT=0 TOP_MEMORIES="[]"
if [ "$HAS_HIPPOCAMPUS" = "true" ]; then
    MEMORY_COUNT=$(jq '.memories | length' "$HIPPOCAMPUS_FILE")
    CORE_COUNT=$(jq '[.memories[] | select(.importance >= 0.7)] | length' "$HIPPOCAMPUS_FILE")
    TOP_MEMORIES=$(jq -c '[.memories | sort_by(-.importance) | .[:5] | .[] | {id, domain, importance, summary: (.content[:80] + "...")}]' "$HIPPOCAMPUS_FILE")
fi

# Read VTA if available
DRIVE=0.5 SEEKING="[]" ANTICIPATING="[]" RECENT_REWARDS="[]"
if [ "$HAS_VTA" = "true" ]; then
    DRIVE=$(jq -r '.drive // 0.5' "$VTA_FILE")
    SEEKING=$(jq -c '.seeking // []' "$VTA_FILE")
    ANTICIPATING=$(jq -c '.anticipating // []' "$VTA_FILE")
    RECENT_REWARDS=$(jq -c '[.recentRewards[-5:] // [] | .[] | {type, source, intensity}]' "$VTA_FILE")
fi

DRIVE_PCT=$(echo "$DRIVE * 100" | bc | cut -d. -f1)

# Generate HTML
cat > "$OUTPUT_FILE" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Brain Dashboard</title>
    <style>
        :root { --bg: #0f0f0f; --card: #1a1a1a; --border: #2e2e2e; --text: #fafafa; --muted: #71717a; --accent: #8b5cf6; }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: var(--bg); color: var(--text); min-height: 100vh; padding: 32px 16px; }
        .container { max-width: 560px; margin: 0 auto; }
        .header { display: flex; align-items: center; gap: 16px; margin-bottom: 24px; }
        .avatar { width: 56px; height: 56px; border-radius: 50%; object-fit: cover; border: 2px solid var(--accent); }
        .avatar-placeholder { width: 56px; height: 56px; border-radius: 50%; background: var(--accent); display: flex; align-items: center; justify-content: center; font-size: 24px; }
        .header h1 { font-size: 1.25rem; } .header .sub { color: var(--muted); font-size: 0.8rem; }
        .tabs { display: flex; gap: 4px; background: var(--card); padding: 4px; border-radius: 10px; margin-bottom: 16px; }
        .tab { flex: 1; padding: 8px; border: none; background: transparent; color: var(--muted); font-size: 0.8rem; cursor: pointer; border-radius: 6px; transition: 0.2s; }
        .tab:hover { background: #242424; } .tab.active { background: #242424; color: var(--text); }
        .tab-content { display: none; } .tab-content.active { display: block; }
        .card { background: var(--card); border-radius: 10px; padding: 16px; margin-bottom: 12px; }
        .card-title { font-size: 0.65rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--muted); margin-bottom: 10px; }
        .stats { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
        .stat { background: var(--bg); border-radius: 8px; padding: 12px; text-align: center; }
        .stat-val { font-size: 1.5rem; font-weight: 600; } .stat-label { font-size: 0.65rem; color: var(--muted); }
        .list-item { display: flex; gap: 8px; padding: 8px 0; border-bottom: 1px solid var(--border); font-size: 0.8rem; }
        .list-item:last-child { border: none; }
        .badge { background: var(--bg); padding: 2px 8px; border-radius: 6px; font-size: 0.7rem; white-space: nowrap; }
        .list-text { flex: 1; color: #a1a1aa; }
        .empty { color: var(--muted); text-align: center; padding: 16px; font-size: 0.85rem; }
        .install-prompt { text-align: center; padding: 24px; }
        .install-prompt .icon { font-size: 2rem; margin-bottom: 8px; opacity: 0.5; }
        .install-prompt p { color: var(--muted); font-size: 0.85rem; margin-bottom: 12px; }
        .install-prompt code { background: var(--bg); padding: 6px 12px; border-radius: 6px; font-size: 0.75rem; }
        .dim { display: flex; align-items: center; padding: 6px 0; }
        .dim-icon { width: 24px; } .dim-name { flex: 1; font-size: 0.8rem; }
        .dim-bar { width: 80px; height: 5px; background: var(--bg); border-radius: 3px; margin: 0 8px; overflow: hidden; }
        .dim-fill { height: 100%; border-radius: 3px; }
        .dim-val { width: 32px; text-align: right; font-size: 0.75rem; color: #a1a1aa; }
        .quadrant { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }
        .q-cell { background: var(--bg); border-radius: 6px; padding: 10px; text-align: center; border: 1px solid var(--border); }
        .q-cell.active { border-color: var(--accent); background: rgba(139,92,246,0.1); }
        .q-cell .emoji { font-size: 1rem; } .q-cell .label { font-size: 0.65rem; margin-top: 2px; }
        .drive-meter { text-align: center; padding: 16px; }
        .drive-val { font-size: 2rem; font-weight: 700; color: #f59e0b; }
        .drive-bar { height: 6px; background: var(--bg); border-radius: 3px; margin-top: 8px; }
        .drive-fill { height: 100%; background: linear-gradient(90deg, #f59e0b, #ef4444); border-radius: 3px; }
        .tags { display: flex; flex-wrap: wrap; gap: 6px; }
        .tag { background: var(--bg); padding: 4px 10px; border-radius: 10px; font-size: 0.7rem; color: #a1a1aa; }
        .footer { text-align: center; margin-top: 20px; font-size: 0.65rem; color: var(--muted); }
        .footer a { color: var(--accent); text-decoration: none; }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
HTMLHEAD

# Avatar
if [ -n "$AVATAR_BASE64" ]; then
    echo "        <img src=\"$AVATAR_BASE64\" class=\"avatar\">" >> "$OUTPUT_FILE"
else
    echo "        <div class=\"avatar-placeholder\">🎭</div>" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << HEADER
        <div><h1>$AGENT_NAME</h1><div class="sub">Brain Dashboard</div></div>
    </div>
    <div class="tabs">
        <button class="tab" data-tab="hippocampus">🧠 Memory</button>
        <button class="tab active" data-tab="amygdala">🎭 Emotions</button>
        <button class="tab" data-tab="vta">⭐ Drive</button>
    </div>
    
    <!-- Hippocampus Tab -->
    <div class="tab-content" id="tab-hippocampus">
HEADER

if [ "$HAS_HIPPOCAMPUS" = "true" ]; then
    cat >> "$OUTPUT_FILE" << HIPPO
        <div class="card">
            <div class="stats">
                <div class="stat"><div class="stat-val" style="color:#06b6d4">$MEMORY_COUNT</div><div class="stat-label">Total Memories</div></div>
                <div class="stat"><div class="stat-val" style="color:#06b6d4">$CORE_COUNT</div><div class="stat-label">Core Memories</div></div>
            </div>
        </div>
        <div class="card">
            <div class="card-title">Top Memories</div>
            <div id="topMemories"></div>
        </div>
HIPPO
else
    cat >> "$OUTPUT_FILE" << 'INSTALL_HIPPO'
        <div class="card">
            <div class="install-prompt">
                <div class="icon">🧠</div>
                <p>Hippocampus not installed</p>
                <p>Add memory formation & recall to your agent</p>
                <code>clawdhub install hippocampus</code>
            </div>
        </div>
INSTALL_HIPPO
fi

cat >> "$OUTPUT_FILE" << AMYGDALA_CONTENT
    </div>
    
    <!-- Amygdala Tab (active) -->
    <div class="tab-content active" id="tab-amygdala">
        <div class="card" style="text-align:center;padding:20px">
            <div style="font-size:3rem">$MOOD_EMOJI</div>
            <div style="font-size:1rem;font-weight:600;color:$MOOD_COLOR">$MOOD_LABEL</div>
        </div>
        <div class="card">
            <div class="card-title">Dimensions</div>
            <div id="dimensions"></div>
        </div>
        <div class="card">
            <div class="card-title">Mood Quadrant</div>
            <div class="quadrant">
                <div class="q-cell" id="q-stressed"><div class="emoji">😤</div><div class="label">Stressed</div></div>
                <div class="q-cell" id="q-energized"><div class="emoji">😄</div><div class="label">Energized</div></div>
                <div class="q-cell" id="q-depleted"><div class="emoji">😔</div><div class="label">Depleted</div></div>
                <div class="q-cell" id="q-content"><div class="emoji">😌</div><div class="label">Content</div></div>
            </div>
        </div>
        <div class="card">
            <div class="card-title">Recent Feelings</div>
            <div id="recentEmotions"></div>
        </div>
    </div>
    
    <!-- VTA Tab -->
    <div class="tab-content" id="tab-vta">
AMYGDALA_CONTENT

if [ "$HAS_VTA" = "true" ]; then
    cat >> "$OUTPUT_FILE" << VTA
        <div class="card">
            <div class="drive-meter">
                <div class="drive-val">${DRIVE_PCT}%</div>
                <div style="color:var(--muted);font-size:0.8rem">Drive Level</div>
                <div class="drive-bar"><div class="drive-fill" style="width:${DRIVE_PCT}%"></div></div>
            </div>
        </div>
        <div class="card">
            <div class="card-title">Seeking</div>
            <div id="vtaSeeking" class="tags"></div>
        </div>
        <div class="card">
            <div class="card-title">Looking Forward To</div>
            <div id="vtaAnticipating" class="tags"></div>
        </div>
        <div class="card">
            <div class="card-title">Recent Rewards</div>
            <div id="recentRewards"></div>
        </div>
VTA
else
    cat >> "$OUTPUT_FILE" << 'INSTALL_VTA'
        <div class="card">
            <div class="install-prompt">
                <div class="icon">⭐</div>
                <p>VTA not installed</p>
                <p>Add motivation & reward system to your agent</p>
                <code>clawdhub install vta-memory</code>
            </div>
        </div>
INSTALL_VTA
fi

cat >> "$OUTPUT_FILE" << 'FOOTER'
    </div>
    
    <div class="footer"><a href="https://github.com/ImpKind">AI Brain Series</a> 🎭</div>
</div>
<script>
FOOTER

# Inject data
cat >> "$OUTPUT_FILE" << JSDATA
const state = {
    hippocampus: { installed: $HAS_HIPPOCAMPUS, topMemories: $TOP_MEMORIES },
    amygdala: { dimensions: { valence:$VALENCE, arousal:$AROUSAL, connection:$CONNECTION, curiosity:$CURIOSITY, energy:$ENERGY, trust:$TRUST, anticipation:$ANTICIPATION }, recentEmotions: $RECENT_EMOTIONS },
    vta: { installed: $HAS_VTA, drive: $DRIVE, seeking: $SEEKING, anticipating: $ANTICIPATING, recentRewards: $RECENT_REWARDS }
};
JSDATA

cat >> "$OUTPUT_FILE" << 'JSEND'

// Tabs
document.querySelectorAll('.tab').forEach(t => t.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(x => x.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(x => x.classList.remove('active'));
    t.classList.add('active');
    document.getElementById('tab-' + t.dataset.tab).classList.add('active');
}));

// Hippocampus
if (state.hippocampus.installed) {
    const memEl = document.getElementById('topMemories');
    if (state.hippocampus.topMemories?.length) {
        state.hippocampus.topMemories.forEach(m => {
            memEl.innerHTML += `<div class="list-item"><span class="badge">${(m.importance*100).toFixed(0)}%</span><span class="list-text">${m.summary}</span></div>`;
        });
    } else memEl.innerHTML = '<div class="empty">No memories yet</div>';
}

// Amygdala
const dims = [
    {k:'valence',n:'Valence',i:'🎭',min:-1,max:1,c:'linear-gradient(90deg,#ef4444,#fbbf24,#10b981)'},
    {k:'arousal',n:'Arousal',i:'⚡',min:0,max:1,c:'linear-gradient(90deg,#3b82f6,#f97316)'},
    {k:'connection',n:'Connection',i:'💕',min:0,max:1,c:'#ec4899'},
    {k:'curiosity',n:'Curiosity',i:'🔍',min:0,max:1,c:'#06b6d4'},
    {k:'energy',n:'Energy',i:'🔋',min:0,max:1,c:'#eab308'},
    {k:'trust',n:'Trust',i:'🤝',min:0,max:1,c:'#10b981'}
];
const dimsEl = document.getElementById('dimensions');
dims.forEach(d => {
    const v = state.amygdala.dimensions[d.k]||0;
    const pct = ((v-d.min)/(d.max-d.min))*100;
    dimsEl.innerHTML += `<div class="dim"><span class="dim-icon">${d.i}</span><span class="dim-name">${d.n}</span><div class="dim-bar"><div class="dim-fill" style="width:${pct}%;background:${d.c}"></div></div><span class="dim-val">${v.toFixed(2)}</span></div>`;
});

const v=state.amygdala.dimensions.valence, a=state.amygdala.dimensions.arousal;
const q = (v>=0&&a>=0.5)?'energized':(v>=0)?'content':(a>=0.5)?'stressed':'depleted';
document.getElementById('q-'+q)?.classList.add('active');

const emotionsEl = document.getElementById('recentEmotions');
if (state.amygdala.recentEmotions?.length) {
    state.amygdala.recentEmotions.slice().reverse().forEach(e => {
        emotionsEl.innerHTML += `<div class="list-item"><span class="badge">${e.label}</span><span class="list-text">${e.trigger||'—'}</span></div>`;
    });
} else emotionsEl.innerHTML = '<div class="empty">No recent emotions</div>';

// VTA
if (state.vta.installed) {
    const seekEl = document.getElementById('vtaSeeking');
    const antEl = document.getElementById('vtaAnticipating');
    const rewEl = document.getElementById('recentRewards');
    (state.vta.seeking||[]).forEach(s => seekEl.innerHTML += `<span class="tag">${s}</span>`);
    if (!state.vta.seeking?.length) seekEl.innerHTML = '<div class="empty">Nothing sought</div>';
    (state.vta.anticipating||[]).forEach(a => antEl.innerHTML += `<span class="tag">${a}</span>`);
    if (!state.vta.anticipating?.length) antEl.innerHTML = '<div class="empty">Nothing anticipated</div>';
    if (state.vta.recentRewards?.length) {
        state.vta.recentRewards.slice().reverse().forEach(r => {
            rewEl.innerHTML += `<div class="list-item"><span class="badge">${r.type}</span><span class="list-text">${r.source||'—'}</span></div>`;
        });
    } else rewEl.innerHTML = '<div class="empty">No recent rewards</div>';
}
</script>
</body>
</html>
JSEND

echo "🎭 Dashboard generated: $OUTPUT_FILE"
