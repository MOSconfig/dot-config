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

# cc/gg outside a multiplexer (macOS only): open in native tmux, else RMUX.
typeset -ga _mux_tmux_runtimes=(/opt/homebrew/bin/tmux /usr/local/bin/tmux)
typeset -ga _mux_rmux_runtimes=(/opt/homebrew/bin/rmux /usr/local/bin/rmux)

# Same choice as each store: the first runtime path that is a file must be executable.
function _mux_runtime_ok {
  local runtime
  for runtime in "$@"; do
    [[ -f "$runtime" ]] || continue
    [[ -x "$runtime" ]]
    return
  done
  return 1
}

# Print the backend cc/gg open in: tmux first, then RMUX.
function _mux_backend {
  emulate -L zsh
  if (( $+functions[_tmux_store] && $+functions[_tmux_store_path] )) && _tmux_store_path >/dev/null &&
      _mux_runtime_ok $_mux_tmux_runtimes; then
    print tmux
    return 0
  fi
  local runtime
  for runtime in $_mux_rmux_runtimes; do [[ -f "$runtime" ]] && break; runtime=; done
  if (( $+functions[_rmux_store] && $+functions[_rmux_store_path] )) && _rmux_store_path >/dev/null &&
      _mux_runtime_ok $_mux_rmux_runtimes &&
      [[ -f "${runtime:h}/rmux-daemon" && -x "${runtime:h}/rmux-daemon" ]]; then
    print rmux
    return 0
  fi
  return 1
}

function _mux_should_wrap {
  emulate -L zsh
  (( ! ${+TMUX} && ! ${+RMUX} )) && [[ -t 0 && -t 1 ]] || return 1
  [[ "$OSTYPE" == darwin* && "${CC_GG_INLINE:-}" != 1 ]] || return 1
  [[ "${commands[zsh]:-}" == /* ]] && _mux_backend >/dev/null
}

function _mux_open {
  emulate -L zsh
  local launcher=$1 title=$2 zsh=${commands[zsh]} backend
  shift 2
  if ! backend=$(_mux_backend); then
    print -u2 -- "$launcher: no tmux or RMUX available; set CC_GG_INLINE=1 to run without one."
    return 1
  fi
  local store=_${backend}_store
  # The window's zsh runs the launcher function in-pane, then stays as a shell.
  $store open "$PWD" "$title" "$zsh" -lic \
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
