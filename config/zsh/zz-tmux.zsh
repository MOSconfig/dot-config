unalias tt tl td th ts 2>/dev/null
unfunction tt tl td th ts 2>/dev/null

function _tmux_store {
  if [[ -x "$HOME/.local/bin/tmux-store" ]]; then
    "$HOME/.local/bin/tmux-store" "$@"
  elif (( $+commands[tmux-store] )); then
    command tmux-store "$@"
  else
    print -u2 'Tmux helpers are not installed; run ./install.sh in dot-configs.'
    return 127
  fi
}

# cc/gg outside a multiplexer: open in a native tmux window (macOS only).
typeset -ga _mux_tmux_runtimes=(/opt/homebrew/bin/tmux /usr/local/bin/tmux)

function _mux_should_wrap {
  emulate -L zsh
  [[ -z "${TMUX:-}" && -z "${RMUX:-}" && -t 0 && -t 1 ]] || return 1
  [[ "$OSTYPE" == darwin* && "${CC_GG_INLINE:-}" != 1 ]] || return 1
  (( $+functions[_tmux_store] )) || return 1
  [[ -x "$HOME/.local/bin/tmux-store" ]] || (( $+commands[tmux-store] )) || return 1
  local runtime found=0
  for runtime in $_mux_tmux_runtimes; do [[ -x "$runtime" ]] && found=1; done
  (( found )) && [[ "${commands[zsh]:-}" == /* ]]
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
