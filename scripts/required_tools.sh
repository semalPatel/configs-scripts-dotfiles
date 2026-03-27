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
ROOT_TARGET_HOME=""
ROOT_STAGE_REPO=""
ROOT_PHASE_PROVIDER=""
ROOT_PHASE_OPTIONAL_CODEX="no"
ROOT_PHASE_OPTIONAL_DOCKER="no"
ROOT_PHASE_OPTIONAL_PODMAN="no"

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

has_prompt_tty() {
  [ -r /dev/tty ] || return 1
  ( : </dev/tty ) >/dev/null 2>&1
}

is_interactive() {
  [ "${BOOTSTRAP_ASSUME_TTY:-0}" = "1" ] || has_prompt_tty
}

prompt_read() {
  if [ "${BOOTSTRAP_ASSUME_TTY:-0}" = "1" ]; then
    IFS= read -r answer || answer=""
  elif has_prompt_tty; then
    IFS= read -r answer </dev/tty || answer=""
  else
    IFS= read -r answer || answer=""
  fi

  printf '%s\n' "$answer"
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
  if bootstrap_is_root; then
    printf '%s\n' "  2. ZeroBrew (disabled for root)" >&2
  else
    printf '%s\n' "  2. ZeroBrew" >&2
  fi
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
    answer=$(prompt_read)
    case "${answer:-1}" in
      1) printf '%s\n' "brew"; return 0 ;;
      2)
        if bootstrap_is_root; then
          bootstrap_warn "ZeroBrew cannot be installed as root; choose Homebrew or the system package manager"
        else
          printf '%s\n' "zerobrew"; return 0
        fi
        ;;
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
    answer=$(prompt_read)
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
    answer=$(prompt_read)
    case "${answer:-n}" in
      y|Y|yes|YES) printf '%s\n' "yes"; return 0 ;;
      n|N|no|NO|"") printf '%s\n' "no"; return 0 ;;
    esac
    bootstrap_warn "invalid selection: ${answer:-}"
  done
}

prompt_confirmation() {
  prompt_label=$1
  default_answer=${2:-y}

  while :; do
    if [ "$default_answer" = "y" ]; then
      printf '%s' "$prompt_label [Y/n]: " >&2
    else
      printf '%s' "$prompt_label [y/N]: " >&2
    fi

    answer=$(prompt_read)
    case "${answer:-$default_answer}" in
      y|Y|yes|YES) printf '%s\n' "yes"; return 0 ;;
      n|N|no|NO) printf '%s\n' "no"; return 0 ;;
    esac
    bootstrap_warn "invalid selection: ${answer:-}"
  done
}

prompt_username() {
  while :; do
    printf '%s' "Username [dev]: " >&2
    answer=$(prompt_read)
    username=${answer:-dev}
    if bootstrap_validate_username "$username"; then
      printf '%s\n' "$username"
      return 0
    fi
    bootstrap_warn "invalid username: $username"
  done
}

detect_provider() {
  if [ -n "${BOOTSTRAP_SELECTED_PROVIDER:-}" ]; then
    printf '%s\n' "$BOOTSTRAP_SELECTED_PROVIDER"
  elif [ -n "$PACKAGE_MANAGER_OVERRIDE" ]; then
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

validate_provider() {
  provider=$1

  case "$provider" in
    zerobrew)
      if bootstrap_is_root; then
        bootstrap_fail "ZeroBrew cannot be installed as root; rerun as a non-root user or choose Homebrew/system package manager"
      fi
      ;;
  esac
}

linux_admin_group() {
  if command -v getent >/dev/null 2>&1; then
    if getent group sudo >/dev/null 2>&1; then
      printf '%s\n' "sudo"
      return 0
    fi
    if getent group wheel >/dev/null 2>&1; then
      printf '%s\n' "wheel"
      return 0
    fi
  fi

  if grep -q '^sudo:' /etc/group 2>/dev/null; then
    printf '%s\n' "sudo"
    return 0
  fi
  if grep -q '^wheel:' /etc/group 2>/dev/null; then
    printf '%s\n' "wheel"
    return 0
  fi

  bootstrap_fail "unable to determine Linux admin group (expected sudo or wheel)"
}

ensure_linux_root_dependencies() {
  package_manager=$(bootstrap_pkg_manager)

  case "$package_manager" in
    apt)
      if ! command -v sudo >/dev/null 2>&1; then
        if [ "$ACTION" = "dry-run" ]; then
          bootstrap_log "dry-run: apt install sudo"
        else
          run_privileged_command apt-get update
          run_privileged_command apt-get install -y sudo
        fi
      fi
      ;;
    dnf)
      if ! command -v sudo >/dev/null 2>&1; then
        if [ "$ACTION" = "dry-run" ]; then
          bootstrap_log "dry-run: dnf install sudo"
        else
          run_privileged_command dnf install -y sudo
        fi
      fi
      ;;
    pacman)
      if ! command -v sudo >/dev/null 2>&1; then
        if [ "$ACTION" = "dry-run" ]; then
          bootstrap_log "dry-run: pacman install sudo"
        else
          run_privileged_command pacman -S --noconfirm sudo
        fi
      fi
      ;;
    *)
      bootstrap_fail "root onboarding requires apt, dnf, or pacman on Linux"
      ;;
  esac
}

rerun_args() {
  args="--$ACTION"
  if [ "$INSTALL_MODE" = "copy" ]; then
    args="$args --copy"
  fi
  if [ -n "$PLATFORM_OVERRIDE" ]; then
    args="$args --platform $PLATFORM_OVERRIDE"
  fi
  if [ -n "$PACKAGE_MANAGER_OVERRIDE" ]; then
    args="$args --package-manager $PACKAGE_MANAGER_OVERRIDE"
  fi

  printf '%s\n' "$args"
}

use_root_package_phase() {
  [ "${BOOTSTRAP_SKIP_PACKAGE_SETUP:-0}" = "1" ]
}

run_privileged_command() {
  if bootstrap_is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

rerun_env_prefix() {
  env_prefix="BOOTSTRAP_SELECTED_PROVIDER=$ROOT_PHASE_PROVIDER BOOTSTRAP_OPTIONAL_CODEX=$ROOT_PHASE_OPTIONAL_CODEX BOOTSTRAP_OPTIONAL_DOCKER=$ROOT_PHASE_OPTIONAL_DOCKER BOOTSTRAP_OPTIONAL_PODMAN=$ROOT_PHASE_OPTIONAL_PODMAN"
  if use_root_package_phase; then
    env_prefix="$env_prefix BOOTSTRAP_SKIP_PACKAGE_SETUP=1"
  fi
  printf '%s\n' "$env_prefix"
}

root_stage_repo_for_user() {
  target_user=$1
  target_home=$2

  stage_root="$target_home/.local/share/dotfiles-bootstrap"
  stage_repo="$stage_root/repo"

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: stage bootstrap repo at $stage_repo"
    ROOT_STAGE_REPO=$stage_repo
    return 0
  fi

  target_group=$(id -gn "$target_user")
  mkdir -p "$stage_root"
  rm -rf "$stage_repo"
  cp -R "$REPO_ROOT" "$stage_repo"
  chown -R "$target_user:$target_group" "$stage_root"
  ROOT_STAGE_REPO=$stage_repo
}

ensure_linux_user_account() {
  target_user=$1

  target_shell=$(bootstrap_pick_login_shell)
  admin_group=$(linux_admin_group)

  if bootstrap_user_exists "$target_user"; then
    target_home=$(bootstrap_user_home "$target_user")
    [ -n "$target_home" ] || bootstrap_fail "unable to determine home directory for existing user: $target_user"
    if [ "$ACTION" = "dry-run" ]; then
      bootstrap_log "dry-run: user exists, reuse $target_user"
      bootstrap_log "dry-run: ensure $target_user is in admin group $admin_group"
    else
      usermod -aG "$admin_group" "$target_user"
    fi
    ROOT_TARGET_HOME=$target_home
    return 0
  fi

  target_home="/home/$target_user"
  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: useradd -m -s $target_shell $target_user"
    bootstrap_log "dry-run: usermod -aG $admin_group $target_user"
  else
    useradd -m -s "$target_shell" "$target_user"
    usermod -aG "$admin_group" "$target_user"
    bootstrap_log "setup: set a password for $target_user"
    passwd "$target_user"
  fi

  ROOT_TARGET_HOME=$target_home
}

rerun_bootstrap_as_user() {
  target_user=$1
  stage_repo=$2

  rerun_flags=$(rerun_args)
  rerun_script="$stage_repo/scripts/required_tools.sh"
  rerun_env=$(rerun_env_prefix)
  rerun_cmd="$rerun_env /bin/sh '$rerun_script' $rerun_flags"

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: su - $target_user -c $rerun_cmd"
    return 0
  fi

  bootstrap_log "handoff: rerunning bootstrap as $target_user"
  su - "$target_user" -c "$rerun_cmd"
}

open_login_shell_as_user() {
  target_user=$1
  login_shell=$(bootstrap_pick_login_shell)

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: exec su - $target_user -s $login_shell"
    return 0
  fi

  if bootstrap_has_command zsh; then
    usermod -s "$login_shell" "$target_user"
  fi
  bootstrap_log "handoff: opening login shell as $target_user with $login_shell"
  exec su - "$target_user" -s "$login_shell"
}

handle_root_bootstrap() {
  platform=$1

  case "$platform" in
    darwin)
      bootstrap_fail "run this bootstrap from your normal macOS user account, not as root"
      ;;
    linux)
      ;;
    *)
      bootstrap_fail "root onboarding is only supported on Linux"
      ;;
  esac

  if ! is_interactive; then
    bootstrap_fail "this bootstrap must run as a non-root user; rerun interactively as root to create one first"
  fi

  bootstrap_log "info: bootstrap is running as root and will set up a real userspace account first"
  if [ "$(prompt_confirmation "Create or reuse a non-root bootstrap user now?" y)" != "yes" ]; then
    bootstrap_fail "root bootstrap aborted; create a non-root user and rerun the script from that account"
  fi

  target_user=$(prompt_username)
  ROOT_PHASE_PROVIDER=$(detect_provider)
  validate_provider "$ROOT_PHASE_PROVIDER"
  ROOT_PHASE_OPTIONAL_CODEX=$(detect_optional_codex)
  ROOT_PHASE_OPTIONAL_DOCKER=$(detect_optional_docker)
  ROOT_PHASE_OPTIONAL_PODMAN=$(detect_optional_podman)
  ensure_linux_root_dependencies
  case "$ROOT_PHASE_PROVIDER" in
    apt|dnf|pacman)
      provider=$ROOT_PHASE_PROVIDER
      OPTIONAL_CODEX=$ROOT_PHASE_OPTIONAL_CODEX
      OPTIONAL_DOCKER=$ROOT_PHASE_OPTIONAL_DOCKER
      OPTIONAL_PODMAN=$ROOT_PHASE_OPTIONAL_PODMAN
      install_linux_packages "$provider"
      ensure_git "$provider"
      ensure_zsh "$provider"
      install_optional_codex "$provider"
      install_optional_docker "$provider"
      install_optional_podman "$provider"
      BOOTSTRAP_SKIP_PACKAGE_SETUP=1
      export BOOTSTRAP_SKIP_PACKAGE_SETUP
      ;;
  esac
  ensure_linux_user_account "$target_user"
  root_stage_repo_for_user "$target_user" "$ROOT_TARGET_HOME"
  rerun_bootstrap_as_user "$target_user" "$ROOT_STAGE_REPO"
  bootstrap_log "bootstrap complete"
  open_login_shell_as_user "$target_user"
  exit 0
}

detect_optional_codex() {
  if [ -n "${BOOTSTRAP_OPTIONAL_CODEX:-}" ]; then
    printf '%s\n' "$BOOTSTRAP_OPTIONAL_CODEX"
  elif is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
    prompt_optional_codex
  else
    printf '%s\n' "no"
  fi
}

detect_optional_docker() {
  if [ -n "${BOOTSTRAP_OPTIONAL_DOCKER:-}" ]; then
    printf '%s\n' "$BOOTSTRAP_OPTIONAL_DOCKER"
  elif is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
    prompt_optional_install "Docker"
  else
    printf '%s\n' "no"
  fi
}

detect_optional_podman() {
  if [ -n "${BOOTSTRAP_OPTIONAL_PODMAN:-}" ]; then
    printf '%s\n' "$BOOTSTRAP_OPTIONAL_PODMAN"
  elif is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
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
        run_privileged_command apt-get install -y "$@"
      fi
      ;;
    dnf)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: dnf install $*"
      else
        run_privileged_command dnf install -y "$@"
      fi
      ;;
    pacman)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: pacman install $*"
      else
        run_privileged_command pacman -S --noconfirm "$@"
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
      run_privileged_command apt-get update
      for pkg in "$@"; do
        if run_privileged_command apt-get install -y "$pkg"; then
          :
        elif [ "$pkg" = "docker-compose-plugin" ]; then
          bootstrap_warn "apt package unavailable, retrying with fallback docker-compose: $pkg"
          run_privileged_command apt-get install -y docker-compose || bootstrap_fail "failed to install docker-compose fallback for $pkg"
        else
          bootstrap_fail "failed to install apt package: $pkg"
        fi
      done
      ;;
    dnf)
      command -v dnf >/dev/null 2>&1 || bootstrap_fail "dnf is required on dnf-based Linux systems"
      run_privileged_command dnf install -y "$@"
      ;;
    pacman)
      command -v pacman >/dev/null 2>&1 || bootstrap_fail "pacman is required on pacman-based Linux systems"
      run_privileged_command pacman -S --noconfirm "$@"
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
  if bootstrap_has_command codex; then
    bootstrap_log "skip: codex already present"
    return 0
  fi

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
  if bootstrap_has_command docker; then
    bootstrap_log "skip: docker already present"
    return 0
  fi

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
        run_privileged_command apt-get install -y docker.io || bootstrap_fail "failed to install apt package: docker.io"
        if run_privileged_command apt-get install -y docker-compose-plugin; then
          :
        else
          bootstrap_warn "apt package unavailable, retrying with fallback docker-compose: docker-compose-plugin"
          run_privileged_command apt-get install -y docker-compose || bootstrap_fail "failed to install docker-compose fallback for docker-compose-plugin"
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
  if bootstrap_has_command podman; then
    bootstrap_log "skip: podman already present"
    return 0
  fi

  case "$provider" in
    brew|zerobrew|apt|dnf|pacman)
      provider_install_formula "$provider" podman
      ;;
  esac
}

print_completion() {
  bootstrap_log "bootstrap complete"
  bootstrap_log "summary: provider=$provider codex=$OPTIONAL_CODEX docker=$OPTIONAL_DOCKER podman=$OPTIONAL_PODMAN"
  bootstrap_log "next-step: start a new login shell with 'exec zsh -l' to load updated PATH and zsh config"
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
  if bootstrap_is_root; then
    handle_root_bootstrap "$platform"
  fi
  provider=$(detect_provider)
  validate_provider "$provider"
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

  if use_root_package_phase; then
    bootstrap_log "skip: system package setup already handled by root bootstrap"
  else
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
  fi
  ensure_antidote
  apply_managed_files
  setup_git_defaults "$platform"
  if use_root_package_phase; then
    bootstrap_log "skip: optional package installs already handled by root bootstrap"
  else
    install_optional_codex "$provider"
    install_optional_docker "$provider"
    install_optional_podman "$provider"
  fi
  print_completion
}

main "$@"
