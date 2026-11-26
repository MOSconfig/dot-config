unalias tt tl td th ts 2>/dev/null
unfunction tt tl td th ts 2>/dev/null

# Print the helper _tmux_store runs: the first executable regular file.
function _tmux_store_path {
  local helper
  for helper in "$HOME/.local/bin/tmux-store" "${commands[tmux-store]:-}"; do
    [[ -n "$helper" && -f "$helper" && -x "$helper" ]] && { print -r -- "$helper"; return 0; }
  done
  return 1
}

function _tmux_store {
  local helper
  if helper=$(_tmux_store_path); then
    "$helper" "$@"
  else
    print -u2 'Tmux helpers are not installed; run ./install.sh in dot-configs.'
    return 127
  fi
}

# cc/gg outside a multiplexer: open in a native tmux window (macOS only).
typeset -ga _mux_tmux_runtimes=(/opt/homebrew/bin/tmux /usr/local/bin/tmux)

function _mux_should_wrap {
  emulate -L zsh
  (( ! ${+TMUX} && ! ${+RMUX} )) && [[ -t 0 && -t 1 ]] || return 1
  [[ "$OSTYPE" == darwin* && "${CC_GG_INLINE:-}" != 1 ]] || return 1
  (( $+functions[_tmux_store] )) && _tmux_store_path >/dev/null || return 1
  # Same choice as store.py: the first runtime path that is a file must be executable.
  local runtime
  for runtime in $_mux_tmux_runtimes; do
    [[ -f "$runtime" ]] || continue
    [[ -x "$runtime" && "${commands[zsh]:-}" == /* ]]
    return
  done
  return 1
}

function _mux_open {
  emulate -L zsh
  local launcher=$1 title=$2 zsh=${commands[zsh]}
  shift 2
  # The window's zsh runs the launcher function in-pane, then stays as a shell.
  _tmux_store open "$PWD" "$title" "$zsh" -lic \
    'if (( $+functions[$1] )); then "$@"; else print -u2 -- "$1: launcher function not loaded"; fi; exec "$0" -il' \
    "$zsh" "$launcher" "$@"
}

function tt {
  emulate -L zsh
  if (( $# != 1 )); then
    print -u2 'usage: tt <session>'
    return 2
  fi
  _tmux_store attach "$1"
}

function tl {
  emulate -L zsh
  if (( $# )); then
    print -u2 'usage: tl'
    return 2
  fi
  _tmux_store list
}

function td {
  emulate -L zsh
  if (( $# != 1 )); then
    print -u2 'usage: td <session>'
    return 2
  fi
  _tmux_store delete "$1"
}

function th {
  emulate -L zsh
  if (( $# )); then
    print -u2 'usage: th'
    return 2
  fi
  _tmux_store help
}

function ts {
  emulate -L zsh
  if (( $# )); then
    print -u2 'usage: ts'
    return 2
  fi
  _tmux_store restart
}

if [[ -o interactive ]]; then
  unalias tr 2>/dev/null
  unfunction tr 2>/dev/null
  function tr {
    emulate -L zsh
    if (( $# == 1 )) && [[ "$1" != -* ]]; then
      tt "$1"
    else
      command tr "$@"
    fi
  }
fi
