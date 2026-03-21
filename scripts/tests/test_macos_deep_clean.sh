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
  mkdir -p "$root/home/Library/Developer/Xcode/Archives/A1"
  mkdir -p "$root/home/Library/Developer/Xcode/ModuleCache.noindex/M1"
  mkdir -p "$root/home/Library/Developer/CoreSimulator/Devices/D1/data/Library/Caches/C1"
  mkdir -p "$root/home/.npm/_cacache"
  mkdir -p "$root/home/.gradle/caches/modules-2"
  mkdir -p "$root/home/.m2/repository/a"
  mkdir -p "$root/home/.ivy2/cache/a"
  mkdir -p "$root/home/.cargo/registry/index"
  mkdir -p "$root/home/.cargo/git/checkouts"
  mkdir -p "$root/home/.composer/cache/files"
  mkdir -p "$root/home/.cache/ms-playwright/data"
  mkdir -p "$root/home/Library/Caches/Cypress/1"
  mkdir -p "$root/home/Library/Caches/com.apple.Safari"
  mkdir -p "$root/home/Library/Caches/Google/Chrome/Default/Cache"
  mkdir -p "$root/home/Library/Caches/Firefox/Profiles/p1/cache2"
  mkdir -p "$root/home/Library/Containers/com.foo.app/Data/Library/Caches/X"
  mkdir -p "$root/systemA/Library/Caches/os"
  mkdir -p "$root/systemB/private/var/folders/x"
  mkdir -p "$root/systemA/private/var/db/oah"
  mkdir -p "$root/systemA/Library/Updates/U1"

  printf 'cache' > "$root/home/Library/Caches/app/file.tmp"
  printf 'log' > "$root/home/Library/Logs/app/log.txt"
  printf 'tmp' > "$root/tmpdir/t.tmp"
  printf 'derived' > "$root/home/Library/Developer/Xcode/DerivedData/ProjA/a"
  printf 'archive' > "$root/home/Library/Developer/Xcode/Archives/A1/a"
  printf 'module' > "$root/home/Library/Developer/Xcode/ModuleCache.noindex/M1/m"
  printf 'simcache' > "$root/home/Library/Developer/CoreSimulator/Devices/D1/data/Library/Caches/C1/c"
  printf 'node' > "$root/home/.npm/_cacache/node"
  printf 'gradle' > "$root/home/.gradle/caches/modules-2/g"
  printf 'maven' > "$root/home/.m2/repository/a/m"
  printf 'ivy' > "$root/home/.ivy2/cache/a/i"
  printf 'cargo-reg' > "$root/home/.cargo/registry/index/r"
  printf 'cargo-git' > "$root/home/.cargo/git/checkouts/g"
  printf 'composer' > "$root/home/.composer/cache/files/c"
  printf 'playwright' > "$root/home/.cache/ms-playwright/data/p"
  printf 'cypress' > "$root/home/Library/Caches/Cypress/1/c"
  printf 'safari' > "$root/home/Library/Caches/com.apple.Safari/s"
  printf 'chrome' > "$root/home/Library/Caches/Google/Chrome/Default/Cache/c"
  printf 'firefox' > "$root/home/Library/Caches/Firefox/Profiles/p1/cache2/f"
  printf 'container' > "$root/home/Library/Containers/com.foo.app/Data/Library/Caches/X/c"
  printf 'os' > "$root/systemA/Library/Caches/os/sys.cache"
  printf 'var' > "$root/systemB/private/var/folders/x/sys.tmp"
  printf 'oah' > "$root/systemA/private/var/db/oah/oah.cache"
  printf 'upd' > "$root/systemA/Library/Updates/U1/u"

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

# 1b) dry-run-all should not delete files
root="$(mkfixture)"
run_clean "$root" --dry-run-all
assert_exists "$root/home/.m2/repository/a/m"
assert_exists "$root/home/Library/Caches/com.apple.Safari/s"
assert_exists "$root/systemA/private/var/db/oah/oah.cache"
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
assert_missing "$root/home/Library/Developer/Xcode/Archives/A1/a"
assert_missing "$root/home/Library/Developer/Xcode/ModuleCache.noindex/M1/m"
assert_missing "$root/home/Library/Developer/CoreSimulator/Devices/D1/data/Library/Caches/C1/c"
assert_missing "$root/home/.npm/_cacache/node"
assert_missing "$root/home/.gradle/caches/modules-2/g"
assert_missing "$root/home/.m2/repository/a/m"
assert_missing "$root/home/.ivy2/cache/a/i"
assert_missing "$root/home/.cargo/registry/index/r"
assert_missing "$root/home/.cargo/git/checkouts/g"
assert_missing "$root/home/.composer/cache/files/c"
assert_missing "$root/home/.cache/ms-playwright/data/p"
assert_missing "$root/home/Library/Caches/Cypress/1/c"
assert_missing "$root/home/Library/Caches/com.apple.Safari/s"
assert_missing "$root/home/Library/Caches/Google/Chrome/Default/Cache/c"
assert_missing "$root/home/Library/Caches/Firefox/Profiles/p1/cache2/f"
assert_missing "$root/home/Library/Containers/com.foo.app/Data/Library/Caches/X/c"
assert_missing "$root/systemA/Library/Caches/os/sys.cache"
assert_missing "$root/systemB/private/var/folders/x/sys.tmp"
assert_missing "$root/systemA/private/var/db/oah/oah.cache"
assert_missing "$root/systemA/Library/Updates/U1/u"
rm -rf "$root"

echo "PASS: macos deep clean tests"
