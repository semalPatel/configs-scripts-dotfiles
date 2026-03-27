#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/../required_tools.sh"
HELPER_SCRIPT="$SCRIPT_DIR/../lib/bootstrap_common.sh"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  haystack=$1
  needle=$2

  printf '%s' "$haystack" | grep -Fq "$needle" || fail "expected output to contain: $needle"
}

assert_absent() {
  path=$1

  [ ! -e "$path" ] || fail "expected path to remain absent: $path"
}

assert_file() {
  path=$1

  [ -f "$path" ] || fail "expected file: $path"
}

assert_symlink_target() {
  path=$1
  expected=$2

  [ -L "$path" ] || fail "expected symlink: $path"
  [ "$(readlink "$path")" = "$expected" ] || fail "expected $path -> $expected"
}

mkfixture() {
  mktemp -d
}

write_stub() {
  path=$1
  shift

  cat >"$path" <<EOF
#!/bin/sh
set -eu
$*
EOF
  chmod +x "$path"
}

run_bootstrap() {
  home_dir=$1
  shift

  BOOTSTRAP_MISSING_COMMANDS="${BOOTSTRAP_MISSING_COMMANDS:-}" HOME="$home_dir" /bin/sh "$BOOTSTRAP_SCRIPT" "$@" 2>&1
}

run_bootstrap_with_path() {
  home_dir=$1
  path_dir=$2
  shift 2

  BOOTSTRAP_MISSING_COMMANDS="${BOOTSTRAP_MISSING_COMMANDS:-}" HOME="$home_dir" PATH="$path_dir:/usr/bin:/bin" /bin/sh "$BOOTSTRAP_SCRIPT" "$@" 2>&1
}

run_bootstrap_interactive() {
  home_dir=$1
  path_dir=$2
  answers=$3
  shift 3

  printf '%s' "$answers" | BOOTSTRAP_MISSING_COMMANDS="${BOOTSTRAP_MISSING_COMMANDS:-}" HOME="$home_dir" PATH="$path_dir:/usr/bin:/bin" BOOTSTRAP_ASSUME_TTY=1 /bin/sh "$BOOTSTRAP_SCRIPT" "$@" 2>&1
}

if [ ! -f "$BOOTSTRAP_SCRIPT" ]; then
  fail "bootstrap script not found: $BOOTSTRAP_SCRIPT"
fi

fixture_root="$(mkfixture)"
trap 'rm -rf "$fixture_root"' EXIT

home_dir="$fixture_root/home"
mkdir -p "$home_dir"

output="$(run_bootstrap "$home_dir" --dry-run --platform darwin)" || fail "bootstrap dry-run failed: $output"
assert_contains "$output" "mode: dry-run"
assert_contains "$output" "install-mode: link"
assert_contains "$output" "provider: brew"
assert_contains "$output" "optional-codex: no"
assert_contains "$output" "optional-docker: no"
assert_contains "$output" "optional-podman: no"
assert_contains "$output" "dry-run: brew bundle --file $REPO_ROOT/configs/Brewfile"
assert_contains "$output" "dry-run: git setup"
assert_contains "$output" "dotfiles/.zshrc -> $home_dir/.zshrc"
assert_contains "$output" "dotfiles/.zprofile -> $home_dir/.zprofile"
assert_contains "$output" "dotfiles/.zshenv -> $home_dir/.zshenv"
assert_contains "$output" "dotfiles/.gitconfig -> $home_dir/.gitconfig"
assert_contains "$output" "dotfiles/.ssh/config -> $home_dir/.ssh/config"
assert_contains "$output" "dotfiles/.zsh_plugins.txt -> $home_dir/.zsh_plugins.txt"
assert_contains "$output" "bootstrap complete"
assert_contains "$output" "next-step: start a new login shell with 'exec zsh -l' to load updated PATH and zsh config"
assert_absent "$home_dir/.zshrc"
assert_contains "$(cat "$REPO_ROOT/dotfiles/.zprofile")" '$HOME/.local/bin'
assert_contains "$(cat "$REPO_ROOT/dotfiles/.zshrc")" 'antidote'
if grep -Fq 'oh-my-zsh' "$REPO_ROOT/dotfiles/.zshrc"; then
  fail "expected managed .zshrc to avoid oh-my-zsh"
fi

copy_output="$(run_bootstrap "$home_dir" --dry-run --copy --platform darwin)" || fail "bootstrap copy dry-run failed: $copy_output"
assert_contains "$copy_output" "install-mode: copy"
assert_contains "$copy_output" "dotfiles/.zshrc -> $home_dir/.zshrc"

unsupported_bin="$fixture_root/unsupported-bin"
mkdir -p "$unsupported_bin"
write_stub "$unsupported_bin/uname" 'printf "%s\n" "FreeBSD"'
if unsupported_output="$(run_bootstrap_with_path "$home_dir" "$unsupported_bin" --dry-run 2>&1)"; then
  fail "expected unsupported platform to fail"
fi
assert_contains "$unsupported_output" "unsupported platform/package-manager pair: unknown/brew"

linux_bin="$fixture_root/linux-bin"
mkdir -p "$linux_bin"
write_stub "$linux_bin/uname" 'printf "%s\n" "Linux"'
write_stub "$linux_bin/brew" 'exit 0'
write_stub "$linux_bin/apt-get" 'printf "apt-get %s\n" "$*" >> "'"$fixture_root"'/apt.log"'
linux_output="$(run_bootstrap_with_path "$home_dir" "$linux_bin" --dry-run)" || fail "linux dry-run failed: $linux_output"
assert_contains "$linux_output" "platform: linux"
assert_contains "$linux_output" "provider: apt"
assert_contains "$linux_output" "dry-run: apt install packages from"

linux_apply_bin="$fixture_root/linux-apply-bin"
mkdir -p "$linux_apply_bin"
apt_apply_log="$fixture_root/apt-apply.log"
write_stub "$linux_apply_bin/uname" 'printf "%s\n" "Linux"'
write_stub "$linux_apply_bin/sudo" '"$@"'
write_stub "$linux_apply_bin/apt-get" '
printf "apt-get %s\n" "$*" >> "'"$apt_apply_log"'"
if [ "$1" = "update" ]; then
  exit 0
fi
pkg=""
for arg in "$@"; do
  case "$arg" in
    -*) ;;
    install) ;;
    *) pkg="$arg" ;;
  esac
done
if [ "$1" = "install" ] && [ "$pkg" = "docker-compose-plugin" ]; then
  printf "%s\n" "E: Unable to locate package docker-compose-plugin" >&2
  exit 100
fi
if [ "$1" = "install" ] && [ "$pkg" = "docker-compose" ]; then
  exit 0
fi
exit 0'
write_stub "$linux_apply_bin/git" '
if [ "$1" = "clone" ]; then
  for target do :; done
  mkdir -p "$target"
  printf "%s\n" "# antidote stub" > "$target/antidote.zsh"
  exit 0
fi
exit 0'
linux_apply_home="$fixture_root/linux-apply-home"
mkdir -p "$linux_apply_home"
linux_apply_output="$(BOOTSTRAP_MISSING_COMMANDS='git zsh' run_bootstrap_interactive "$linux_apply_home" "$linux_apply_bin" '3
n
y
n
' --apply)" || fail "linux apply failed: $linux_apply_output"
assert_contains "$linux_apply_output" "warn: apt package unavailable, retrying with fallback docker-compose: docker-compose-plugin"
assert_contains "$(cat "$apt_apply_log")" "apt-get install -y docker-compose-plugin"
assert_contains "$(cat "$apt_apply_log")" "apt-get install -y docker-compose"
assert_file "$linux_apply_home/.gitconfig"
assert_file "$linux_apply_home/.ssh/config"

darwin_bin="$fixture_root/darwin-bin"
mkdir -p "$darwin_bin"
write_stub "$darwin_bin/uname" 'printf "%s\n" "Darwin"'
darwin_output="$(BOOTSTRAP_MISSING_COMMANDS=brew run_bootstrap_with_path "$home_dir" "$darwin_bin" --dry-run)" || fail "darwin auto-detect dry-run failed: $darwin_output"
assert_contains "$darwin_output" "platform: darwin"
assert_contains "$darwin_output" "provider: brew"
assert_contains "$darwin_output" "dry-run: install Homebrew"
assert_contains "$darwin_output" "dry-run: brew bundle --file $REPO_ROOT/configs/Brewfile"

interactive_bin="$fixture_root/interactive-bin"
mkdir -p "$interactive_bin"
write_stub "$interactive_bin/uname" 'printf "%s\n" "Darwin"'
interactive_output="$(BOOTSTRAP_MISSING_COMMANDS='codex docker podman' run_bootstrap_interactive "$home_dir" "$interactive_bin" '2
y
y
n
' --dry-run)" || fail "interactive dry-run failed: $interactive_output"
assert_contains "$interactive_output" "provider: zerobrew"
assert_contains "$interactive_output" "optional-codex: yes"
assert_contains "$interactive_output" "optional-docker: yes"
assert_contains "$interactive_output" "optional-podman: no"
assert_contains "$interactive_output" "dry-run: install ZeroBrew"
assert_contains "$interactive_output" "dry-run: zb bundle install -f $REPO_ROOT/configs/Brewfile"
assert_contains "$interactive_output" "dry-run: install Codex CLI"
assert_contains "$interactive_output" "dry-run: zb install docker docker-compose"

root_bin="$fixture_root/root-bin"
mkdir -p "$root_bin"
write_stub "$root_bin/uname" 'printf "%s\n" "Linux"'
write_stub "$root_bin/id" '
if [ "${1:-}" = "-u" ]; then
  printf "%s\n" "0"
  exit 0
fi
exit 1'
write_stub "$root_bin/getent" '
if [ "${1:-}" = "group" ] && [ "${2:-}" = "sudo" ]; then
  printf "%s\n" "sudo:x:27:"
  exit 0
fi
exit 2'
write_stub "$root_bin/apt-get" 'exit 0'
if root_noninteractive_output="$(run_bootstrap_with_path "$home_dir" "$root_bin" --dry-run 2>&1)"; then
  fail "expected root noninteractive bootstrap to fail"
fi
assert_contains "$root_noninteractive_output" "must run as a non-root user"

root_interactive_output="$(run_bootstrap_interactive "$home_dir" "$root_bin" 'y
dev
' --dry-run)" || fail "root interactive dry-run failed: $root_interactive_output"
assert_contains "$root_interactive_output" "info: bootstrap is running as root"
assert_contains "$root_interactive_output" "dry-run: useradd -m -s"
assert_contains "$root_interactive_output" "dry-run: usermod -aG sudo dev"
assert_contains "$root_interactive_output" "dry-run: stage bootstrap repo at /home/dev/.local/share/dotfiles-bootstrap/repo"
assert_contains "$root_interactive_output" "dry-run: su - dev -c /bin/sh '/home/dev/.local/share/dotfiles-bootstrap/repo/scripts/required_tools.sh' --dry-run"
assert_contains "$root_interactive_output" "next-step: start a login shell as dev with 'su - dev'"

root_darwin_bin="$fixture_root/root-darwin-bin"
mkdir -p "$root_darwin_bin"
write_stub "$root_darwin_bin/uname" 'printf "%s\n" "Darwin"'
write_stub "$root_darwin_bin/id" 'if [ "${1:-}" = "-u" ]; then printf "%s\n" "0"; else exit 1; fi'
if root_darwin_output="$(run_bootstrap_with_path "$home_dir" "$root_darwin_bin" --dry-run 2>&1)"; then
  fail "expected macOS root bootstrap to fail"
fi
assert_contains "$root_darwin_output" "run this bootstrap from your normal macOS user account"

interactive_both_output="$(BOOTSTRAP_MISSING_COMMANDS='docker podman' run_bootstrap_interactive "$home_dir" "$interactive_bin" '1
n
y
y
' --dry-run)" || fail "interactive both dry-run failed: $interactive_both_output"
assert_contains "$interactive_both_output" "provider: brew"
assert_contains "$interactive_both_output" "optional-codex: no"
assert_contains "$interactive_both_output" "optional-docker: yes"
assert_contains "$interactive_both_output" "optional-podman: yes"
assert_contains "$interactive_both_output" "dry-run: brew install docker docker-compose"
assert_contains "$interactive_both_output" "dry-run: brew install podman"

existing_tools_bin="$fixture_root/existing-tools-bin"
mkdir -p "$existing_tools_bin"
write_stub "$existing_tools_bin/uname" 'printf "%s\n" "Darwin"'
write_stub "$existing_tools_bin/brew" 'exit 0'
write_stub "$existing_tools_bin/codex" 'exit 0'
write_stub "$existing_tools_bin/docker" 'exit 0'
write_stub "$existing_tools_bin/podman" 'exit 0'
existing_tools_output="$(run_bootstrap_interactive "$home_dir" "$existing_tools_bin" '1
y
y
y
' --dry-run)" || fail "existing tools dry-run failed: $existing_tools_output"
assert_contains "$existing_tools_output" "skip: codex already present"
assert_contains "$existing_tools_output" "skip: docker already present"
assert_contains "$existing_tools_output" "skip: podman already present"

darwin_apply_bin="$fixture_root/darwin-apply-bin"
mkdir -p "$darwin_apply_bin"
brew_log="$fixture_root/brew.log"
git_log="$fixture_root/git.log"
npm_log="$fixture_root/npm.log"
write_stub "$darwin_apply_bin/uname" 'printf "%s\n" "Darwin"'
write_stub "$darwin_apply_bin/brew" '
printf "brew %s\n" "$*" >> "'"$brew_log"'"
if [ "$#" -ge 2 ] && [ "$1" = "install" ] && [ "$2" = "zsh" ]; then
  exit 0
fi
if [ "$#" -ge 2 ] && [ "$1" = "install" ] && [ "$2" = "git" ]; then
  exit 0
fi
if [ "$#" -ge 2 ] && [ "$1" = "bundle" ] && [ "$2" = "--file" ]; then
  exit 0
fi
exit 0'
write_stub "$darwin_apply_bin/git" '
printf "git %s\n" "$*" >> "'"$git_log"'"
if [ "$#" -ge 4 ] && [ "$1" = "clone" ]; then
  for target do :; done
  mkdir -p "$target"
  printf "%s\n" "# antidote stub" > "$target/antidote.zsh"
  exit 0
fi
exit 0'
write_stub "$darwin_apply_bin/git-credential-osxkeychain" 'exit 0'
write_stub "$darwin_apply_bin/npm" 'printf "npm %s\n" "$*" >> "'"$npm_log"'"; exit 0'
apply_home="$fixture_root/apply-home"
mkdir -p "$apply_home"
apply_output="$(BOOTSTRAP_MISSING_COMMANDS='zsh git' run_bootstrap_with_path "$apply_home" "$darwin_apply_bin" --apply --copy)" || fail "darwin apply failed: $apply_output"
assert_contains "$apply_output" "install: brew bundle --file"
assert_contains "$apply_output" "install: brew install git"
assert_contains "$apply_output" "install: brew install zsh"
assert_contains "$apply_output" "install: git clone https://github.com/mattmc3/antidote.git $apply_home/.antidote"
assert_contains "$apply_output" "setup: git config init.defaultBranch main"
assert_contains "$apply_output" "bootstrap complete"
assert_file "$apply_home/.zshrc"
assert_file "$apply_home/.zprofile"
assert_file "$apply_home/.zshenv"
assert_file "$apply_home/.gitconfig"
assert_file "$apply_home/.ssh/config"
assert_file "$apply_home/.zsh_plugins.txt"
[ -d "$apply_home/.ssh/control" ] || fail "expected ssh multiplexing control directory"
assert_contains "$(cat "$brew_log")" "brew bundle --file"
assert_contains "$(cat "$brew_log")" "brew install git"
assert_contains "$(cat "$brew_log")" "brew install zsh"
assert_contains "$(cat "$git_log")" "git clone --depth 1 https://github.com/mattmc3/antidote.git $apply_home/.antidote"

link_home="$fixture_root/link-home"
mkdir -p "$link_home"
link_output="$(BOOTSTRAP_MISSING_COMMANDS=zsh run_bootstrap_with_path "$link_home" "$darwin_apply_bin" --apply)" || fail "darwin link apply failed: $link_output"
assert_symlink_target "$link_home/.zshrc" "$REPO_ROOT/dotfiles/.zshrc"
assert_symlink_target "$link_home/.zprofile" "$REPO_ROOT/dotfiles/.zprofile"

source_dir="$fixture_root/source"
target_dir="$fixture_root/target"
mkdir -p "$source_dir" "$target_dir"
printf '%s\n' "hello" > "$source_dir/example.txt"
. "$HELPER_SCRIPT"
bootstrap_link_target "$source_dir/example.txt" "$target_dir/example.txt"
bootstrap_link_target "$source_dir/example.txt" "$target_dir/example.txt"
assert_symlink_target "$target_dir/example.txt" "$source_dir/example.txt"
backup_count="$(find "$target_dir" -maxdepth 1 -name 'example.txt.bak.*' | wc -l | tr -d ' ')"
[ "$backup_count" = "0" ] || fail "expected no backups for idempotent relink, found $backup_count"

copy_source="$fixture_root/copy-source"
copy_target="$fixture_root/copy-target"
mkdir -p "$copy_source" "$copy_target"
printf '%s\n' "hello" > "$copy_source/example.txt"
cp "$copy_source/example.txt" "$copy_target/example.txt"
bootstrap_copy_target "$copy_source/example.txt" "$copy_target/example.txt"
bootstrap_copy_target "$copy_source/example.txt" "$copy_target/example.txt"
assert_file "$copy_target/example.txt"
copy_backup_count="$(find "$copy_target" -maxdepth 1 -name 'example.txt.bak.*' | wc -l | tr -d ' ')"
[ "$copy_backup_count" = "0" ] || fail "expected no backups for idempotent recopy, found $copy_backup_count"

echo "PASS: required_tools tests"
