typeset -U path PATH
path=(
  "$HOME/.local/bin"
  "${XDG_DATA_HOME:-$HOME/.local/share}/zerobrew/prefix/bin"
  "${XDG_DATA_HOME:-$HOME/.local/share}/zerobrew/prefix/sbin"
  /opt/zerobrew/bin
  /opt/zerobrew/sbin
  "$HOME/.cargo/bin"
  "$HOME/.antigravity/antigravity/bin"
  /usr/sbin
  /usr/bin
  /sbin
  /bin
  $path
)

case "$(uname -s 2>/dev/null)" in
  Darwin)
    path=(
      /opt/homebrew/bin
      /usr/local/bin
      /usr/local/sbin
      $path
    )
    ;;
  Linux)
    path=(
      /home/linuxbrew/.linuxbrew/bin
      /home/linuxbrew/.linuxbrew/sbin
      /usr/local/bin
      /usr/local/sbin
      $path
    )
    ;;
esac

export PATH

if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi
