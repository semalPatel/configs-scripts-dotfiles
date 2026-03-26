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
