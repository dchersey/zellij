# claude-effort-borders

Color each [zellij](https://zellij.dev) pane's **frame** by the
[Claude Code](https://docs.claude.com/en/docs/claude-code) session's reasoning
**effort level**, so across a screenful of parallel sessions you can see at a glance
what each one is running at. Ultracode gets its own color.

```
ultracode = violet    max = red    xhigh = orange
high = cyan    medium = green    low = pink    (none = frame cleared)
```

It's a Claude Code **statusLine** script: it renders the usual
`model · [branch] · {effort} · (style) · ~dir` line **and**, as a side effect, recolors
the current pane's frame to match the effort — via this fork's
`zellij action set-pane-color --frame <color>`.

## Requirements

- **This zellij fork** — or any zellij build with `set-pane-color --frame`
  (the `--frame` option, submitted upstream as
  [zellij-org/zellij#5303](https://github.com/zellij-org/zellij/pull/5303)). On stock
  zellij without it, the statusline text still renders fine; the frame just won't color
  (the call fails silently — see *Graceful degradation*).
- **Claude Code** with a configurable `statusLine`.
- **jq**.

## Files

| File | What it is |
|------|------------|
| `statusline-effort.sh` | The statusline. Reads Claude Code's status JSON, maps `.effort.level` → a color, and sets the pane frame (debounced; only calls zellij when the color changes). |
| `claude-ultracode` | Toggles a per-pane "ultracode" marker file (ultracode can't be detected externally — see below). |
| `uc` / `nuc` | One-keystroke shorthands for `claude-ultracode on` / `off`. |

## Install

```sh
# scripts onto your PATH
cp claude-ultracode uc nuc ~/bin/ && chmod +x ~/bin/claude-ultracode ~/bin/uc ~/bin/nuc
# the statusline anywhere
cp statusline-effort.sh ~/.claude/ && chmod +x ~/.claude/statusline-effort.sh
```

Then point Claude Code at it in `~/.claude/settings.json`:

```jsonc
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-effort.sh",
    "refreshInterval": 2          // sec; lets the frame follow /effort + the ultracode
                                  // flag WITHOUT a model turn. Omit and the frame only
                                  // updates on each assistant message.
  },
  "respondToBashCommands": false  // makes `!uc` / `!nuc` fire without prompting Claude
                                  // (true fire-and-forget). Global: affects all `!` cmds.
}
```

## Why ultracode needs a manual flag

The five normal effort levels (`low`…`max`) come straight from the status JSON
(`.effort.level`) and color automatically. **Ultracode does not.** It reports as plain
`"xhigh"` with **no distinguishing field anywhere in the JSON** (verified on Claude Code
2.1.191), so nothing external can tell ultracode from a plain `/effort xhigh`. The only
thing that *can* tell is Claude itself — it receives an "Ultracode is on" reminder
in-context each turn of an `/effort ultracode` session.

So ultracode is opt-in via a per-pane flag file
(`$TMPDIR/claude-ultracode-$ZELLIJ_PANE_ID`):

- `!uc` (or `claude-ultracode on`) when you `/effort ultracode` → frame turns violet.
- `!nuc` (or `claude-ultracode off`) when you leave it.

The statusline only honors the flag **at xhigh** (ultracode = xhigh + workflow
orchestration), so at any other level the flag is simply ignored.

## Optional: let Claude keep the border in sync

Since Claude is the only thing that can see ultracode, you can have it assert the flag
for you — add a rule like this to your `CLAUDE.md`:

> In any zellij pane (`$ZELLIJ` set), keep the violet ultracode tag mirrored to the
> real state, **without needing the effort level**:
> - See an **"Ultracode is on"** reminder → `claude-ultracode on`.
> - See an explicit **"ultracode is off"** reminder while the tag is still set →
>   `claude-ultracode off`. (Trigger = *no ultracode reminder* + *flag file present*;
>   confirm via `$TMPDIR/claude-ultracode-$ZELLIJ_PANE_ID` or just clear idempotently.)
> - See neither → leave it; bias toward asserting *on*.
>
> The tag mirrors ultracode; `!uc`/`!nuc` just beat the until-next-reply lag.

With this, ultracode → auto-violet and leaving it → auto-cleared; `!uc`/`!nuc` become
pure lag-beaters.

## Graceful degradation

- **Outside zellij** (`$ZELLIJ` unset): the statusline just renders its text line; no
  frame calls are made.
- **Stock zellij without `--frame`**: text still renders; the `set-pane-color --frame`
  call is backgrounded with stderr discarded, so it fails silently — no frame color, no
  errors, no slowdown.

## Customizing colors

Edit the `case "$setting" in … esac` block near the bottom of `statusline-effort.sh` —
each level maps to a hex string (or empty to clear the frame).
