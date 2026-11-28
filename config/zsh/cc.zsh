# cc [words]
#
# On macOS outside tmux/RMUX with a terminal, opens Claude Code in native tmux,
# else RMUX (see _mux_backend in zz-tmux.zsh); CC_GG_INLINE=1 opts out. The
# words name the session (none: the current folder's name). When that session
# already runs, cc attaches to it as it is and starts no second Claude Code.
#
# Sibling of `gg` (config/zsh/gg.zsh) but launches Anthropic's
# Claude Code CLI instead of GitHub Copilot CLI. Sets the active terminal
# tab + window title to [title] via OSC 1/2 and tells RMUX directly so the
# title sticks when nested, then runs `claude` in
# the current shell. If title is omitted, use the current directory path.
#
# Model + effort are pinned globally in ~/.claude/settings.json and injected
# here because Claude Code may rewrite settings.json at runtime.
# Permission mode CANNOT be pinned via settings.json — the binary explicitly rejects
# defaultMode="bypassPermissions" with "bypassPermissions mode is
# disabled by settings". So we pass --permission-mode at the command
# line on every invocation, which the binary does honor.
#
# See gg.zsh for the rationale on each title-update path; this is the
# same recipe with a different launcher.

unalias cc 2>/dev/null
unfunction cc 2>/dev/null
function cc {
  emulate -L zsh
  # Prepend a Nerd Font glyph so the tab is visually distinct as a Claude
  # Code session. mdi-creation (U+F0674) renders as sparkles in any Nerd
  # Font — fits the "AI agent" vibe and reads cleanly even without color.
  # Wrap in $'...' (zsh ANSI-C quoting) so the literal codepoint sits in
  # the title bytes.
  local icon=$''
  # Words join with one space whatever the caller's IFS is, as _mux_open joins the session name.
  local IFS=' '
  local title_text="$*"
  [[ -n "$title_text" ]] || title_text=$PWD
  local title="$icon $title_text"
  if (( $+functions[_mux_should_wrap] )) && _mux_should_wrap; then
    _mux_open cc "$title" "$@"
    return
  fi
  DISABLE_AUTO_TITLE=true
  # -r: send the title literally; no prompt (%) or backslash expansion.
  print -rn -- $'\e]2;'"$title"$'\a'
  print -rn -- $'\e]1;'"$title"$'\a'
  if [[ -n "$RMUX" ]] && (( $+commands[rmux] )); then
    # RMUX reads a trailing ';' as a command separator; escape it.
    local rmux_title=$title
    [[ $rmux_title == *';' ]] && rmux_title="${rmux_title%;}\\;"
    command rmux rename-window -- "$rmux_title" 2>/dev/null
  elif [[ -z "${RMUX:-}" && -n "${TMUX:-}" ]] && (( $+functions[_tmux_store] )); then
    _tmux_store rename "$title" 2>/dev/null
  fi
  command claude --permission-mode bypassPermissions --model 'claude-opus-5-5[1m]' --effort xhigh
  unset DISABLE_AUTO_TITLE
}
