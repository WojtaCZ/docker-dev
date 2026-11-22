#!/usr/bin/env bash
# claude-usage: read the Claude plan limits and pace work against the 5-hour window.
#
#   claude-usage probe [--raw]   start a throwaway claude in tmux, run /usage, print
#                                "<name>\t<pct used>\t<reset text>" per limit (or the raw screen)
#   claude-usage pace [--fresh]  pace report for the 5h window (+ weekly) from a cached
#                                probe (<= CLAUDE_USAGE_TTL s old, default 300) or a new one
#   claude-usage ack             user said "keep going": no hard stop for this 5h window
#   claude-usage hook            Claude Code hook (SessionStart / PostToolUse), JSON on stdin
#
# The probe claude runs with hooks disabled, no MCP servers and CLAUDE_USAGE_PROBE=1, so
# it never recurses into these hooks. One probe at a time per machine (flock).
# Origin: ~/Downloads/usage.sh (tmux driving an interactive /usage).
set -u

STATE="${CLAUDE_USAGE_STATE:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage}"
TTL="${CLAUDE_USAGE_TTL:-300}"
TIMEOUT=30
mkdir -p "$STATE" 2>/dev/null

die() { echo "claude-usage: $*" >&2; exit 1; }

# ----------------------------------------------------------------------------- probe
probe() {
    local raw=0; [ "${1:-}" = "--raw" ] && raw=1
    command -v tmux   >/dev/null 2>&1 || die "tmux not found in PATH"
    command -v claude >/dev/null 2>&1 || die "claude not found in PATH"
    local workdir="$STATE/probe"; mkdir -p "$workdir"
    SESSION="claude-usage-$$"

    exec 9>"$STATE/probe.lock"
    flock -w 90 9 || die "another probe is still running"

    alive()  { tmux has-session -t "$SESSION" 2>/dev/null; }
    screen() { tmux capture-pane -p -t "$SESSION" 2>/dev/null; }
    trap 'tmux kill-session -t "$SESSION" 2>/dev/null' EXIT
    dump_screen() { echo "claude-usage: last screen was:" >&2; screen | sed '/^[[:space:]]*$/d' | tail -n 20 >&2; }
    wait_for() {
        local i
        for ((i = 0; i < TIMEOUT * 2; i++)); do
            alive || die "probe session ended unexpectedly (claude exited)"
            screen | grep -qE "$1" && return 0
            sleep 0.5
        done
        return 1
    }

    tmux new-session -d -s "$SESSION" -x 200 -y 100 -c "$workdir" \
        "env CLAUDE_USAGE_PROBE=1 DEV_SKIP_UPDATE=1 claude --strict-mcp-config --settings '{\"disableAllHooks\":true}'" \
        || die "failed to start tmux session"

    local TRUST="Yes, I trust this folder" READY="shift\+tab to cycle|\? for shortcuts"
    wait_for "$TRUST|$READY" || { dump_screen; die "claude did not start within ${TIMEOUT}s"; }
    if screen | grep -q "$TRUST"; then
        tmux send-keys -t "$SESSION" Down
        wait_for "❯ $TRUST" || { dump_screen; die "could not select '$TRUST'"; }
        tmux send-keys -t "$SESSION" Enter
        wait_for "$READY" || { dump_screen; die "claude prompt did not appear after trusting"; }
    fi
    sleep 1
    tmux send-keys -t "$SESSION" '/usage'; sleep 1
    tmux send-keys -t "$SESSION" Enter
    wait_for "[0-9]+(\.[0-9]+)?% *(used|left)" || { dump_screen; die "usage info did not appear within ${TIMEOUT}s"; }

    local prev="" cur="" i
    for ((i = 0; i < TIMEOUT * 2; i++)); do
        cur="$(screen)"; [ "$cur" = "$prev" ] && break
        prev="$cur"; sleep 0.5
    done
    tmux send-keys -t "$SESSION" Escape

    if [ "$raw" = 1 ]; then printf '%s\n' "$cur"; return 0; fi

    # A limit is any line with "<N>% used|left"; its name is the text before it on that
    # line or the nearest preceding text line; its reset is the next "Resets ..." line.
    local result
    result="$(printf '%s\n' "$cur" \
        | sed -E 's/(█|▉|▊|▋|▌|▍|▎|▏|▐|░|▒|▓|▀|▄|■|━|─|│|╭|╮|╰|╯)+/ /g' \
        | awk '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/[ \t]+/, " ", s); return s }
        function flush() { if (have) printf "%s\t%s\t%s\n", name, pct, reset; have = 0; reset = "" }
        {
            line = trim($0); if (line == "") next
            if (match(line, /[0-9]+(\.[0-9]+)?% *(used|left)/)) {
                flush()
                m = substr(line, RSTART, RLENGTH); p = m; sub(/%.*/, "", p)
                pct = (m ~ /left/) ? 100 - p : p + 0
                pre = trim(substr(line, 1, RSTART - 1)); name = (pre != "" ? pre : last)
                rest = trim(substr(line, RSTART + RLENGTH))
                if (match(rest, /Resets?:? */)) reset = trim(substr(rest, RSTART + RLENGTH))
                have = 1; next
            }
            if (have && reset == "" && match(line, /^Resets?:? */)) { reset = trim(substr(line, RLENGTH + 1)); next }
            last = line
        }
        END { flush() }')"
    [ -n "$result" ] || { dump_screen; die "no limits found in claude output"; }
    printf '%s\n' "$result" > "$STATE/last.tsv.tmp" && mv "$STATE/last.tsv.tmp" "$STATE/last.tsv"
    printf '%s\n' "$result"
}

cache_age() {   # seconds since the last successful probe, or a huge number
    local f="$STATE/last.tsv"
    [ -s "$f" ] || { echo 999999; return; }
    echo $(( $(date +%s) - $(stat -c %Y "$f") ))
}

refresh_bg() {  # start a probe detached unless one is already running
    # stdout/stderr detached: a hook's pipe left open would make Claude Code wait for the probe
    ( flock -n 8 || exit 0; setsid "$0" probe >/dev/null 2>"$STATE/probe.err" ) 8>"$STATE/refresh.lock" >/dev/null 2>&1 </dev/null &
    disown 2>/dev/null || true
}

# ------------------------------------------------------------------------------ pace
# Prints a report; the last line is VERDICT=<CRITICAL|FAST|OK|SLOW|UNKNOWN>.
pace_report() {
    python3 - "$STATE" <<'PY'
import os, re, sys, time, subprocess
state = sys.argv[1]
now = time.time()
W = 5 * 3600
try:
    rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(state, "last.tsv")) if l.strip()]
except OSError:
    print("no usage sample yet"); print("VERDICT=UNKNOWN"); sys.exit()
age = now - os.path.getmtime(os.path.join(state, "last.tsv"))

def reset_epoch(text):
    if not text: return None
    t = re.sub(r"^Resets?:?\s*", "", text.strip(), flags=re.I)
    m = re.search(r"in\s+(?:(\d+)\s*d)?\s*(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?", t)
    if t.lower().startswith("in") and m and any(m.groups()):
        d, h, mi = (int(x or 0) for x in m.groups()); return now + d*86400 + h*3600 + mi*60
    tz = None
    mt = re.search(r"\(([^)]+)\)", t)
    if mt: tz = mt.group(1); t = t[:mt.start()]
    t = t.replace(",", " ").replace(" at ", " ").strip()
    env = dict(os.environ, LC_ALL="C")
    if tz: env["TZ"] = tz
    try:
        e = int(subprocess.run(["date", "-d", t, "+%s"], capture_output=True, text=True, env=env, check=True).stdout)
    except Exception:
        return None
    while e < now - 60: e += 86400
    return e

def find(rx):
    for r in rows:
        if len(r) >= 2 and re.search(rx, r[0], re.I): return r
    return None

out, verdict = [], "UNKNOWN"
s = find(r"session") or find(r"5.?h")
if s:
    pct = float(s[1]); rst = reset_epoch(s[2] if len(s) > 2 else "")
    # history of (time, pct, reset) for a recent-rate estimate
    hist = os.path.join(state, "history.tsv")
    with open(hist, "a") as f: f.write(f"{int(now - age)}\t{pct}\t{int(rst or 0)}\n")
    samples = []
    for l in open(hist):
        try: t, p, r = l.split("\t"); samples.append((float(t), float(p), int(r)))
        except ValueError: pass
    if rst:
        remaining = max(0.0, rst - now); elapsed = min(W, max(60.0, W - remaining))
        same = [x for x in samples if abs(x[2] - rst) < 900 and x[0] >= now - 3600]
        # %/s, window average. /usage reports whole percents, so early in a window
        # "1%" after a minute would extrapolate to ~240%; assume at least 30 min
        # have passed. A real burst (e.g. 15% in 10 min) still projects >115%.
        rate = pct / max(elapsed, 1800.0)
        if same and (now - age) - same[0][0] >= 600 and pct >= same[0][1]:
            rate = (pct - same[0][1]) / ((now - age) - same[0][0])   # last hour's rate
        projected = pct + rate * remaining
        exp = elapsed / W * 100
        ack = os.path.exists(os.path.join(state, f"ack-{int(rst) // 600}"))
        out.append(f"5h window: {pct:.0f}% used, {elapsed/3600:.1f}h of 5h elapsed (even pace would be {exp:.0f}%), "
                   f"resets in {remaining/60:.0f} min")
        out.append(f"burn rate: {rate*3600:.1f}%/h -> projected {projected:.0f}% at reset")
        if rate > 0 and pct < 100:
            out.append(f"at this rate the limit is hit in {(100-pct)/rate/60:.0f} min")
        if pct >= 100: verdict = "CRITICAL"
        elif projected >= 115 or (pct >= 90 and remaining > 1800): verdict = "FAST" if ack else "CRITICAL"
        elif projected > 100: verdict = "FAST"
        elif projected < 75 and elapsed > 1800: verdict = "SLOW"
        else: verdict = "OK"
        if ack and verdict in ("FAST",): out.append("(user acknowledged the fast pace for this window)")
        open(os.path.join(state, "critical-window"), "w").write(str(int(rst) // 600))
        etaf = os.path.join(state, "eta")
        if pct >= 100: open(etaf, "w").write("1")
        elif rate > 0: open(etaf, "w").write(str(max(1, int((100 - pct) / rate / 60))))
        elif os.path.exists(etaf): os.remove(etaf)
    else:
        out.append(f"5h window: {pct:.0f}% used (reset time not parsed: {s[2] if len(s) > 2 else '-'})")
        verdict = "CRITICAL" if pct >= 95 else "FAST" if pct >= 80 else "OK"
w = find(r"week.*all") or find(r"week")
if w:
    out.append(f"weekly ({w[0]}): {float(w[1]):.0f}% used, resets {re.sub(r'^Resets?:? *', '', w[2]) if len(w) > 2 else '-'}")
    if float(w[1]) >= 95 and verdict != "CRITICAL": verdict = "FAST"
for r in rows:
    if r is not s and r is not w and len(r) >= 2: out.append(f"{r[0]}: {float(r[1]):.0f}% used")
out.append(f"(sample {age/60:.0f} min old)")
print("\n".join(out)); print(f"VERDICT={verdict}")
PY
}

pace() {
    if [ "${1:-}" = "--fresh" ] || [ "$(cache_age)" -gt "$TTL" ]; then
        probe >/dev/null || [ -s "$STATE/last.tsv" ] || exit 1
    fi
    pace_report
}

ack() {
    local rst
    rst="$(python3 - "$STATE" <<'PY'
import sys, os
try:
    l = open(os.path.join(sys.argv[1], "history.tsv")).read().splitlines()[-1]
    print(int(l.split("\t")[2]) // 600)
except Exception: print("")
PY
)"
    [ -n "$rst" ] && [ "$rst" != 0 ] || die "no 5h window known yet; run 'claude-usage pace' first"
    rm -f "$STATE/critical"; touch "$STATE/ack-$rst" && echo "acknowledged: no hard stop for the rest of this 5h window"
}

# ------------------------------------------------------------------------------ hook
# One entry point for SessionStart, PostToolUse, PreToolUse (Agent|Task|Workflow),
# SubagentStart and SubagentStop. Check interval per session:
#   base     CLAUDE_USAGE_HEAVY_EVERY (600 s) on Opus/Fable-class, CLAUDE_USAGE_LIGHT_EVERY (1800 s) else
#   agents   divided by (1 + running subagents) on this machine, so 10 agents -> ~1 min
#   burn     at most 1/6 of the projected time to exhaustion
#   floor    60 s
# A CRITICAL verdict is sticky: every tool call of every agent is blocked until a new
# sample is no longer critical or the user acks. Spawning a subagent or workflow
# re-checks first (probing inline if the sample is > 2 min old) and is denied when the
# pace is CRITICAL, or FAST unless the new agent runs on Sonnet/Haiku.
AGENTS="$STATE/agents"
running_agents() {
    mkdir -p "$AGENTS"
    find "$AGENTS" -type f -mmin +180 -delete 2>/dev/null   # crashed agents never send Stop
    find "$AGENTS" -type f | wc -l
}
emit() {  # emit <kind> <event> <text>
    python3 -c '
import json, sys
kind, ev, text = sys.argv[1:4]
text = text.replace("\\n", "\n")
if kind == "block":   o = {"decision": "block", "reason": text}
elif kind == "deny":  o = {"hookSpecificOutput": {"hookEventName": ev, "permissionDecision": "deny", "permissionDecisionReason": text}}
else:                 o = {"hookSpecificOutput": {"hookEventName": ev, "additionalContext": text}}
print(json.dumps(o))' "$@"
}
CRIT_MSG='STOP starting new work now. Finish only the step in progress; a subagent returns its partial result at once. Then report these numbers to the user and ask how to proceed (usage-pacing skill). If the user says to continue anyway, run `claude-usage ack`.'

evaluate() {  # sets REP and VERDICT from the cache; maintains the sticky critical flag
    REP="$(pace_report)"; VERDICT="$(sed -n 's/^VERDICT=//p' <<< "$REP")"
    REP="$(grep -v '^VERDICT=' <<< "$REP")"
    if [ "$VERDICT" = "CRITICAL" ]; then printf '%s\n' "$REP" > "$STATE/critical"; else rm -f "$STATE/critical"; fi
}

hook() {
    [ -n "${CLAUDE_USAGE_PROBE:-}" ] && exit 0
    [ "${CLAUDE_USAGE_PACING:-1}" = "0" ] && exit 0
    local input event transcript sid tool agent submodel model
    input="$(cat)"
    { read -r event; read -r transcript; read -r sid; read -r tool; read -r agent; read -r submodel; } < <(python3 -c '
import json, sys
try: d = json.loads(sys.stdin.read())
except Exception: d = {}
ti = d.get("tool_input") or {}
for v in (d.get("hook_event_name"), d.get("transcript_path"), d.get("session_id"), d.get("tool_name"),
          d.get("agent_id"), ti.get("model") if isinstance(ti, dict) else None):
    print(str(v or "-").replace("\n", " "))
' <<< "$input")
    model="$(printf '%s' "$input" | grep -o '"model"[^,}]*' | head -1)"
    if [ -z "$model" ] && [ -f "$transcript" ]; then
        model="$(tail -c 200000 "$transcript" | grep -o '"model":"[^"]*"' | tail -1)"
    fi
    local heavy=0 every="${CLAUDE_USAGE_LIGHT_EVERY:-1800}"
    if printf '%s' "$model" | grep -qiE 'opus|fable|mythos'; then every="${CLAUDE_USAGE_HEAVY_EVERY:-600}"; heavy=1; fi
    local n; n="$(running_agents)"
    every=$(( every / (1 + n) ))
    local eta; eta="$(cat "$STATE/eta" 2>/dev/null || true)"
    [ -n "$eta" ] && [ "$eta" -gt 0 ] && [ $(( eta * 60 / 6 )) -lt "$every" ] && every=$(( eta * 60 / 6 ))
    [ "$every" -lt 60 ] && every=60
    local ttl="$TTL"; [ "$every" -lt "$ttl" ] && ttl="$every"

    local stamp="$STATE/hook-${sid//[^A-Za-z0-9_-]/_}" now; now="$(date +%s)"
    case "$event" in
    SessionStart)
        [ "$(cache_age)" -gt "$ttl" ] && refresh_bg
        local rep="usage sample is being refreshed in the background; run 'claude-usage pace' when you need it"
        if [ "$(cache_age)" -le 3600 ]; then evaluate; rep="$REP"$'\n'"VERDICT=$VERDICT"; fi
        touch "$stamp"
        printf 'Usage pacing is ON (skill: usage-pacing). Model class: %s; pace checks every %d min now, more often while subagents run (%d running).\nAim to use the 5-hour window fully but not run out before it resets. Spawning subagents/workflows is re-checked and denied when the pace is too fast.\n%s\n' \
            "$([ $heavy = 1 ] && echo heavy || echo light)" $((every / 60)) "$n" "$rep"
        exit 0 ;;
    SubagentStart)
        [ "$agent" != "-" ] && touch "$AGENTS/${agent//[^A-Za-z0-9_-]/_}"
        emit context SubagentStart "Usage pacing is ON for this agent. If a hook blocks you with USAGE PACE CRITICAL, stop at once and return what you have so far, saying it was cut short for usage."
        exit 0 ;;
    SubagentStop)
        [ "$agent" != "-" ] && rm -f "$AGENTS/${agent//[^A-Za-z0-9_-]/_}"
        exit 0 ;;
    PreToolUse)
        case "$tool" in Agent|Task|Workflow) ;; *) exit 0 ;; esac
        if [ "$(cache_age)" -gt 120 ]; then timeout 45 "$0" probe >/dev/null 2>&1 || true; fi
        [ -s "$STATE/last.tsv" ] || exit 0
        evaluate; touch "$stamp"
        case "$VERDICT" in
            CRITICAL) emit deny PreToolUse "USAGE PACE CRITICAL: not starting a new $tool.\n$REP\n$CRIT_MSG" ;;
            FAST)
                if [ "$tool" != "Workflow" ] && printf '%s' "$submodel" | grep -qiE 'sonnet|haiku'; then
                    emit context PreToolUse "Usage pace is FAST ($n agents running); a $submodel subagent is allowed, but start no more than needed.\n$REP"
                else
                    emit deny PreToolUse "Usage pace is TOO FAST for the 5-hour window ($n agents already running), so no new heavy $tool.\n$REP\nRun it on model sonnet or haiku, wait for running agents to finish, or do it yourself in fewer steps."
                fi ;;
            *) [ "$n" -ge 3 ] && emit context PreToolUse "Pace check before spawning ($n agents running): $VERDICT.\n$REP" ;;
        esac
        exit 0 ;;
    esac

    # PostToolUse (main session and every subagent).
    if [ -s "$STATE/critical" ] && [ ! -e "$STATE/ack-$(cat "$STATE/critical-window" 2>/dev/null)" ]; then
        [ "$(cache_age)" -gt "$ttl" ] && refresh_bg
        [ "$(cache_age)" -le "$ttl" ] && evaluate       # a fresh sample may lift it
        if [ -s "$STATE/critical" ]; then
            emit block "$event" "USAGE PACE CRITICAL: the 5-hour limit will be exhausted well before it resets.\n$(cat "$STATE/critical")\n$CRIT_MSG"
        fi
        exit 0
    fi
    if [ -f "$stamp" ] && [ $((now - $(stat -c %Y "$stamp"))) -lt "$every" ]; then exit 0; fi
    if [ "$(cache_age)" -gt "$ttl" ]; then
        refresh_bg
        [ "$(cache_age)" -gt $((every * 2)) ] && [ "$(cache_age)" -gt 600 ] && exit 0   # nothing recent enough
    fi
    touch "$stamp"
    evaluate
    case "$VERDICT" in
        CRITICAL) emit block "$event" "USAGE PACE CRITICAL: the 5-hour limit will be exhausted well before it resets.\n$REP\n$CRIT_MSG" ;;
        FAST) emit context "$event" "Usage pace is TOO FAST for the 5-hour window ($n subagents running).\n$REP\nThrottle now (usage-pacing skill): no new parallel agents, delegate to cheaper models, read less, keep turns short." ;;
        SLOW) emit context "$event" "Usage pace is well UNDER the 5-hour window.\n$REP\nThere is headroom: where it helps the task, it is fine to be more thorough or parallel (usage-pacing skill)." ;;
    esac
    exit 0
}

case "${1:-pace}" in
    probe) shift; probe "$@" ;;
    pace)  shift; pace "$@" ;;
    ack)   ack ;;
    hook)  hook ;;
    -h|--help|help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command '$1' (probe|pace|ack|hook)" ;;
esac
