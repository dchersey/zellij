#!/bin/bash
# Claude Code statusline:
#   1. renders model · [branch] · {effort} · (output_style) · ~dir
#   2. colors the *zellij pane frame* by effort level so you can see at a glance
#      what each pane is running at:
#        ultracode = violet   max = red   xhigh = orange
#        high = cyan   medium = green   low = pink   (none = cleared)
#      Opus and Qwen sessions get their own color (periwinkle / sky blue), by model not effort.
#
# Ultracode reports as xhigh via .effort.level, so we disambiguate it from a plain
# /effort xhigh by checking the last `/effort` command recorded in the transcript.
# The frame is set via the fork's `zellij action set-pane-frame-color`, debounced
# so we only call zellij when the color actually changes.
input=$(cat)

j() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
model=$(j '.model.display_name')
model_id=$(j '.model.id')
cwd=$(j '.workspace.current_dir')
output_style=$(j '.output_style.name')
effort=$(j '.effort.level')
transcript=$(j '.transcript_path')
session_id=$(j '.session_id')

# Export this session's current effort so clauding-snapshot can bake it into restore
# layouts (preserve per-pane effort across restore). Keyed by session id; stable path
# ($HOME/.cache, NOT $TMPDIR) so a relay/LaunchAgent-run clauding-snapshot reads the
# same files. Write only on change. Raw .effort.level (ultracode -> xhigh, the right
# restore level since there's no --effort ultracode).
if [ -n "$session_id" ] && [ -n "$effort" ]; then
  edir="$HOME/.cache/claude-effort"; efile="$edir/$session_id"
  if [ "$(cat "$efile" 2>/dev/null)" != "$effort" ]; then
    mkdir -p "$edir" 2>/dev/null && printf '%s' "$effort" > "$efile" 2>/dev/null
  fi
fi

# --- setting: start from the effort level, then apply model + ultracode overrides ---
setting="$effort"

# Model override: a few models get their own color regardless of effort, so you can spot
# them at a glance (other models — e.g. Fable, Sonnet — just show the effort color). Match
# the model id / display name, case-insensitively.
case "$(printf '%s %s' "$model_id" "$model" | tr '[:upper:]' '[:lower:]')" in
  *qwen*) setting="qwen" ;;   # local Qwen (e.g. Claude Code -> Ollama on athena)
  *opus*) setting="opus" ;;   # Claude Opus
esac

# Ultracode (xhigh + a per-pane flag) is the explicit, top-priority signal and wins over
# the model color — it IS an Opus mode, so it must not be masked by the plain Opus color.
# Ultracode reports as plain "xhigh" via .effort.level with no external tell, so it's
# opt-in via the flag set by `claude-ultracode on` (run alongside /effort ultracode).
if [ "$effort" = "xhigh" ] && [ -n "${ZELLIJ_PANE_ID:-}" ] \
   && [ -f "${TMPDIR:-/tmp}/claude-ultracode-${ZELLIJ_PANE_ID}" ]; then
  setting="ultracode"
fi

# --- map setting -> hex (empty = clear the override) ---
case "$setting" in
  qwen)      color="#87ceeb" ;;  # sky blue (Qwen model)
  opus)      color="#b0b9f9" ;;  # periwinkle (Opus model)
  ultracode) color="#a667e2" ;;  # violet (Claude convention)
  max)       color="#ff3b30" ;;  # red
  xhigh)     color="#febb71" ;;  # orange
  high)      color="#00ced1" ;;  # cyan
  medium)    color="#2ecc71" ;;  # green
  low)       color="#ff69b4" ;;  # pink
  *)         color="" ;;
esac

# --- optional per-level color overrides ($HOME/.claude/effort-colors.json) ---
# A JSON object mapping effort level -> color (hex like "#fea644", or any value
# zellij's color parser accepts), e.g. {"xhigh":"#fea644"}. Partial: any level not
# listed keeps the built-in default above. Path overridable via $CLAUDE_EFFORT_COLORS.
ocfile="${CLAUDE_EFFORT_COLORS:-$HOME/.claude/effort-colors.json}"
if [ -n "$setting" ] && [ -f "$ocfile" ]; then
  oc=$(jq -r --arg k "$setting" '.[$k] // empty' "$ocfile" 2>/dev/null)
  [ -n "$oc" ] && color="$oc"
fi

# --- update the zellij pane frame, only when the color changes ---
# Use the FORK's zellij explicitly: a stock zellij on PATH (e.g. Homebrew's) lacks the
# `--frame` flag and fails silently, leaving the border unset — so never trust a bare
# `zellij`. Prefer ~/.local/bin (the fork's install path); override with $ZELLIJ_FRAME_BIN.
zj="${ZELLIJ_FRAME_BIN:-}"
[ -n "$zj" ] || { [ -x "$HOME/.local/bin/zellij" ] && zj="$HOME/.local/bin/zellij" || zj="zellij"; }
if [ "${ZELLIJ:-}" = "0" ] && [ -n "${ZELLIJ_PANE_ID:-}" ] && command -v "$zj" >/dev/null 2>&1; then
  # Debounce cache keyed by SESSION + pane id (pane ids restart low per session but
  # $TMPDIR is shared, so a pane-id-only key would skip a restored pane whose color
  # matches a previous session's cached value).
  sess=$(printf '%s' "${ZELLIJ_SESSION_NAME:-nosess}" | tr -c 'A-Za-z0-9_.-' '_')
  cache="${TMPDIR:-/tmp}/claude-frame-${sess}-${ZELLIJ_PANE_ID}"
  prev=$(cat "$cache" 2>/dev/null || echo "__none__")
  if [ "$color" != "$prev" ]; then
    # Run in the FOREGROUND (only on a change, so rare) and cache ONLY after the call
    # succeeds — a failed set (wrong binary, transient error) is then not remembered as
    # applied, so the next render retries instead of silently giving up (self-healing).
    if [ -n "$color" ]; then
      "$zj" action set-pane-color --pane-id "$ZELLIJ_PANE_ID" --frame "$color" >/dev/null 2>&1
    else
      "$zj" action set-pane-color --pane-id "$ZELLIJ_PANE_ID" --reset >/dev/null 2>&1
    fi
    if [ $? -eq 0 ]; then printf '%s' "$color" > "$cache"; fi
  fi
fi

# --- render the statusline ---
label="${setting:-?}"
dir_base=$(basename "$cwd" 2>/dev/null)
branch=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo detached)
fi
if [ -n "$branch" ]; then
  printf "\033[2m%s\033[0m \033[2m[%s]\033[0m \033[2m{%s}\033[0m \033[2m(%s)\033[0m \033[2m~%s\033[0m" \
    "$model" "$branch" "$label" "$output_style" "$dir_base"
else
  printf "\033[2m%s\033[0m \033[2m{%s}\033[0m \033[2m(%s)\033[0m \033[2m~%s\033[0m" \
    "$model" "$label" "$output_style" "$dir_base"
fi
