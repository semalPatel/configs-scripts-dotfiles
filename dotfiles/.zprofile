typeset -U path PATH
path=(
  "$HOME/.cargo/bin"
  "$HOME/.antigravity/antigravity/bin"
  /opt/homebrew/bin
  /usr/local/bin
  /usr/local/sbin
  /usr/sbin
  /usr/bin
  /sbin
  /bin
  $path
)
export PATH

if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi
