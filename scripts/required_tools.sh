#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
. "$SCRIPT_DIR/lib/bootstrap_common.sh"

REPO_ROOT=$(bootstrap_repo_root "$0") || bootstrap_fail "unable to determine repository root"
DOTFILES_DIR="$REPO_ROOT/dotfiles"
CONFIGS_DIR="$REPO_ROOT/configs"

ACTION="apply"
INSTALL_MODE="link"
PLATFORM_OVERRIDE=""
PACKAGE_MANAGER_OVERRIDE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --dry-run
  --apply
  --copy
  --platform darwin|linux
  --package-manager brew|apt|dnf|pacman
  --help
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        ACTION="dry-run"
        ;;
      --apply)
        ACTION="apply"
        ;;
      --copy)
        INSTALL_MODE="copy"
        ;;
      --platform)
        shift
        [ "$#" -gt 0 ] || bootstrap_fail "--platform requires a value"
        PLATFORM_OVERRIDE=$1
        ;;
      --package-manager)
        shift
        [ "$#" -gt 0 ] || bootstrap_fail "--package-manager requires a value"
        PACKAGE_MANAGER_OVERRIDE=$1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        bootstrap_fail "unknown argument: $1"
        ;;
    esac
    shift
  done
}

detect_platform() {
  if [ -n "$PLATFORM_OVERRIDE" ]; then
    printf '%s\n' "$PLATFORM_OVERRIDE"
  else
    bootstrap_os_name
  fi
}

detect_package_manager() {
  if [ -n "$PACKAGE_MANAGER_OVERRIDE" ]; then
    printf '%s\n' "$PACKAGE_MANAGER_OVERRIDE"
  elif [ "$(detect_platform)" = "darwin" ]; then
    printf '%s\n' "brew"
  else
    bootstrap_pkg_manager
  fi
}

display_source() {
  source_path=$1
  case "$source_path" in
    "$REPO_ROOT"/*) printf '%s\n' "${source_path#"$REPO_ROOT"/}" ;;
    *) printf '%s\n' "$source_path" ;;
  esac
}

emit_target() {
  source_path=$1
  target_path=$2

  bootstrap_log "map: $(display_source "$source_path") -> $target_path"
}

apply_target() {
  source_path=$1
  target_path=$2

  if [ ! -f "$source_path" ]; then
    bootstrap_fail "missing managed source: $source_path"
  fi

  if [ "$ACTION" = "dry-run" ]; then
    emit_target "$source_path" "$target_path"
    return 0
  fi

  bootstrap_install_target "$INSTALL_MODE" "$source_path" "$target_path"
  bootstrap_log "install: $(display_source "$source_path") -> $target_path"
}

ensure_dir() {
  dir_path=$1

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: mkdir -p $dir_path"
  else
    mkdir -p "$dir_path"
  fi
}

ensure_brew() {
  if bootstrap_has_command brew || bootstrap_activate_homebrew; then
    return 0
  fi

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: install Homebrew"
    return 0
  fi

  bootstrap_log "install: Homebrew"
  bootstrap_install_homebrew
  bootstrap_activate_homebrew || bootstrap_fail "Homebrew installation finished but brew is still not on PATH"
}

ensure_zsh() {
  platform=$1

  if bootstrap_has_command zsh; then
    bootstrap_log "skip: zsh already present"
    return 0
  fi

  case "$platform" in
    darwin)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: brew install zsh"
      else
        bootstrap_log "install: brew install zsh"
        brew install zsh
      fi
      ;;
    linux)
      bootstrap_warn "skip: zsh installation is expected from the Linux package manifest"
      ;;
    *)
      bootstrap_warn "skip: unsupported platform for zsh bootstrap: $platform"
      ;;
  esac
}

install_brew_packages() {
  brewfile="$CONFIGS_DIR/Brewfile"

  [ -f "$brewfile" ] || bootstrap_fail "missing Brewfile: $brewfile"
  ensure_brew
  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: brew bundle --file $brewfile"
  else
    bootstrap_log "install: brew bundle --file $brewfile"
    brew bundle --file "$brewfile"
  fi
}

install_linux_packages() {
  package_manager=$1
  manifest="$CONFIGS_DIR/packages/$package_manager.txt"

  [ -f "$manifest" ] || bootstrap_fail "missing package manifest: $manifest"
  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: $package_manager install packages from $manifest"
    bootstrap_warn "skip: GUI apps in the Brewfile are macOS-only"
    return 0
  fi

  set -- $(bootstrap_manifest_packages "$manifest")
  if [ "$#" -eq 0 ]; then
    bootstrap_warn "skip: no packages listed in $manifest"
    return 0
  fi

  case "$package_manager" in
    apt)
      command -v apt-get >/dev/null 2>&1 || bootstrap_fail "apt-get is required on apt-based Linux systems"
      sudo apt-get update
      sudo apt-get install -y "$@"
      ;;
    dnf)
      command -v dnf >/dev/null 2>&1 || bootstrap_fail "dnf is required on dnf-based Linux systems"
      sudo dnf install -y "$@"
      ;;
    pacman)
      command -v pacman >/dev/null 2>&1 || bootstrap_fail "pacman is required on pacman-based Linux systems"
      sudo pacman -S --noconfirm "$@"
      ;;
    *)
      bootstrap_fail "unsupported Linux package manager: $package_manager"
      ;;
  esac
}

ensure_antidote() {
  antidote_dir="$HOME/.antidote"
  antidote_file="$antidote_dir/antidote.zsh"

  if [ "$ACTION" = "dry-run" ]; then
    if [ -r "$antidote_file" ]; then
      bootstrap_log "skip: antidote already present at $antidote_dir"
    else
      bootstrap_log "dry-run: git clone https://github.com/mattmc3/antidote.git $antidote_dir"
    fi
    return 0
  fi

  if [ -r "$antidote_file" ]; then
    bootstrap_log "skip: antidote already present at $antidote_dir"
    return 0
  fi

  command -v git >/dev/null 2>&1 || bootstrap_fail "git is required to install antidote"
  bootstrap_log "install: git clone https://github.com/mattmc3/antidote.git $antidote_dir"
  git clone --depth 1 https://github.com/mattmc3/antidote.git "$antidote_dir"
}

apply_managed_files() {
  apply_target "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  apply_target "$DOTFILES_DIR/.zprofile" "$HOME/.zprofile"
  apply_target "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
  apply_target "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
  apply_target "$DOTFILES_DIR/.ssh/config" "$HOME/.ssh/config"
  apply_target "$DOTFILES_DIR/.zsh_plugins.txt" "$HOME/.zsh_plugins.txt"
}

main() {
  parse_args "$@"

  platform=$(detect_platform)
  package_manager=$(detect_package_manager)

  bootstrap_log "mode: $ACTION"
  bootstrap_log "install-mode: $INSTALL_MODE"
  bootstrap_log "platform: $platform"
  bootstrap_log "package-manager: $package_manager"

  ensure_dir "$HOME/.ssh"
  ensure_dir "$HOME/.ssh/control"
  ensure_dir "$HOME/.config"

  case "$platform:$package_manager" in
    darwin:brew)
      install_brew_packages
      ;;
    linux:apt|linux:dnf|linux:pacman)
      install_linux_packages "$package_manager"
      ;;
    *)
      bootstrap_fail "unsupported platform/package-manager pair: $platform/$package_manager"
      ;;
  esac

  ensure_zsh "$platform"
  ensure_antidote
  apply_managed_files
}

main "$@"
