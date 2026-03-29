# Keep non-interactive shells portable and XDG-friendly.

typeset -U path PATH
path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  $path
)
export PATH
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Ghostty sets TERM=xterm-ghostty. Fresh remote Linux boxes often lack that
# terminfo entry, which breaks zsh line editing and key handling over SSH.
if [ -n "${SSH_CONNECTION:-}" ] && [ "${TERM:-}" = "xterm-ghostty" ]; then
  if ! command -v infocmp >/dev/null 2>&1 || ! infocmp xterm-ghostty >/dev/null 2>&1; then
    export TERM="xterm-256color"
  fi
fi
