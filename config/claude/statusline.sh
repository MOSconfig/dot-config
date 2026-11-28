#!/usr/bin/env bash
# Custom status line for Claude Code (~/.claude/statusline.sh).
#
# Sibling of ~/.copilot/statusline.sh: the same two-line Apollo design.
# Every item is an accent-colored Nerd Font icon, a muted label, and its
# value. Items are separated by a thin rule and hide when they have no data.
#
# Claude Code feeds this script a JSON payload on stdin. Schema reference:
#   https://code.claude.com/docs/en/statusline
# Fields we read (a missing field hides its item, never an error):
#   .model.display_name | .model.id          -> Model
#   .workspace.current_dir | .cwd            -> Path and the Git state
#   .effort.level                            -> Effort (falls back to
#                                               MODEL_REASONING_EFFORT)
#   .context_window.used_percentage          -> Context bar (color-graded)
#   .context_window.context_window_size      -> Context capacity
#   .cost.total_lines_added/removed          -> Diff (+a -r)
#   .session_id                              -> btw (mermaid-tty's marker)
#
# Layout: a padding row, then two lines.
#   L1: Model (aqua), Effort (purple), WakaTime (yellow), Venv (green), and
#       Context last (blue): a ten-cell bar, the percentage in
#       green/yellow/red, and the capacity, e.g. "45% of 1.0M".
#   L2: Branch (orange) with its indicators (✓ clean or ● dirty, aqua
#       ahead/behind, and a purple stash icon with the count only when
#       there are stashes), then Diff (blue): this session's +added in green
#       and -removed in red, nonzero parts only, hidden when both are 0;
#       then btw (yellow): "answering Ns" while mermaid-tty answers a /btw
#       in this session (its marker, ~/.cache/mermaid-tty/btw-<session_id>,
#       is 1 and under 300 s old);
#       then Path (aqua) at the right end. With COLUMNS known, the path is
#       right-aligned and shortened from the left (…/) to fit; otherwise it
#       follows the other items after the rule.
#
# Env overrides (mirror the copilot one for muscle memory):
#   CLAUDE_STATUSLINE_NO_ICONS=1  drop icons, keep text labels
#   CLAUDE_STATUSLINE_NO_COLOR=1  drop color (still pads + separators)
#   CLAUDE_STATUSLINE_PAD_TOP=N   padding rows before the lines (default 1)
#   CLAUDE_STATUSLINE_PAD_LEFT=N  spaces before the lines     (default 0)
#   CLAUDE_STATUSLINE_PAD_RIGHT=N spaces after the lines      (default 0)
#
# Quick check that all icons render in your terminal:
#     ~/.claude/statusline.sh --test
#
# Bash 3.2-compatible (macOS default). Avoid `set -e` so one bad segment
# can never blank the whole line.

set -u

# A file's change time in epoch seconds, or 0 when it cannot be read. GNU
# stat is tried first: BSD's -f would print the file system there instead of
# failing, and its output would be taken for a time. Anything but digits is 0.
file_mtime() {
  local t
  t="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || t=0
  case "$t" in '' | *[!0123456789]*) t=0 ;; esac
  printf '%s' "$t"
}


# --- Configuration ---------------------------------------------------------
# A literal `\n` token in SEGMENTS starts the next line. `path` is placed at
# the right end of its line. Segments without data take no space.
SEGMENTS="model effort waka venv ctx \n branch diff btw path"
SEP=' │ '

ICONS_ON=1
[ -n "${CLAUDE_STATUSLINE_NO_ICONS:-}" ] && ICONS_ON=0

# Nerd Font icons. Bash 3.2 (macOS default) does not support `\uXXXX` in
# $'...' quoting — only `\xHH` — so each codepoint is spelled as raw
# UTF-8 bytes. All glyphs are FontAwesome (U+F0xx-F2xx range), the same
# subset Copilot's statusline uses. Verify with --test.
#
#   U+F2DB microchip        = EF 8B 9B   Model
#   U+F0E4 dashboard        = EF 83 A4   Effort
#   U+F11C keyboard         = EF 84 9C   WakaTime
#   U+F1AE flask            = EF 86 AE   Venv
#   U+F1C0 database         = EF 87 80   Context
#   U+F126 code-fork        = EF 84 A6   Branch
#   U+F27A commenting       = EF 89 BA   btw
#   U+F187 archive          = EF 86 87   Stash
#   U+F440 diff             = EF 91 80   Diff
#   U+F07C folder-open      = EF 81 BC   Path
ICON_MODEL=$'\xef\x8b\x9b'
ICON_EFFORT=$'\xef\x83\xa4'
ICON_WAKA=$'\xef\x84\x9c'
ICON_VENV=$'\xef\x86\xae'
ICON_CTX=$'\xef\x87\x80'
ICON_BRANCH=$'\xef\x84\xa6'
ICON_BTW=$'\xef\x89\xba'
ICON_STASH=$'\xef\x86\x87'
ICON_DIFF=$'\xef\x91\x80'
ICON_PATH=$'\xef\x81\xbc'

C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
C_PURPLE=""; C_AQUA=""; C_ORANGE=""; C_FG=""; C_FG_DIM=""
APOLLO_STATUSLINE_COLORS="${HOME}/.local/share/dot-configs/apollo/current/generated/statusline-colors.sh"
if [ -z "${CLAUDE_STATUSLINE_NO_COLOR:-}" ] && [ -f "$APOLLO_STATUSLINE_COLORS" ]; then
  source "$APOLLO_STATUSLINE_COLORS"
fi
# The icon carries the accent; labels are muted so the values read first.
# The generated include has no darker rule role, so the separators and the
# empty context cells use the same inactive foreground as the labels.
C_MUTED="$C_FG_DIM"
C_RULE="$C_FG_DIM"
C_PATH_VALUE="$C_FG"

PAD_TOP="${CLAUDE_STATUSLINE_PAD_TOP:-1}"
PAD_LEFT="${CLAUDE_STATUSLINE_PAD_LEFT:-0}"
PAD_RIGHT="${CLAUDE_STATUSLINE_PAD_RIGHT:-0}"

repeat() {
  local ch=$1 n=$2 out=""
  while [ "$n" -gt 0 ]; do out="${out}${ch}"; n=$((n - 1)); done
  printf '%s' "$out"
}

CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline-cache-$USER"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- --test flag: visually verify which icons render -----------------------
if [ "${1:-}" = "--test" ]; then
  has_fc=0
  command -v fc-list >/dev/null 2>&1 && has_fc=1
  printf 'Codepoint  Glyph  Label    Font check\n'
  printf -- '---------- ------ -------- ----------------------------------------\n'
  while IFS='|' read -r cp_hex glyph lbl; do
    [ -z "$cp_hex" ] && continue
    fc_status='(fc-list not installed)'
    if [ "$has_fc" = "1" ]; then
      fonts="$(fc-list ":charset=$cp_hex" 2>/dev/null \
                | grep -v '^/.*\.LastResort' | wc -l | tr -d ' ')"
      if [ "$fonts" -gt 0 ]; then
        fc_status="✓ in $fonts font(s)"
      else
        fc_status="✗ MISSING from real fonts"
      fi
    fi
    printf 'U+%-7s  %s     %-7s  %s\n' "$cp_hex" "$glyph" "$lbl" "$fc_status"
  done <<TEST_ICONS_EOF
f2db|${ICON_MODEL}|Model
f0e4|${ICON_EFFORT}|Effort
f11c|${ICON_WAKA}|WakaTime
f1ae|${ICON_VENV}|Venv
f1c0|${ICON_CTX}|Context
f126|${ICON_BRANCH}|Branch
f27a|${ICON_BTW}|btw
f187|${ICON_STASH}|Stash
f440|${ICON_DIFF}|Diff
f07c|${ICON_PATH}|Path
TEST_ICONS_EOF
  exit 0
fi

# --- 1. Read JSON payload from stdin ---------------------------------------
session_json=""
if [ ! -t 0 ]; then
  session_json="$(cat 2>/dev/null || true)"
fi

# --- 2. Parse the fields with pure-bash regex (no jq fork) -----------------
# Claude Code's payload is shallow JSON with stable keys. Pure-bash parsing
# avoids the ~22ms jq startup per render. Every key we read is unique
# within the payload, so targeted regex against the raw text is enough.
model_name=""
cwd=""
effort_level=""
ctx_pct=""
ctx_size=""
lines_added="0"
lines_removed="0"

# jget_str <key>  -> first matching "key": "value" string into __JV
# jget_num <key>  -> first matching "key": number/bool/null into __JV
# Both use the global $session_json haystack; both clear __JV on no-match.
__JV=""
jget_str() {
  __JV=""
  [[ "$session_json" =~ \"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && __JV="${BASH_REMATCH[1]}"
}
jget_num() {
  __JV=""
  if [[ "$session_json" =~ \"$1\"[[:space:]]*:[[:space:]]*([-0-9.]+|true|false|null) ]]; then
    [ "${BASH_REMATCH[1]}" != "null" ] && __JV="${BASH_REMATCH[1]}"
  fi
}

if [ -n "$session_json" ]; then
  jget_str "display_name";              model_name="$__JV"
  [ -z "$model_name" ] && { jget_str "id"; model_name="$__JV"; }
  jget_str "current_dir";               cwd="$__JV"
  [ -z "$cwd" ] && { jget_str "cwd";   cwd="$__JV"; }
  jget_str "level";                     effort_level="$__JV"
  jget_num "used_percentage";           ctx_pct="$__JV"
  jget_num "context_window_size";       ctx_size="$__JV"
  jget_num "total_lines_added";         lines_added="${__JV:-0}"
  jget_num "total_lines_removed";       lines_removed="${__JV:-0}"
fi

# Report the Git state of the workspace, not of wherever Claude Code was
# launched from.
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  cd "$cwd" 2>/dev/null || true
fi

# --- 3. Helpers ------------------------------------------------------------
label() {
  # "<accent icon> <muted label> " — written into $__LBL via printf -v so
  # callers can splice it without a `$(label ...)` subshell fork.
  local color="$1" icon="$2" text="$3"
  if [ "$ICONS_ON" = "1" ]; then
    printf -v __LBL '%s%s %s%s%s ' "$color" "$icon" "$C_MUTED" "$text" "$C_RESET"
  else
    printf -v __LBL '%s%s%s ' "$C_MUTED" "$text" "$C_RESET"
  fi
}

# The marker mermaid-tty writes while it answers a /btw in session id, into
# BTW_FILE; false for an id that is not a plain lowercase ASCII name, so
# nothing else is ever put into the path, and a disk that ignores case never
# gives two ids one file (session ids are lowercase UUIDs). The class is
# spelled out, as a range would follow the locale and let other letters in.
btw_marker() {
  BTW_FILE=""
  case "$1" in
    '' | *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) return 1 ;;
  esac
  BTW_FILE="$HOME/.cache/mermaid-tty/btw-$1"
}

# Whether the marker at $1 says a /btw is being answered: it is one or two
# bytes, 1 and an optional newline, and changed under 300 s ago; its age in
# seconds goes to BTW_AGE. The size is checked first, as bash cannot hold a NUL
# in a variable: a 1 followed by a NUL and more would read as just 1.
btw_age() {
  local mark="" size now mtime
  BTW_AGE=0
  [ -f "$1" ] || return 1
  size="$(wc -c <"$1" 2>/dev/null)" || return 1
  size="${size//[!0123456789]/}"
  case "$size" in 1 | 2) ;; *) return 1 ;; esac
  IFS= read -r -d '' mark <"$1" 2>/dev/null || true
  case "$size:$mark" in "1:1" | "2:1"$'\n') ;; *) return 1 ;; esac
  mtime="$(file_mtime "$1")"
  [ "$mtime" -gt 0 ] || return 1
  now="$(date +%s)"
  BTW_AGE=$((now - mtime))
  [ "$BTW_AGE" -ge 0 ] && [ "$BTW_AGE" -lt 300 ]
}

is_pos_int() {
  case "${1:-}" in
    '' | *[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

# Format a duration in seconds as "Nd Hh Mm" / "Nh Mm" / "Nm".
fmt_dhm() {
  local s=${1:-0}
  if [ "$s" -ge 86400 ]; then
    printf '%dd%dh%dm' $((s / 86400)) $(((s % 86400) / 3600)) $(((s % 3600) / 60))
  elif [ "$s" -ge 3600 ]; then
    printf '%dh%dm' $((s / 3600)) $(((s % 3600) / 60))
  elif [ "$s" -ge 60 ]; then
    printf '%dm' $((s / 60))
  else
    printf '%ds' "$s"
  fi
}

# Format a token count for the Context capacity: 200000 -> 200k, 1000000 -> 1.0M.
fmt_tokens() {
  local n=${1:-0}
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    # Integer math: e.g. 1500000 -> "1.5M". Compute tenths separately.
    local whole=$(( n / 1000000 ))
    local tenths=$(( (n % 1000000) / 100000 ))
    printf '%d.%dM' "$whole" "$tenths"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    printf '%dk' $(( n / 1000 ))
  else
    printf '%d' "$n"
  fi
}

# Visible width of a rendered string: ANSI color codes take no columns and
# each UTF-8 character counts once (continuation bytes are dropped), so the
# result does not depend on the locale.
vis_width() {
  printf '%s' "$1" | LC_ALL=C sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '
}

# The folder path for the Path item: the workspace (or $PWD), with $HOME as ~.
path_text() {
  local p="${cwd:-$PWD}"
  [ -n "$p" ] || return 0
  case "$p" in
    "$HOME") p="~" ;;
    "$HOME"/*) p="~${p#"$HOME"}" ;;
  esac
  __PATH_TEXT="$p"
}

# Shorten a path from the left to at most $2 columns, keeping whole folder
# names: ~/a/b/c/d -> …/c/d. The last folder stays even when it is wider.
# Result in $__SHORT.
shorten_path() {
  local rest="$1" max="$2"
  __SHORT="$1"
  [ "$(vis_width "$__SHORT")" -le "$max" ] && return 0
  while :; do
    case "$rest" in
      */*) rest="${rest#*/}" ;;
      *) return 0 ;;
    esac
    __SHORT="…/$rest"
    [ "$(vis_width "$__SHORT")" -le "$max" ] && return 0
  done
}

# Join a line's segments with the path at its right end. With COLUMNS the
# path is right-aligned (keeping a six-column margin) and shortened to fit;
# otherwise it follows the segments after the rule. Result in $__LINE.
finish_path_line() {
  local left="$1" prefix cols usable lw pw room gap
  __LINE="$left"
  [ -n "$__PATH_TEXT" ] || return 0
  label "$C_AQUA" "$ICON_PATH" 'Path'
  prefix="$__LBL"
  cols="${COLUMNS:-0}"
  case "$cols" in '' | *[!0-9]*) cols=0 ;; esac
  if [ "$cols" -gt 0 ] && [ -n "$left" ]; then
    usable=$((cols - 6 - PAD_LEFT - PAD_RIGHT))
    lw="$(vis_width "$left")"
    pw="$(vis_width "$prefix")"
    room=$((usable - lw - 3 - pw))
    if [ "$room" -ge 8 ]; then
      shorten_path "$__PATH_TEXT" "$room"
      gap=$((usable - lw - pw - $(vis_width "$__SHORT")))
      [ "$gap" -ge 3 ] || gap=3
      __LINE="${left}$(repeat ' ' "$gap")${prefix}${C_PATH_VALUE}${__SHORT}${C_RESET}"
      return 0
    fi
  fi
  if [ -n "$left" ]; then
    __LINE="${left}${C_RULE}${SEP}${C_RESET}${prefix}${C_PATH_VALUE}${__PATH_TEXT}${C_RESET}"
  else
    __LINE="${prefix}${C_PATH_VALUE}${__PATH_TEXT}${C_RESET}"
  fi
}

# --- 4. Segment functions --------------------------------------------------
# Each seg_* writes its rendered text into the global $__SEG via `printf -v`.
# Returning early (no output) leaves __SEG untouched — the render loop reads
# it and skips empty values. This avoids one `$(...)` subshell fork per
# segment per render.
seg_model() {
  [ -n "$model_name" ] || return 0
  # Trim long internal names: "claude-opus-4.7-1m-internal" -> "opus-4.7-1m"
  local short="$model_name"
  short="${short#claude-}"
  short="${short%-internal}"
  label "$C_AQUA" "$ICON_MODEL" 'Model'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$short" "$C_RESET"
}

seg_effort() {
  # Claude Code's payload carries `.effort.level`, the session's level,
  # including a /effort change made for this session only. The payload omits
  # it when the model does not support effort. Then fall back to the
  # MODEL_REASONING_EFFORT env var: Claude Code exports settings.json's
  # `env` block to the statusline subprocess. The copilot statusline instead
  # derives effort from the "(xhigh)" suffix in the model name.
  local lvl="${effort_level:-${MODEL_REASONING_EFFORT:-}}"
  [ -n "$lvl" ] || return 0
  label "$C_PURPLE" "$ICON_EFFORT" 'Effort'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$lvl" "$C_RESET"
}

# Context — a ten-cell bar, the used percentage graded green → yellow → red,
# and the muted capacity. Hidden while the percentage is 0 or missing.
seg_ctx() {
  [ -n "$ctx_pct" ] || return 0
  # Truncate to int by stripping the decimal portion — saves an awk fork.
  local pct_int="${ctx_pct%%.*}"
  is_pos_int "$pct_int" || return 0
  local color="$C_GREEN" filled body
  if [ "$pct_int" -ge 80 ]; then
    color="$C_RED"
  elif [ "$pct_int" -ge 50 ]; then
    color="$C_YELLOW"
  fi
  filled=$(( (pct_int + 5) / 10 ))
  [ "$filled" -le 10 ] || filled=10
  body="${color}$(repeat '▰' "$filled")${C_RESET}${C_RULE}$(repeat '▱' $((10 - filled)))${C_RESET} ${color}${pct_int}%${C_RESET}"
  if is_pos_int "$ctx_size"; then
    body="${body}${C_MUTED} of $(fmt_tokens "$ctx_size")${C_RESET}"
  fi
  label "$C_BLUE" "$ICON_CTX" 'Context'
  printf -v __SEG '%s%s' "$__LBL" "$body"
}

seg_venv() {
  [ -n "${VIRTUAL_ENV:-}" ] || return 0
  label "$C_GREEN" "$ICON_VENV" 'Venv'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "${VIRTUAL_ENV##*/}" "$C_RESET"
}

# Diff — this session's code changes: +added in green and -removed in red,
# only the nonzero parts; hidden when both are 0.
seg_diff() {
  local a="${lines_added:-0}" r="${lines_removed:-0}" body=""
  is_pos_int "$a" && body="${C_GREEN}+${a}${C_RESET}"
  if is_pos_int "$r"; then
    [ -n "$body" ] && body="${body} "
    body="${body}${C_RED}-${r}${C_RESET}"
  fi
  [ -n "$body" ] || return 0
  label "$C_BLUE" "$ICON_DIFF" 'Diff'
  printf -v __SEG '%s%s' "$__LBL" "$body"
}

# --- Pre-compute shared git state ------------------------------------------
# git/branch/stash all need the same plumbing. Calling git on every render
# costs ~50ms even after consolidation — and git state almost never changes
# between keystrokes. Cache the computed values per-cwd with a 5-second TTL,
# so vim-mode-driven re-renders (which dominate after pressing Esc) skip
# git entirely on the hot path.
GIT_INSIDE=0
GIT_DIRTY=""
GIT_BRANCH=""
GIT_SYNC=""
GIT_STASH_COUNT=0

# Per-cwd cache key. Keep it short — just the cwd hash, since we don't
# invalidate across branches; that's fine because the TTL caps staleness.
__cwd_hash="$(printf '%s' "${PWD}" | cksum | awk '{print $1}')"
__git_cache="$CACHE_DIR/git-${__cwd_hash}"
__use_cache=0
if [ -f "$__git_cache" ]; then
  __mtime="$(file_mtime "$__git_cache")"
  __age=$(( $(date +%s) - __mtime ))
  if [ "$__age" -lt 5 ]; then
    __use_cache=1
    # shellcheck disable=SC1090
    . "$__git_cache" 2>/dev/null || __use_cache=0
  fi
fi

if [ "$__use_cache" = 0 ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_INSIDE=1
  # status + branch + upstream sync in one shot via `git status --porcelain=v2 --branch`.
  __gs="$(git status --porcelain=v2 --branch 2>/dev/null)"
  __dirty_lines="$(printf '%s\n' "$__gs" | grep -cv '^#')"
  [ "$__dirty_lines" -gt 0 ] 2>/dev/null && GIT_DIRTY=1
  GIT_BRANCH="$(printf '%s\n' "$__gs" | awk '/^# branch.head /{print $3; exit}')"
  __ab="$(printf '%s\n' "$__gs" | awk '/^# branch.ab /{print $3" "$4; exit}')"
  if [ -n "$__ab" ]; then
    __ahead="${__ab%% *}"; __behind="${__ab##* }"
    __ahead="${__ahead#+}"; __behind="${__behind#-}"
    [ "${__ahead:-0}" -gt 0 ] 2>/dev/null && GIT_SYNC="${GIT_SYNC}↑${__ahead}"
    [ "${__behind:-0}" -gt 0 ] 2>/dev/null && GIT_SYNC="${GIT_SYNC}↓${__behind}"
  fi
  if [ "$GIT_BRANCH" = "(detached)" ] || [ -z "$GIT_BRANCH" ]; then
    GIT_BRANCH="$(git rev-parse --short HEAD 2>/dev/null)"
  fi
  GIT_STASH_COUNT="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  # Persist for the next renders within the TTL window.
  {
    printf 'GIT_INSIDE=%s\n' "$GIT_INSIDE"
    printf 'GIT_DIRTY=%q\n' "$GIT_DIRTY"
    printf 'GIT_BRANCH=%q\n' "$GIT_BRANCH"
    printf 'GIT_SYNC=%q\n' "$GIT_SYNC"
    printf 'GIT_STASH_COUNT=%s\n' "$GIT_STASH_COUNT"
  } >"$__git_cache" 2>/dev/null || true
fi

# Branch with its indicators: ✓ clean or ● dirty, ahead/behind, and the
# stash icon with the count only when there are stashes.
seg_branch() {
  [ "$GIT_INSIDE" = 1 ] || return 0
  local br="${GIT_BRANCH:-detached}" state
  if [ ${#br} -gt 24 ]; then
    br="${br:0:23}…"
  fi
  if [ -n "$GIT_DIRTY" ]; then
    if [ "$ICONS_ON" = "1" ]; then state="${C_YELLOW}●${C_RESET}"; else state="${C_YELLOW}dirty${C_RESET}"; fi
  else
    if [ "$ICONS_ON" = "1" ]; then state="${C_GREEN}✓${C_RESET}"; else state="${C_GREEN}clean${C_RESET}"; fi
  fi
  label "$C_ORANGE" "$ICON_BRANCH" 'Branch'
  printf -v __SEG '%s%s%s%s %s' "$__LBL" "$C_FG" "$br" "$C_RESET" "$state"
  if [ -n "$GIT_SYNC" ]; then
    __SEG="${__SEG} ${C_AQUA}${GIT_SYNC}${C_RESET}"
  fi
  if is_pos_int "$GIT_STASH_COUNT"; then
    if [ "$ICONS_ON" = "1" ]; then
      __SEG="${__SEG} ${C_PURPLE}${ICON_STASH} ${GIT_STASH_COUNT}${C_RESET}"
    else
      __SEG="${__SEG} ${C_PURPLE}stash ${GIT_STASH_COUNT}${C_RESET}"
    fi
  fi
}

# btw — mermaid-tty answering a /btw side question in this session. With
# MERMAID_TTY_BTW_STATUS=file, mermaid-tty writes 1 to its marker while it
# answers and empties it after; a marker older than 300 s is a crashed or
# stuck session's and stays hidden. The marker's age is how long it has run.
# Only this session's one marker is looked at, so the render costs the same
# however many past sessions left an empty one.
seg_btw() {
  [ -d "$HOME/.cache/mermaid-tty" ] || return 0
  btw_session_id
  btw_marker "$BTW_ID" || return 0
  btw_age "$BTW_FILE" || return 0
  btw_confirm_id "$BTW_ID" || return 0
  label "$C_YELLOW" "$ICON_BTW" 'btw'
  printf -v __SEG '%s%sanswering %ds%s' "$__LBL" "$C_FG" "$BTW_AGE" "$C_RESET"
}

# This session's id into BTW_ID, choosing which one marker to look at. When
# the payload's text names "session_id" exactly once and escapes nothing, that
# value is read straight from the text: nearly always, and with no jq. Any
# other payload, with a nested id or an escaped key, is resolved by jq first,
# so key order never decides which marker is read.
btw_session_id() {
  BTW_ID=""
  local rest="${session_json#*\"session_id\"}"
  if [ "$rest" != "$session_json" ] && [ "${rest#*\"session_id\"}" = "$rest" ] &&
    [ "${session_json#*\\u}" = "$session_json" ] &&
    [[ "$rest" =~ ^[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BTW_ID="${BASH_REMATCH[1]}"
    return 0
  fi
  btw_top_id
  BTW_ID="$BTW_TOP"
}

# The payload's top-level session_id into BTW_TOP, as jq reads the JSON whole
# and checks it: empty unless it is a plain lowercase id.
btw_top_id() {
  BTW_TOP=""
  command -v jq >/dev/null 2>&1 || return 0
  BTW_TOP="$(printf '%s' "$session_json" |
    jq -r '.session_id | if type == "string" and test("\\A[a-z0-9_-]+\\z") then . else empty end' 2>/dev/null)" ||
    BTW_TOP=""
}

# Whether $1 is the payload's top-level session_id: a nested id, an escaped
# key or a value with a newline or NUL cannot pass for it. Asked only once the
# marker says a /btw is being answered.
btw_confirm_id() {
  btw_top_id
  [ -n "$BTW_TOP" ] && [ "$BTW_TOP" = "$1" ]
}

# WakaTime — today's coding time as recorded by WakaTime. The `wakatime-cli
# --today` call hits the network internally (~250ms), way too slow for
# every render. Cache for 5 minutes; on a miss, kick off a background
# refresh and serve the previous value (returns nothing the first time
# until the bg fetch lands). Skipped if wakatime-cli isn't installed.
seg_waka() {
  local wt="$HOME/.wakatime/wakatime-cli"
  [ -x "$wt" ] || return 0
  local cf="$CACHE_DIR/waka_today"
  local lock="$CACHE_DIR/waka_today.lock"
  local now mtime val=""
  now="$(date +%s)"
  mtime=0
  [ -f "$cf" ] && mtime="$(file_mtime "$cf")"
  if [ -f "$cf" ] && [ $((now - mtime)) -lt 300 ]; then
    read -r val <"$cf" 2>/dev/null || val=""
  else
    # Stale-lock recovery: if the lockdir is older than 60s the previous
    # bg fetch died (network hang, SIGKILL on logout, OOM) without
    # cleanup. Without this guard the dir persists forever, no further
    # refresh ever runs, and the segment silently freezes on the last
    # cached value — invisible failure mode. (Reviewer flagged this.)
    if [ -d "$lock" ]; then
      local lock_mtime
      lock_mtime="$(file_mtime "$lock")"
      [ $((now - lock_mtime)) -gt 60 ] && rmdir "$lock" 2>/dev/null
    fi
    # Background refresh — don't block the render. mkdir-based lock so
    # multiple concurrent statusline runs don't all spawn fetchers. The
    # subshell's EXIT trap guarantees the lock is removed even if the
    # fetch hangs and we get killed mid-call.
    # A fetch is tried at most once per 5 minutes, failed or not: the status
    # line reruns every 2 s, and a failing CLI (offline, no key) would
    # otherwise be started on every render. The stamp is read again once the
    # lock is held, so two renders at once start one fetch, not two.
    local tried="$CACHE_DIR/waka_today.tried"
    if mkdir "$lock" 2>/dev/null; then
      if [ -f "$tried" ] && [ $((now - $(file_mtime "$tried"))) -lt 300 ]; then
        rmdir "$lock" 2>/dev/null
      else
        : >"$tried" 2>/dev/null
        (
          trap 'rmdir "'"$lock"'" 2>/dev/null' EXIT
          "$wt" --today >"$cf.tmp" 2>/dev/null \
            && mv "$cf.tmp" "$cf" 2>/dev/null
        ) &
      fi
    fi
    # Serve stale value while the bg refresh runs (avoids flicker).
    [ -f "$cf" ] && read -r val <"$cf" 2>/dev/null
  fi
  [ -n "$val" ] || return 0
  # wakatime-cli prints variants: "2 hrs 9 mins" / "1 hr 5 mins" /
  # "47 mins" / "1 min" / "8 secs". Convert to total seconds, then
  # render via fmt_dhm so multi-day totals format as "Nd Hh Mm" / "Nh Mm"
  # consistently with seg_timer.
  local hrs=0 mins=0 secs=0 total
  case "$val" in *' hr'*) hrs="${val%% hr*}" ;; esac
  local rest="$val"
  case "$rest" in *' hr'*) rest="${rest#*hrs }"; rest="${rest#*hr }" ;; esac
  case "$rest" in *' min'*) mins="${rest%% min*}" ;; esac
  rest="$val"
  case "$rest" in *' min'*) rest="${rest#*mins }"; rest="${rest#*min }" ;; esac
  case "$rest" in *' sec'*) secs="${rest%% sec*}" ;; esac
  case "$hrs" in '' | *[!0-9]*) hrs=0 ;; esac
  case "$mins" in '' | *[!0-9]*) mins=0 ;; esac
  case "$secs" in '' | *[!0-9]*) secs=0 ;; esac
  total=$(( hrs * 3600 + mins * 60 + secs ))
  [ "$total" -ge 60 ] || return 0
  label "$C_YELLOW" "$ICON_WAKA" 'WakaTime'
  printf -v __SEG '%s%s%s%s' "$__LBL" "$C_FG" "$(fmt_dhm "$total")" "$C_RESET"
}

# --- 5. Render -------------------------------------------------------------
# Each seg_* writes its output to the global $__SEG via `printf -v` instead
# of stdout, so segments concatenate without a `$(...)` fork each. A literal
# `\n` token starts the next line; `path` is held back and placed at the
# right end of its line by finish_path_line. A line with no data takes no row.
out=""
line=""
__PATH_TEXT=""
add_line() {
  [ -n "$__LINE" ] || return 0
  if [ -n "$out" ]; then out="${out}"$'\n'"${__LINE}"; else out="$__LINE"; fi
}
for s in $SEGMENTS; do
  if [ "$s" = '\n' ]; then
    finish_path_line "$line"
    add_line
    line=""
    __PATH_TEXT=""
    continue
  fi
  if [ "$s" = "path" ]; then
    path_text
    continue
  fi
  __SEG=""
  "seg_$s" 2>/dev/null || true
  [ -n "$__SEG" ] || continue
  if [ -n "$line" ]; then
    line="${line}${C_RULE}${SEP}${C_RESET}${__SEG}"
  else
    line="$__SEG"
  fi
done
finish_path_line "$line"
add_line

# Padding rows are a no-break space: Claude Code trims a truly empty
# leading row, and U+00A0 renders invisibly.
i=0
while [ "$i" -lt "$PAD_TOP" ]; do
  printf '\r\302\240\n'
  i=$((i + 1))
done

# `\r` (carriage return) snaps the cursor to column 1 before painting,
# which matters because Claude Code's renderer sometimes pre-positions
# us a cell or two in. Note: Claude Code's statusline panel itself has
# a 1-cell border that no script-side ANSI can defeat — that border is
# UI chrome, not padding.
printf '\r%s%s%s' \
  "$(repeat ' ' "$PAD_LEFT")" \
  "$out" \
  "$(repeat ' ' "$PAD_RIGHT")"
