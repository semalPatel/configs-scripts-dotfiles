#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEAN_SCRIPT="$SCRIPT_DIR/../macos_deep_clean.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_exists() {
  [ -e "$1" ] || fail "expected path to exist: $1"
}

assert_missing() {
  [ ! -e "$1" ] || fail "expected path to be deleted: $1"
}

mkfixture() {
  local root
  root="$(mktemp -d)"

  mkdir -p "$root/home/Library/Caches/app"
  mkdir -p "$root/home/Library/Logs/app"
  mkdir -p "$root/tmpdir"
  mkdir -p "$root/home/Library/Developer/Xcode/DerivedData/ProjA"
  mkdir -p "$root/home/.npm/_cacache"
  mkdir -p "$root/systemA/Library/Caches/os"
  mkdir -p "$root/systemB/private/var/folders/x"

  printf 'cache' > "$root/home/Library/Caches/app/file.tmp"
  printf 'log' > "$root/home/Library/Logs/app/log.txt"
  printf 'tmp' > "$root/tmpdir/t.tmp"
  printf 'derived' > "$root/home/Library/Developer/Xcode/DerivedData/ProjA/a"
  printf 'node' > "$root/home/.npm/_cacache/node"
  printf 'os' > "$root/systemA/Library/Caches/os/sys.cache"
  printf 'var' > "$root/systemB/private/var/folders/x/sys.tmp"

  echo "$root"
}

run_clean() {
  local root="$1"
  shift
  MDC_ALLOW_NON_DARWIN=1 \
  MDC_HOME="$root/home" \
  MDC_TMPDIR="$root/tmpdir" \
  MDC_SYSTEM_ROOTS="$root/systemA:$root/systemB" \
  "$CLEAN_SCRIPT" "$@" >/dev/null
}

if [ ! -f "$CLEAN_SCRIPT" ]; then
  echo "Cleanup script not found yet: $CLEAN_SCRIPT"
  echo "This is expected to fail before implementation."
  exit 1
fi

# 1) dry-run should not delete files
root="$(mkfixture)"
run_clean "$root" --dry-run --level heavy --with-xcode --with-node
assert_exists "$root/home/Library/Caches/app/file.tmp"
assert_exists "$root/home/Library/Developer/Xcode/DerivedData/ProjA/a"
rm -rf "$root"

# 2) safe execute should delete safe targets and keep heavy-only artifacts
root="$(mkfixture)"
run_clean "$root" --execute --level safe
assert_missing "$root/home/Library/Caches/app/file.tmp"
assert_missing "$root/home/Library/Logs/app/log.txt"
assert_missing "$root/tmpdir/t.tmp"
assert_exists "$root/home/Library/Developer/Xcode/DerivedData/ProjA/a"
assert_exists "$root/home/.npm/_cacache/node"
rm -rf "$root"

# 3) heavy execute with toggles should delete heavy targets too
root="$(mkfixture)"
run_clean "$root" --execute --level heavy --with-xcode --with-node
assert_missing "$root/home/Library/Caches/app/file.tmp"
assert_missing "$root/home/Library/Developer/Xcode/DerivedData/ProjA/a"
assert_missing "$root/home/.npm/_cacache/node"
assert_exists "$root/systemA/Library/Caches/os/sys.cache"
assert_exists "$root/systemB/private/var/folders/x/sys.tmp"
rm -rf "$root"

# 4) system cache toggle should clean OS-level cache roots
root="$(mkfixture)"
run_clean "$root" --execute --level heavy --with-system-caches
assert_missing "$root/systemA/Library/Caches/os/sys.cache"
assert_missing "$root/systemB/private/var/folders/x/sys.tmp"
rm -rf "$root"

# 5) execute-all should include heavy + all categories and system caches
root="$(mkfixture)"
run_clean "$root" --execute-all
assert_missing "$root/home/Library/Caches/app/file.tmp"
assert_missing "$root/home/Library/Developer/Xcode/DerivedData/ProjA/a"
assert_missing "$root/home/.npm/_cacache/node"
assert_missing "$root/systemA/Library/Caches/os/sys.cache"
assert_missing "$root/systemB/private/var/folders/x/sys.tmp"
rm -rf "$root"

echo "PASS: macos deep clean tests"
