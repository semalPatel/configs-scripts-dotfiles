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

bootstrap_os_name() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) printf '%s\n' "darwin" ;;
    Linux) printf '%s\n' "linux" ;;
    *) printf '%s\n' "unknown" ;;
  esac
}

bootstrap_pkg_manager() {
  if command -v brew >/dev/null 2>&1; then
    printf '%s\n' "brew"
  elif command -v apt-get >/dev/null 2>&1; then
    printf '%s\n' "apt"
  elif command -v dnf >/dev/null 2>&1; then
    printf '%s\n' "dnf"
  elif command -v pacman >/dev/null 2>&1; then
    printf '%s\n' "pacman"
  else
    printf '%s\n' "unknown"
  fi
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
