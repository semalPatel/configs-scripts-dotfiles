#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
CAPTURE_SCRIPT="$SCRIPT_DIR/../capture_userspace.sh"

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_absent() {
  [ ! -e "$1" ] || fail "expected path to be absent: $1"
}

assert_contains() {
  haystack=$1
  needle=$2
  printf '%s' "$haystack" | grep -Fq "$needle" || fail "expected output to contain: $needle"
}

mkfixture() {
  mktemp -d
}

if [ ! -f "$CAPTURE_SCRIPT" ]; then
  fail "capture script not found: $CAPTURE_SCRIPT"
fi

fixture_root="$(mkfixture)"
trap 'rm -rf "$fixture_root"' EXIT

source_home="$fixture_root/source-home"
repo_root="$fixture_root/repo-root"
mkdir -p "$source_home/.ssh" "$source_home/Library/Application Support/com.mitchellh.ghostty" "$repo_root"

printf '%s\n' "export PATH=\"$source_home/.local/bin:$source_home/bin:\$PATH\"" > "$source_home/.zshenv"
printf '%s\n' "export PATH=\"$source_home/.cargo/bin:\$PATH\"" > "$source_home/.zprofile"
printf '%s\n' "export PATH=\"$source_home/.antigravity/antigravity/bin:\$PATH\"" > "$source_home/.zshrc"
cat > "$source_home/.gitconfig" <<EOF
[user]
	name = Test User
	email = test@example.com
EOF
cat > "$source_home/.ssh/config" <<EOF
Include $source_home/.colima/ssh_config
Include ~/.ssh/conf.d/*.conf

Host github.com
  AddKeysToAgent yes
  IdentityFile ~/.ssh/github_noreply
  ForwardX11 yes
EOF
printf '%s\n' 'PRIVATE KEY DATA' > "$source_home/.ssh/id_rsa"
printf '%s\n' 'PUBLIC KEY DATA' > "$source_home/.ssh/id_rsa.pub"
printf '%s\n' 'keybind = cmd+backspace=esc:w' > "$source_home/Library/Application Support/com.mitchellh.ghostty/config"

output="$(CAPTURE_SOURCE_HOME="$source_home" CAPTURE_REPO_ROOT="$repo_root" sh "$CAPTURE_SCRIPT")" || fail "capture script failed: $output"

assert_file "$repo_root/dotfiles/.zshenv"
assert_file "$repo_root/dotfiles/.zprofile"
assert_file "$repo_root/dotfiles/.zshrc"
assert_file "$repo_root/dotfiles/.gitconfig"
assert_file "$repo_root/dotfiles/.ssh/config"
assert_file "$repo_root/dotfiles/.config/ghostty/config"
assert_absent "$repo_root/dotfiles/.ssh/id_rsa"
assert_absent "$repo_root/dotfiles/.ssh/id_rsa.pub"

assert_contains "$(cat "$repo_root/dotfiles/.zshenv")" 'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"'
assert_contains "$(cat "$repo_root/dotfiles/.zprofile")" 'export PATH="$HOME/.cargo/bin:$PATH"'
assert_contains "$(cat "$repo_root/dotfiles/.zshrc")" 'export PATH="$HOME/.antigravity/antigravity/bin:$PATH"'
assert_contains "$(cat "$repo_root/dotfiles/.ssh/config")" '# Include ~/.colima/ssh_config'
assert_contains "$(cat "$repo_root/dotfiles/.ssh/config")" 'Include ~/.ssh/conf.d/*.conf'
assert_contains "$(cat "$repo_root/dotfiles/.ssh/config")" 'IdentityFile ~/.ssh/github_noreply'
assert_contains "$(cat "$repo_root/dotfiles/.config/ghostty/config")" 'keybind = cmd+backspace=esc:w'
assert_contains "$output" "capture: dotfiles/.zshenv"
assert_contains "$output" "capture: dotfiles/.ssh/config"
assert_contains "$output" "capture: dotfiles/.config/ghostty/config"
assert_contains "$output" "summary: captured 6 files"

printf '%s\n' "PASS: capture userspace tests"
