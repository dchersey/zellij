#!/bin/bash
# Claude Code statusline:
#   1. renders model · [branch] · {effort} · (output_style) · ~dir
#   2. colors the *zellij pane frame* by effort level so you can see at a glance
#      what each pane is running at:
#        ultracode = violet   max = red   xhigh = orange
#        high = cyan   medium = green   low = pink   (none = cleared)
#
# Ultracode reports as xhigh via .effort.level, so we disambiguate it from a plain
# /effort xhigh by checking the last `/effort` command recorded in the transcript.
# The frame is set via the fork's `zellij action set-pane-frame-color`, debounced
# so we only call zellij when the color actually changes.
input=$(cat)

j() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
model=$(j '.model.display_name')
cwd=$(j '.workspace.current_dir')
output_style=$(j '.output_style.name')
effort=$(j '.effort.level')
transcript=$(j '.transcript_path')

# --- effort "setting", distinguishing ultracode from a plain xhigh ---
# Ultracode reports as "xhigh" via .effort.level and there is NO external signal
# that separates them: the /effort argument isn't recorded in the transcript
# (<command-args> is empty) and the ultracode reminder isn't persisted. So
# ultracode is opt-in via a per-pane flag, set by `claude-ultracode on` (run it
# alongside /effort ultracode). When the flag is set and we're at xhigh -> violet.
setting="$effort"
if [ "$effort" = "xhigh" ] && [ -n "${ZELLIJ_PANE_ID:-}" ] \
   && [ -f "${TMPDIR:-/tmp}/claude-ultracode-${ZELLIJ_PANE_ID}" ]; then
  setting="ultracode"
fi

# --- map setting -> hex (empty = clear the override) ---
case "$setting" in
  ultracode) color="#8a2be2" ;;  # violet (Claude convention)
  max)       color="#ff3b30" ;;  # red
  xhigh)     color="#ff8c0d" ;;  # orange (matches frame_highlight)
  high)      color="#00ced1" ;;  # cyan
  medium)    color="#2ecc71" ;;  # green
  low)       color="#ff69b4" ;;  # pink
  *)         color="" ;;
esac

# --- update the zellij pane frame, only when the color changes ---
if [ "${ZELLIJ:-}" = "0" ] && [ -n "${ZELLIJ_PANE_ID:-}" ] && command -v zellij >/dev/null 2>&1; then
  cache="${TMPDIR:-/tmp}/claude-frame-${ZELLIJ_PANE_ID}"
  prev=$(cat "$cache" 2>/dev/null || echo "__none__")
  if [ "$color" != "$prev" ]; then
    printf '%s' "$color" > "$cache"
    if [ -n "$color" ]; then
      ( zellij action set-pane-color --pane-id "$ZELLIJ_PANE_ID" --frame "$color" >/dev/null 2>&1 & )
    else
      ( zellij action set-pane-color --pane-id "$ZELLIJ_PANE_ID" --reset >/dev/null 2>&1 & )
    fi
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
