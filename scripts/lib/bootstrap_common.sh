#!/usr/bin/env sh

# Shared helpers for portable bootstrap scripts.

bootstrap_log() {
  printf '%s\n' "$*"
}

bootstrap_warn() {
  printf '%s\n' "warn: $*" >&2
}

bootstrap_fail() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

bootstrap_is_root() {
  [ "$(id -u 2>/dev/null || printf '1')" = "0" ]
}

bootstrap_validate_username() {
  username=$1

  case "$username" in
    ""|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]*)
      return 1
      ;;
    -*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

bootstrap_user_exists() {
  username=$1
  id "$username" >/dev/null 2>&1
}

bootstrap_user_home() {
  username=$1

  if command -v getent >/dev/null 2>&1; then
    getent passwd "$username" | awk -F: 'NR==1 { print $6 }'
    return 0
  fi

  awk -F: -v user="$username" '$1 == user { print $6; exit }' /etc/passwd
}

bootstrap_pick_login_shell() {
  if command -v zsh >/dev/null 2>&1; then
    command -v zsh
  elif command -v bash >/dev/null 2>&1; then
    command -v bash
  else
    printf '%s\n' "/bin/sh"
  fi
}

bootstrap_os_name() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) printf '%s\n' "darwin" ;;
    Linux) printf '%s\n' "linux" ;;
    *) printf '%s\n' "unknown" ;;
  esac
}

bootstrap_pkg_manager() {
  case "$(bootstrap_os_name)" in
    darwin)
      if command -v brew >/dev/null 2>&1; then
        printf '%s\n' "brew"
      else
        printf '%s\n' "unknown"
      fi
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        printf '%s\n' "apt"
      elif command -v dnf >/dev/null 2>&1; then
        printf '%s\n' "dnf"
      elif command -v pacman >/dev/null 2>&1; then
        printf '%s\n' "pacman"
      else
        printf '%s\n' "unknown"
      fi
      ;;
    *)
      printf '%s\n' "unknown"
      ;;
  esac
}

bootstrap_install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v bash >/dev/null 2>&1; then
    bootstrap_fail "bash is required to install Homebrew"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    bootstrap_fail "curl is required to install Homebrew"
  fi

  NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

bootstrap_install_zerobrew() {
  if bootstrap_has_command zb >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    bootstrap_fail "curl is required to install ZeroBrew"
  fi

  curl -fsSL https://zerobrew.rs/install | bash -s -- --no-modify-path
}

bootstrap_activate_homebrew() {
  if [ -n "${BOOTSTRAP_MISSING_COMMANDS:-}" ]; then
    case " ${BOOTSTRAP_MISSING_COMMANDS} " in
      *" brew "*) return 1 ;;
    esac
  fi

  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  for brew_prefix in /opt/homebrew/bin /usr/local/bin /home/linuxbrew/.linuxbrew/bin; do
    if [ -x "$brew_prefix/brew" ]; then
      PATH="$brew_prefix:$PATH"
      export PATH
      return 0
    fi
  done

  return 1
}

bootstrap_activate_zerobrew() {
  if [ -n "${BOOTSTRAP_MISSING_COMMANDS:-}" ]; then
    case " ${BOOTSTRAP_MISSING_COMMANDS} " in
      *" zb "*) return 1 ;;
    esac
  fi

  if command -v zb >/dev/null 2>&1; then
    return 0
  fi

  zerobrew_bin="${ZEROBREW_BIN:-$HOME/.local/bin}"
  if [ -x "$zerobrew_bin/zb" ]; then
    PATH="$zerobrew_bin:$PATH"
    export PATH
    return 0
  fi

  return 1
}

bootstrap_has_command() {
  if [ -n "${BOOTSTRAP_MISSING_COMMANDS:-}" ]; then
    case " ${BOOTSTRAP_MISSING_COMMANDS} " in
      *" $1 "*) return 1 ;;
    esac
  fi
  command -v "$1" >/dev/null 2>&1
}

bootstrap_repo_root() {
  script_path=${1:-$0}
  script_dir=$(CDPATH= cd -- "$(dirname -- "$script_path")" && pwd -P) || return 1
  CDPATH= cd -- "$script_dir/.." && pwd -P
}

bootstrap_mkdir_parent() {
  target=$1
  mkdir -p "$(dirname -- "$target")"
}

bootstrap_backup_path() {
  target=$1
  stamp=$(date +%Y%m%d%H%M%S)
  candidate="${target}.bak.${stamp}"
  suffix=0
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    suffix=$((suffix + 1))
    candidate="${target}.bak.${stamp}.${suffix}"
  done
  printf '%s\n' "$candidate"
}

bootstrap_link_target() {
  source_path=$1
  target_path=$2

  bootstrap_mkdir_parent "$target_path"
  if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
    return 0
  fi
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    backup_path=$(bootstrap_backup_path "$target_path")
    mv "$target_path" "$backup_path"
  fi
  ln -s "$source_path" "$target_path"
}

bootstrap_copy_target() {
  source_path=$1
  target_path=$2

  bootstrap_mkdir_parent "$target_path"
  if [ -f "$target_path" ] && [ ! -L "$target_path" ] && cmp -s "$source_path" "$target_path"; then
    return 0
  fi
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    backup_path=$(bootstrap_backup_path "$target_path")
    mv "$target_path" "$backup_path"
  fi
  cp "$source_path" "$target_path"
}

bootstrap_install_target() {
  mode=$1
  source_path=$2
  target_path=$3

  case "$mode" in
    link)
      bootstrap_link_target "$source_path" "$target_path"
      ;;
    copy)
      bootstrap_copy_target "$source_path" "$target_path"
      ;;
    *)
      bootstrap_fail "unsupported install mode: $mode"
      ;;
  esac
}

bootstrap_manifest_packages() {
  manifest_path=$1
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$manifest_path"
}
