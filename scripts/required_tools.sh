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
OPTIONAL_GIT_CONFIG="no"
SELECTED_AGENT="none"
AGENT_INSTALL_METHOD="none"
OPTIONAL_DOCKER="no"
OPTIONAL_PODMAN="no"
ROOT_TARGET_HOME=""
ROOT_STAGE_REPO=""

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
  native_choice=""
  if ! bootstrap_is_root; then
    printf '%s\n' "  2. ZeroBrew" >&2
    native_choice="3"
  else
    native_choice="2"
  fi
  if [ "$platform" = "linux" ]; then
    detected_native=$(bootstrap_pkg_manager)
    case "$detected_native" in
      apt|dnf|pacman)
        printf '%s\n' "  $native_choice. System package manager ($detected_native)" >&2
        ;;
    esac
  fi

  while :; do
    printf '%s' "Choice [1]: " >&2
    answer=$(prompt_read)
    case "${answer:-1}" in
      1) printf '%s\n' "brew"; return 0 ;;
      2)
        if ! bootstrap_is_root; then
          printf '%s\n' "zerobrew"; return 0
        elif [ "${detected_native:-}" = "apt" ] || [ "${detected_native:-}" = "dnf" ] || [ "${detected_native:-}" = "pacman" ]; then
          printf '%s\n' "$detected_native"; return 0
        fi
        ;;
      3)
        if ! bootstrap_is_root; then
          case "${detected_native:-}" in
            apt|dnf|pacman) printf '%s\n' "$detected_native"; return 0 ;;
          esac
        fi
        ;;
    esac
    bootstrap_warn "invalid selection: ${answer:-}"
  done
}

prompt_userspace_provider() {
  platform=$1

  printf '%s\n' "Select userspace package provider:" >&2
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
    answer=$(prompt_read)
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

prompt_agent_choice() {
  printf '%s\n' "Select AI agent to install:" >&2
  printf '%s\n' "  1. None" >&2
  printf '%s\n' "  2. Codex" >&2
  printf '%s\n' "  3. Claude Code" >&2
  printf '%s\n' "  4. OpenCode" >&2
  printf '%s\n' "  5. Mistral Vibe" >&2

  while :; do
    printf '%s' "Choice [1]: " >&2
    answer=$(prompt_read)
    case "${answer:-1}" in
      1) printf '%s\n' "none"; return 0 ;;
      2) printf '%s\n' "codex"; return 0 ;;
      3) printf '%s\n' "claude-code"; return 0 ;;
      4) printf '%s\n' "opencode"; return 0 ;;
      5) printf '%s\n' "mistral-vibe"; return 0 ;;
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

run_privileged_command() {
  if bootstrap_is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

codex_release_archive() {
  platform=$(detect_platform)
  arch=$(uname -m 2>/dev/null || printf '%s\n' "unknown")

  case "$platform:$arch" in
    linux:x86_64|linux:amd64) printf '%s\n' "codex-x86_64-unknown-linux-gnu.tar.gz" ;;
    linux:aarch64|linux:arm64) printf '%s\n' "codex-aarch64-unknown-linux-gnu.tar.gz" ;;
    darwin:x86_64) printf '%s\n' "codex-x86_64-apple-darwin.tar.gz" ;;
    darwin:arm64|darwin:aarch64) printf '%s\n' "codex-aarch64-apple-darwin.tar.gz" ;;
    *)
      bootstrap_fail "unsupported platform/architecture for Codex binary: $platform/$arch"
      ;;
  esac
}

install_codex_release_binary() {
  target_dir="$HOME/.local/bin"
  target_bin="$target_dir/codex"
  archive_name=$(codex_release_archive)
  archive_url="https://github.com/openai/codex/releases/latest/download/$archive_name"
  archive_tmp=$(mktemp "${TMPDIR:-/tmp}/codex.XXXXXX.tar.gz")
  extract_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex.XXXXXX")

  cleanup_codex_binary_install() {
    rm -f "$archive_tmp"
    rm -rf "$extract_dir"
  }

  trap cleanup_codex_binary_install EXIT INT TERM

  mkdir -p "$target_dir"
  bootstrap_log "install: download Codex binary $archive_name"
  curl -fsSL "$archive_url" -o "$archive_tmp"
  tar -xzf "$archive_tmp" -C "$extract_dir"

  extracted_bin=""
  for candidate in "$extract_dir"/codex* "$extract_dir"/bin/codex*; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
      extracted_bin=$candidate
      break
    fi
  done

  [ -n "$extracted_bin" ] || bootstrap_fail "downloaded Codex archive did not contain a codex binary"
  install -m 755 "$extracted_bin" "$target_bin"

  trap - EXIT INT TERM
  cleanup_codex_binary_install
}

rerun_env_prefix() {
  env_prefix=""
  if is_interactive; then
    env_prefix="BOOTSTRAP_ASSUME_TTY=1"
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
      bootstrap_log "dry-run: chown -R $target_user:$target_user $target_home"
    else
      bootstrap_log "reuse: existing user $target_user"
      bootstrap_log "reuse: password unchanged for $target_user"
      usermod -aG "$admin_group" "$target_user"
      mkdir -p "$target_home"
      chown -R "$target_user:$target_user" "$target_home"
      chmod 755 "$target_home"
    fi
    ROOT_TARGET_HOME=$target_home
    return 0
  fi

  target_home="/home/$target_user"
  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: useradd -m -s $target_shell $target_user"
    bootstrap_log "dry-run: usermod -aG $admin_group $target_user"
    bootstrap_log "dry-run: chown -R $target_user:$target_user $target_home"
  else
    bootstrap_log "create: new user $target_user"
    useradd -m -s "$target_shell" "$target_user"
    usermod -aG "$admin_group" "$target_user"
    mkdir -p "$target_home"
    chown -R "$target_user:$target_user" "$target_home"
    chmod 755 "$target_home"
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
  ensure_linux_user_account "$target_user"
  root_stage_repo_for_user "$target_user" "$ROOT_TARGET_HOME"
  rerun_bootstrap_as_user "$target_user" "$ROOT_STAGE_REPO"
  bootstrap_log "bootstrap complete"
  open_login_shell_as_user "$target_user"
  exit 0
}

detect_optional_git_config() {
  if [ -n "${BOOTSTRAP_OPTIONAL_GIT_CONFIG:-}" ]; then
    printf '%s\n' "$BOOTSTRAP_OPTIONAL_GIT_CONFIG"
  elif is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
    prompt_optional_install "Git config"
  else
    printf '%s\n' "no"
  fi
}

detect_selected_agent() {
  if [ -n "${BOOTSTRAP_SELECTED_AGENT:-}" ]; then
    printf '%s\n' "$BOOTSTRAP_SELECTED_AGENT"
  elif is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
    prompt_agent_choice
  else
    printf '%s\n' "none"
  fi
}

agent_install_method() {
  agent=$1
  provider=$2

  case "$agent" in
    none) printf '%s\n' "none" ;;
    codex)
      if bootstrap_has_command npm; then
        printf '%s\n' "npm"
      elif [ "$provider" = "brew" ]; then
        printf '%s\n' "brew-cask"
      else
        printf '%s\n' "codex-release-binary"
      fi
      ;;
    claude-code)
      printf '%s\n' "claude-native-install-script"
      ;;
    opencode)
      if [ "$provider" = "brew" ]; then
        printf '%s\n' "brew-tap"
      elif bootstrap_has_command npm; then
        printf '%s\n' "npm"
      else
        printf '%s\n' "opencode-install-script"
      fi
      ;;
    mistral-vibe)
      printf '%s\n' "mistral-vibe-install-script"
      ;;
    *)
      bootstrap_fail "unsupported agent selection: $agent"
      ;;
  esac
}

agent_install_summary() {
  agent=$1
  method=$2

  case "$agent:$method" in
    codex:npm) printf '%s\n' "Install Codex via npm (@openai/codex)" ;;
    codex:brew-cask) printf '%s\n' "Install Codex via Homebrew cask" ;;
    codex:codex-release-binary) printf '%s\n' "Install Codex via prebuilt release binary" ;;
    claude-code:claude-native-install-script) printf '%s\n' "Install Claude Code via official native install script" ;;
    opencode:brew-tap) printf '%s\n' "Install OpenCode via Homebrew tap" ;;
    opencode:npm) printf '%s\n' "Install OpenCode via npm (opencode-ai)" ;;
    opencode:opencode-install-script) printf '%s\n' "Install OpenCode via official install script" ;;
    mistral-vibe:mistral-vibe-install-script) printf '%s\n' "Install Mistral Vibe via official install script" ;;
    none:none) printf '%s\n' "No agent install selected" ;;
    *) bootstrap_fail "unsupported agent install plan: $agent via $method" ;;
  esac
}

confirm_agent_install() {
  agent=$1
  method=$2

  [ "$agent" != "none" ] || return 0

  if [ -n "${BOOTSTRAP_CONFIRM_AGENT_INSTALL:-}" ]; then
    [ "$BOOTSTRAP_CONFIRM_AGENT_INSTALL" = "yes" ] || return 1
    return 0
  fi

  if is_interactive && [ -z "${BOOTSTRAP_SKIP_PROMPTS:-}" ]; then
    bootstrap_log "agent-plan: $(agent_install_summary "$agent" "$method")"
    [ "$(prompt_confirmation "Proceed with installing $agent using $method?" y)" = "yes" ] || return 1
  fi

  return 0
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

ensure_file() {
  file_path=$1

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: touch $file_path"
  else
    mkdir -p "$(dirname -- "$file_path")"
    touch "$file_path"
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
  manifest="$CONFIGS_DIR/packages/zerobrew.txt"

  [ -f "$manifest" ] || bootstrap_fail "missing ZeroBrew manifest: $manifest"
  ensure_zerobrew
  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: zerobrew install packages from $manifest"
    return 0
  fi

  set -- $(bootstrap_manifest_packages "$manifest")
  if [ "$#" -eq 0 ]; then
    bootstrap_warn "skip: no packages listed in $manifest"
    return 0
  fi

  for pkg in "$@"; do
    bootstrap_log "install: zb install $pkg"
    if ! zb install "$pkg"; then
      bootstrap_warn "skip: zerobrew package failed and was skipped: $pkg"
    fi
  done
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

agent_command_name() {
  agent=$1

  case "$agent" in
    codex) printf '%s\n' "codex" ;;
    claude-code) printf '%s\n' "claude" ;;
    opencode) printf '%s\n' "opencode" ;;
    mistral-vibe) printf '%s\n' "vibe" ;;
    none) printf '%s\n' "" ;;
    *) bootstrap_fail "unsupported agent command lookup: $agent" ;;
  esac
}

configure_codex_superpowers() {
  superpowers_dir="$HOME/.codex/superpowers"
  skills_root="$HOME/.agents/skills"
  skills_link="$skills_root/superpowers"

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: configure obra/superpowers for codex"
    bootstrap_log "dry-run: git clone https://github.com/obra/superpowers.git $superpowers_dir"
    bootstrap_log "dry-run: ln -s $superpowers_dir/skills $skills_link"
    return 0
  fi

  bootstrap_log "install: configure obra/superpowers for codex"
  mkdir -p "$HOME/.codex" "$skills_root"
  if [ -d "$superpowers_dir/.git" ]; then
    bootstrap_log "skip: obra/superpowers already present at $superpowers_dir"
    (cd "$superpowers_dir" && git pull --ff-only >/dev/null 2>&1 || true)
  else
    git clone --depth 1 https://github.com/obra/superpowers.git "$superpowers_dir"
  fi
  if [ -L "$skills_link" ] && [ "$(readlink "$skills_link")" = "$superpowers_dir/skills" ]; then
    bootstrap_log "skip: codex superpowers symlink already present"
  else
    if [ -e "$skills_link" ] || [ -L "$skills_link" ]; then
      rm -rf "$skills_link"
    fi
    ln -s "$superpowers_dir/skills" "$skills_link"
  fi
}

install_selected_agent() {
  provider=$1
  platform=$2
  agent=$3
  method=$4

  [ "$agent" != "none" ] || return 0

  agent_command=$(agent_command_name "$agent")
  if [ -n "$agent_command" ] && bootstrap_has_command "$agent_command"; then
    bootstrap_log "skip: $agent_command already present"
    [ "$agent" = "codex" ] && configure_codex_superpowers
    return 0
  fi

  if [ "$ACTION" = "dry-run" ]; then
    bootstrap_log "dry-run: install agent $agent via $method"
  else
    bootstrap_log "install: agent $agent via $method"
  fi

  case "$agent:$method" in
    codex:npm)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: npm install -g @openai/codex"
      else
        npm install -g @openai/codex
      fi
      configure_codex_superpowers
      ;;
    codex:brew-cask)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: brew install --cask codex"
      else
        ensure_brew
        brew install --cask codex
      fi
      configure_codex_superpowers
      ;;
    codex:codex-release-binary)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: install Codex release binary into $HOME/.local/bin/codex"
      else
        install_codex_release_binary
      fi
      configure_codex_superpowers
      ;;
    claude-code:claude-native-install-script)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: curl -fsSL https://claude.ai/install.sh | bash"
      else
        sh -c "$(curl -fsSL https://claude.ai/install.sh)"
      fi
      ;;
    opencode:brew-tap)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: brew install anomalyco/tap/opencode"
      else
        ensure_brew
        brew install anomalyco/tap/opencode
      fi
      ;;
    opencode:npm)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: npm install -g opencode-ai"
      else
        npm install -g opencode-ai
      fi
      ;;
    opencode:opencode-install-script)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: curl -fsSL https://opencode.ai/install | bash"
      else
        sh -c "$(curl -fsSL https://opencode.ai/install)"
      fi
      ;;
    mistral-vibe:mistral-vibe-install-script)
      if [ "$ACTION" = "dry-run" ]; then
        bootstrap_log "dry-run: curl -LsSf https://mistral.ai/vibe/install.sh | bash"
      else
        sh -c "$(curl -LsSf https://mistral.ai/vibe/install.sh)"
      fi
      ;;
    *)
      bootstrap_fail "unsupported agent installation plan: $agent via $method on $platform"
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
  bootstrap_log "summary: provider=$provider git_config=$OPTIONAL_GIT_CONFIG agent=$SELECTED_AGENT method=$AGENT_INSTALL_METHOD docker=$OPTIONAL_DOCKER podman=$OPTIONAL_PODMAN"
  bootstrap_log "next-step: start a new login shell with 'exec zsh -l' to load updated PATH and zsh config"
}

apply_managed_files() {
  apply_target "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  apply_target "$DOTFILES_DIR/.zprofile" "$HOME/.zprofile"
  apply_target "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
  if [ "$OPTIONAL_GIT_CONFIG" = "yes" ]; then
    apply_target "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
  else
    bootstrap_log "skip: managed git config not selected"
  fi
  apply_target "$DOTFILES_DIR/.ssh/config" "$HOME/.ssh/config"
  apply_target "$DOTFILES_DIR/.zsh_plugins.txt" "$HOME/.zsh_plugins.txt"
  apply_target "$DOTFILES_DIR/.config/ghostty/config" "$HOME/.config/ghostty/config"
  if [ "$(detect_platform)" = "darwin" ]; then
    apply_target "$DOTFILES_DIR/.config/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
  fi
}

main() {
  parse_args "$@"

  platform=$(detect_platform)
  if bootstrap_is_root; then
    handle_root_bootstrap "$platform"
  fi
  provider=$(detect_provider)
  validate_provider "$provider"
  OPTIONAL_GIT_CONFIG=$(detect_optional_git_config)
  SELECTED_AGENT=$(detect_selected_agent)
  AGENT_INSTALL_METHOD=$(agent_install_method "$SELECTED_AGENT" "$provider")
  if ! confirm_agent_install "$SELECTED_AGENT" "$AGENT_INSTALL_METHOD"; then
    SELECTED_AGENT="none"
    AGENT_INSTALL_METHOD="none"
  fi
  OPTIONAL_DOCKER=$(detect_optional_docker)
  OPTIONAL_PODMAN=$(detect_optional_podman)

  bootstrap_log "mode: $ACTION"
  bootstrap_log "install-mode: $INSTALL_MODE"
  bootstrap_log "platform: $platform"
  bootstrap_log "provider: $provider"
  bootstrap_log "optional-git-config: $OPTIONAL_GIT_CONFIG"
  bootstrap_log "selected-agent: $SELECTED_AGENT"
  bootstrap_log "agent-install-method: $AGENT_INSTALL_METHOD"
  bootstrap_log "optional-docker: $OPTIONAL_DOCKER"
  bootstrap_log "optional-podman: $OPTIONAL_PODMAN"

  ensure_dir "$HOME/.ssh"
  ensure_dir "$HOME/.ssh/control"
  ensure_dir "$HOME/.config"
  ensure_file "$HOME/.zsh_history"

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
  if [ "$OPTIONAL_GIT_CONFIG" = "yes" ]; then
    setup_git_defaults "$platform"
  else
    bootstrap_log "skip: git setup not selected"
  fi
  install_selected_agent "$provider" "$platform" "$SELECTED_AGENT" "$AGENT_INSTALL_METHOD"
  install_optional_docker "$provider"
  install_optional_podman "$provider"
  print_completion
}

main "$@"
