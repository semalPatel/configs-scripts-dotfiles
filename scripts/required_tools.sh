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
SELECTED_PROVIDER=""
OPTIONAL_CODEX="no"
OPTIONAL_DOCKER="no"
OPTIONAL_PODMAN="no"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --dry-run
  --apply
  --copy
  --platform darwin|linux
  --package-manager brew|zerobrew|apt|dnf|pacman   # internal/testing override
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

is_interactive() {
  [ "${BOOTSTRAP_ASSUME_TTY:-0}" = "1" ] || { [ -t 0 ] && [ -t 1 ]; }
}

detect_platform() {
  if [ -n "$PLATFORM_OVERRIDE" ]; then
    printf '%s\n' "$PLATFORM_OVERRIDE"
  else
    bootstrap_os_name
  fi
}

prompt_provider() {
  platform=$1

  printf '%s\n' "Select package provider:" >&2
  printf '%s\n' "  1. Homebrew" >&2
  printf '%s\n' "  2. ZeroBrew" >&2
  if [ "$platform" = "linux" ]; then
    detected_native=$(bootstrap_pkg_manager)
    case "$detected_native" in
      apt|dnf|pacman)
        printf '%s\n' "  3. System package manager ($detected_native)" >&2
        ;;
    esac
  fi

  while :; do
    printf '%s' "Choice [1]: " >&2
    IFS= read -r answer || answer=""
    case "${answer:-1}" in
      1) printf '%s\n' "brew"; return 0 ;;
      2) printf '%s\n' "zerobrew"; return 0 ;;
      3)
        case "${detected_native:-}" in
          apt|dnf|pacman) printf '%s\n' "$detected_native"; return 0 ;;
        esac
        ;;
    esac
    bootstrap_warn "invalid selection: ${answer:-}"
  done
}

prompt_optional_codex() {
  while :; do
    printf '%s' "Install Codex CLI? [y/N]: " >&2
    IFS= read -r answer || answer=""
    case "${answer:-n}" in
      y|Y|yes|YES) printf '%s\n' "yes"; return 0 ;;
      n|N|no|NO|"") printf '%s\n' "no"; return 0 ;;
    esac
    bootstrap_warn "invalid selection: ${answer:-}"
  done
}

prompt_optional_install() {
  prompt_label=$1

  while :; do
    printf '%s' "Install $prompt_label? [y/N]: " >&2
    IFS= read -r answer || answer=""
    case "${answer:-n}" in
      y|Y|yes|YES) printf '%s\n' "yes"; return 0 ;;
      n|N|no|NO|"") printf '%s\n' "no"; return 0 ;;
    esac
    bootstrap_warn "invalid selection: ${answer:-}"
  done
}

detect_provider() {
  if [ -n "$PACKAGE_MANAGER_OVERRIDE" ]; then
    printf '%s\n' "$PACKAGE_MANAGER_OVERRIDE"
  elif is_interactive; then
    prompt_provider "$(detect_platform)"
  elif [ "$(detect_platform)" = "linux" ]; then
    detected_native=$(bootstrap_pkg_manager)
    case "$detected_native" in
      apt|dnf|pacman) printf '%s\n' "$detected_native" ;;
      *) printf '%s\n' "brew" ;;
    esac
  else
    printf '%s\n' "brew"
  fi
}

detect_optional_codex() {
  if is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
    prompt_optional_codex
  else
    printf '%s\n' "no"
  fi
}

detect_optional_docker() {
  if is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
    prompt_optional_install "Docker"
  else
    printf '%s\n' "no"
  fi
}

detect_optional_podman() {
  if is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
    prompt_optional_install "Podman"
  else
    printf '%s\n' "no"
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

ensure_zerobrew() {
  if bootstrap_has_command zb || bootstrap_activate_zerobrew; then
    return 0
  fi

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: install ZeroBrew"
    return 0
  fi

  bootstrap_log "install: ZeroBrew"
  bootstrap_install_zerobrew
  bootstrap_activate_zerobrew || bootstrap_fail "ZeroBrew installation finished but zb is still not on PATH"
}

provider_install_formula() {
  provider=$1
  shift

  case "$provider" in
    brew)
      ensure_brew
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: brew install $*"
      else
        bootstrap_log "install: brew install $*"
        brew install "$@"
      fi
      ;;
    zerobrew)
      ensure_zerobrew
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: zb install $*"
      else
        bootstrap_log "install: zb install $*"
        zb install "$@"
      fi
      ;;
    apt)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: apt install $*"
      else
        sudo apt-get install -y "$@"
      fi
      ;;
    dnf)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: dnf install $*"
      else
        sudo dnf install -y "$@"
      fi
      ;;
    pacman)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: pacman install $*"
      else
        sudo pacman -S --noconfirm "$@"
      fi
      ;;
    *)
      bootstrap_fail "unsupported provider for formula install: $provider"
      ;;
  esac
}

ensure_git() {
  provider=$1

  if bootstrap_has_command git; then
    bootstrap_log "skip: git already present"
    return 0
  fi

  provider_install_formula "$provider" git
}

ensure_zsh() {
  provider=$1

  if bootstrap_has_command zsh; then
    bootstrap_log "skip: zsh already present"
    return 0
  fi

  provider_install_formula "$provider" zsh
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

install_zerobrew_packages() {
  brewfile="$CONFIGS_DIR/Brewfile"

  [ -f "$brewfile" ] || bootstrap_fail "missing Brewfile: $brewfile"
  ensure_zerobrew
  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: zb bundle install -f $brewfile"
  else
    bootstrap_log "install: zb bundle install -f $brewfile"
    zb bundle install -f "$brewfile"
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
      for pkg in "$@"; do
        if sudo apt-get install -y "$pkg"; then
          :
        elif [ "$pkg" = "docker-compose-plugin" ]; then
          bootstrap_warn "apt package unavailable, retrying with fallback docker-compose: $pkg"
          sudo apt-get install -y docker-compose || bootstrap_fail "failed to install docker-compose fallback for $pkg"
        else
          bootstrap_fail "failed to install apt package: $pkg"
        fi
      done
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

setup_git_defaults() {
  platform=$1

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: git setup"
    return 0
  fi

  bootstrap_log "setup: git config init.defaultBranch main"
  git config --global init.defaultBranch main

  case "$platform" in
    darwin)
      if bootstrap_has_command git-credential-osxkeychain; then
        bootstrap_log "setup: git config credential.helper osxkeychain"
        git config --global credential.helper osxkeychain
      fi
      ;;
    linux)
      if bootstrap_has_command git-credential-manager; then
        bootstrap_log "setup: git config credential.helper manager"
        git config --global credential.helper manager
      elif bootstrap_has_command git-credential-manager-core; then
        bootstrap_log "setup: git config credential.helper manager-core"
        git config --global credential.helper manager-core
      fi
      ;;
  esac

  if [ -f "$HOME/.ssh/github_noreply.pub" ] && bootstrap_has_command ssh-keygen; then
    bootstrap_log "setup: git config gpg.format ssh"
    git config --global gpg.format ssh
    bootstrap_log "setup: git config user.signingkey $HOME/.ssh/github_noreply.pub"
    git config --global user.signingkey "$HOME/.ssh/github_noreply.pub"
    bootstrap_log "setup: git config gpg.ssh.program ssh-keygen"
    git config --global gpg.ssh.program ssh-keygen
  fi
}

install_optional_codex() {
  provider=$1

  [ "$OPTIONAL_CODEX" = "yes" ] || return 0

  case "$provider" in
    brew)
      ensure_brew
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: install Codex CLI"
      else
        bootstrap_log "install: brew install --cask codex"
        brew install --cask codex
      fi
      ;;
    zerobrew)
      provider_install_formula "$provider" node
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: install Codex CLI"
        bootstrap_log "dry-run: npm install -g @openai/codex"
      else
        bootstrap_log "install: npm install -g @openai/codex"
        npm install -g @openai/codex
      fi
      ;;
    apt)
      provider_install_formula "$provider" nodejs npm
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: install Codex CLI"
        bootstrap_log "dry-run: npm install -g @openai/codex"
      else
        bootstrap_log "install: npm install -g @openai/codex"
        npm install -g @openai/codex
      fi
      ;;
    dnf)
      provider_install_formula "$provider" nodejs npm
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: install Codex CLI"
        bootstrap_log "dry-run: npm install -g @openai/codex"
      else
        bootstrap_log "install: npm install -g @openai/codex"
        npm install -g @openai/codex
      fi
      ;;
    pacman)
      provider_install_formula "$provider" nodejs npm
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: install Codex CLI"
        bootstrap_log "dry-run: npm install -g @openai/codex"
      else
        bootstrap_log "install: npm install -g @openai/codex"
        npm install -g @openai/codex
      fi
      ;;
  esac
}

install_optional_docker() {
  provider=$1

  [ "$OPTIONAL_DOCKER" = "yes" ] || return 0

  case "$provider" in
    brew)
      provider_install_formula "$provider" docker docker-compose
      ;;
    zerobrew)
      provider_install_formula "$provider" docker docker-compose
      ;;
    apt)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: apt install docker.io"
        bootstrap_log "dry-run: apt install docker-compose-plugin"
      else
        sudo apt-get install -y docker.io || bootstrap_fail "failed to install apt package: docker.io"
        if sudo apt-get install -y docker-compose-plugin; then
          :
        else
          bootstrap_warn "apt package unavailable, retrying with fallback docker-compose: docker-compose-plugin"
          sudo apt-get install -y docker-compose || bootstrap_fail "failed to install docker-compose fallback for docker-compose-plugin"
        fi
      fi
      ;;
    dnf)
      provider_install_formula "$provider" docker docker-compose-plugin
      ;;
    pacman)
      provider_install_formula "$provider" docker docker-compose
      ;;
  esac
}

install_optional_podman() {
  provider=$1

  [ "$OPTIONAL_PODMAN" = "yes" ] || return 0

  case "$provider" in
    brew|zerobrew|apt|dnf|pacman)
      provider_install_formula "$provider" podman
      ;;
  esac
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
  provider=$(detect_provider)
  OPTIONAL_CODEX=$(detect_optional_codex)
  OPTIONAL_DOCKER=$(detect_optional_docker)
  OPTIONAL_PODMAN=$(detect_optional_podman)

  bootstrap_log "mode: $ACTION"
  bootstrap_log "install-mode: $INSTALL_MODE"
  bootstrap_log "platform: $platform"
  bootstrap_log "provider: $provider"
  bootstrap_log "optional-codex: $OPTIONAL_CODEX"
  bootstrap_log "optional-docker: $OPTIONAL_DOCKER"
  bootstrap_log "optional-podman: $OPTIONAL_PODMAN"

  ensure_dir "$HOME/.ssh"
  ensure_dir "$HOME/.ssh/control"
  ensure_dir "$HOME/.config"

  case "$platform:$provider" in
    darwin:brew)
      install_brew_packages
      ;;
    darwin:zerobrew|linux:zerobrew)
      install_zerobrew_packages
      ;;
    linux:brew)
      install_brew_packages
      ;;
    linux:apt|linux:dnf|linux:pacman)
      install_linux_packages "$provider"
      ;;
    *)
      bootstrap_fail "unsupported platform/package-manager pair: $platform/$provider"
      ;;
  esac

  ensure_git "$provider"
  ensure_zsh "$provider"
  ensure_antidote
  apply_managed_files
  setup_git_defaults "$platform"
  install_optional_codex "$provider"
  install_optional_docker "$provider"
  install_optional_podman "$provider"
}

main "$@"
