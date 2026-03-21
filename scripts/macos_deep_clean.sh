#!/usr/bin/env bash
set -euo pipefail

MODE="dry-run"
LEVEL="safe"
WITH_XCODE=0
WITH_NODE=0
WITH_PYTHON=0
WITH_HOMEBREW=0
WITH_DOCKER=0
WITH_SYSTEM_CACHES=0
ALL_DRIVES=0
WITH_BROWSER_CACHES=0
WITH_DEV_CACHES=0
WITH_XCODE_ARCHIVES=0
WITH_ROSETTA_CACHE=0
WITH_LOCAL_SNAPSHOTS=0
WITH_SIMULATOR_PRUNE=0
REPORT_TOP_SPACE=0
TOP_LIMIT=20

MDC_HOME="${MDC_HOME:-$HOME}"
MDC_TMPDIR="${MDC_TMPDIR:-${TMPDIR:-/tmp}}"

usage() {
  cat <<'USAGE'
Usage: macos_deep_clean.sh [options]

Safe by default: runs in dry-run mode unless --execute is provided.

Options:
  --dry-run               Print reclaimable targets (default)
  --dry-run-all           Equivalent to full heavy preview in one flag
  --execute               Perform deletion of approved targets
  --execute-all           Equivalent to full heavy cleanup in one flag
  --report-top-space      Print largest directories/files and exit
  --top-limit N           Number of rows for top-space report (default: 20)
  --level safe|heavy      Cleanup depth (default: safe)

Heavy-level category toggles:
  --with-xcode            Include Xcode/CoreSimulator caches
  --with-node             Include npm/yarn/pnpm caches
  --with-python           Include pip/uv caches
  --with-homebrew         Run brew cache cleanup (if brew exists)
  --with-docker           Run docker builder prune (if docker exists)
  --with-browser-caches   Include browser/webview caches
  --with-dev-caches       Include Gradle/Maven/Ivy/Cargo/Composer/Playwright/Cypress caches
  --with-xcode-archives   Include Xcode Archives/Products/ModuleCache and simulator device caches
  --with-rosetta-cache    Include Rosetta translation cache (/private/var/db/oah)
  --with-system-caches    Include macOS-level caches (/Library, /private/var/*)
  --with-local-snapshots  Try thinning/deleting APFS local snapshots (tmutil)
  --with-simulator-prune  Delete unavailable iOS Simulators (xcrun simctl)
  --all-drives            Include mounted volumes under /Volumes when using --with-system-caches

  --help                  Show this help
USAGE
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

require_macos() {
  if [ "${MDC_ALLOW_NON_DARWIN:-0}" = "1" ]; then
    return 0
  fi
  if [ "$(uname -s)" != "Darwin" ]; then
    printf 'This script supports macOS only.\n' >&2
    exit 1
  fi
}

bytes_to_human_kib() {
  local kib="$1"
  awk -v kib="$kib" 'BEGIN {
    if (kib < 1024) { printf "%d KiB", kib; exit }
    mib = kib / 1024
    if (mib < 1024) { printf "%.2f MiB", mib; exit }
    gib = mib / 1024
    printf "%.2f GiB", gib
  }'
}

is_dangerous_target() {
  local p="$1"
  case "$p" in
    ""|"/"|"/System"|"/Library"|"/Users"|"/Applications"|"/bin"|"/sbin"|"/usr"|"/etc"|"/var")
      return 0
      ;;
  esac
  return 1
}

kib_for_path() {
  local p="$1"
  local out
  [ -e "$p" ] || { echo 0; return; }
  out="$(du -sk "$p" 2>/dev/null || true)"
  if [ -z "$out" ]; then
    echo 0
    return
  fi
  printf '%s\n' "$out" | awk '{print $1+0}'
}

clean_contents() {
  local target="$1"

  [ -e "$target" ] || return 0

  if [ -L "$target" ]; then
    warn "Skipping symlink target: $target"
    return 0
  fi

  if is_dangerous_target "$target"; then
    warn "Refusing dangerous target: $target"
    return 0
  fi

  find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
}

TARGETS=()
add_target() {
  TARGETS+=("$1")
}

add_targets_from_find() {
  local base="$1"
  shift
  [ -d "$base" ] || return 0
  while IFS= read -r path; do
    [ -n "$path" ] && add_target "$path"
  done < <(find "$base" "$@" 2>/dev/null || true)
}

add_system_targets_for_root() {
  local root="$1"
  root="${root%/}"
  [ -n "$root" ] || root=""

  add_target "$root/Library/Caches"
  add_target "$root/Library/Logs"
  add_target "$root/private/var/folders"
  add_target "$root/private/var/tmp"
  add_target "$root/private/var/log"
  add_target "$root/Library/Updates"
}

add_system_targets() {
  local -a roots=()
  roots+=("/")

  if [ -n "${MDC_SYSTEM_ROOTS:-}" ]; then
    roots=()
    local old_ifs="$IFS"
    IFS=":"
    for r in $MDC_SYSTEM_ROOTS; do
      [ -n "$r" ] && roots+=("$r")
    done
    IFS="$old_ifs"
  elif [ "$ALL_DRIVES" -eq 1 ]; then
    local vol
    for vol in /Volumes/*; do
      [ -d "$vol" ] || continue
      [ -L "$vol" ] && continue
      roots+=("$vol")
    done
  fi

  local root
  for root in "${roots[@]}"; do
    add_system_targets_for_root "$root"
  done
}

build_targets() {
  add_target "$MDC_HOME/Library/Caches"
  add_target "$MDC_HOME/Library/Logs"
  add_target "$MDC_HOME/Library/Application Support/CrashReporter"
  add_target "$MDC_HOME/Library/WebKit"
  add_target "$MDC_TMPDIR"

  if [ "$LEVEL" = "heavy" ]; then
    if [ "$WITH_XCODE" -eq 1 ]; then
      add_target "$MDC_HOME/Library/Developer/Xcode/DerivedData"
      add_target "$MDC_HOME/Library/Developer/Xcode/iOS DeviceSupport"
      add_target "$MDC_HOME/Library/Developer/CoreSimulator/Caches"
    fi

    if [ "$WITH_NODE" -eq 1 ]; then
      add_target "$MDC_HOME/.npm"
      add_target "$MDC_HOME/Library/Caches/Yarn"
      add_target "$MDC_HOME/Library/Caches/pnpm"
    fi

    if [ "$WITH_PYTHON" -eq 1 ]; then
      add_target "$MDC_HOME/.cache/pip"
      add_target "$MDC_HOME/.cache/uv"
    fi

    if [ "$WITH_BROWSER_CACHES" -eq 1 ]; then
      add_target "$MDC_HOME/Library/Caches/com.apple.Safari"
      add_target "$MDC_HOME/Library/Caches/Google/Chrome/Default/Cache"
      add_targets_from_find "$MDC_HOME/Library/Caches/Firefox/Profiles" -type d -name "cache2"
      add_targets_from_find "$MDC_HOME/Library/Containers" -type d -path "*/Data/Library/Caches"
    fi

    if [ "$WITH_DEV_CACHES" -eq 1 ]; then
      add_target "$MDC_HOME/.gradle/caches"
      add_target "$MDC_HOME/.m2/repository"
      add_target "$MDC_HOME/.ivy2/cache"
      add_target "$MDC_HOME/.cargo/registry"
      add_target "$MDC_HOME/.cargo/git"
      add_target "$MDC_HOME/.composer/cache"
      add_target "$MDC_HOME/.cache/ms-playwright"
      add_target "$MDC_HOME/Library/Caches/Cypress"
    fi

    if [ "$WITH_XCODE_ARCHIVES" -eq 1 ]; then
      add_target "$MDC_HOME/Library/Developer/Xcode/Archives"
      add_target "$MDC_HOME/Library/Developer/Xcode/Products"
      add_target "$MDC_HOME/Library/Developer/Xcode/ModuleCache.noindex"
      add_targets_from_find "$MDC_HOME/Library/Developer/CoreSimulator/Devices" -type d -path "*/data/Library/Caches"
    fi

    if [ "$WITH_SYSTEM_CACHES" -eq 1 ]; then
      add_system_targets
    fi

    if [ "$WITH_ROSETTA_CACHE" -eq 1 ]; then
      add_target "/private/var/db/oah"
      if [ -n "${MDC_SYSTEM_ROOTS:-}" ]; then
        local old_ifs="$IFS"
        IFS=":"
        for r in $MDC_SYSTEM_ROOTS; do
          [ -n "$r" ] && add_target "${r%/}/private/var/db/oah"
        done
        IFS="$old_ifs"
      fi
    fi
  fi
}

run_tool_cleanups() {
  if [ "$MODE" != "execute" ]; then
    return 0
  fi

  if [ "$LEVEL" = "heavy" ] && [ "$WITH_HOMEBREW" -eq 1 ]; then
    if command -v brew >/dev/null 2>&1; then
      log "Running: brew cleanup -s"
      brew cleanup -s >/dev/null 2>&1 || warn "brew cleanup failed"
    else
      warn "brew not found; skipping homebrew cleanup"
    fi
  fi

  if [ "$LEVEL" = "heavy" ] && [ "$WITH_DOCKER" -eq 1 ]; then
    if command -v docker >/dev/null 2>&1; then
      log "Running: docker builder prune -af"
      docker builder prune -af >/dev/null 2>&1 || warn "docker prune failed"
    else
      warn "docker not found; skipping docker cleanup"
    fi
  fi

  if [ "$LEVEL" = "heavy" ] && [ "$WITH_SIMULATOR_PRUNE" -eq 1 ]; then
    if command -v xcrun >/dev/null 2>&1; then
      log "Running: xcrun simctl delete unavailable"
      xcrun simctl delete unavailable >/dev/null 2>&1 || warn "simulator prune failed"
    else
      warn "xcrun not found; skipping simulator prune"
    fi
  fi

  if [ "$LEVEL" = "heavy" ] && [ "$WITH_LOCAL_SNAPSHOTS" -eq 1 ]; then
    if command -v tmutil >/dev/null 2>&1; then
      log "Running: tmutil thinlocalsnapshots / 10000000000 4"
      tmutil thinlocalsnapshots / 10000000000 4 >/dev/null 2>&1 || warn "snapshot thinning failed"
    else
      warn "tmutil not found; skipping local snapshots cleanup"
    fi
  fi
}

report_top_space() {
  local base="$MDC_HOME"
  local limit="$TOP_LIMIT"

  log "Top space report:"
  log "Top directories under $base:"

  {
    du -x -d 3 "$base" 2>/dev/null || du -x --max-depth=3 "$base" 2>/dev/null || true
  } | sort -nr | head -n "$limit" | while IFS= read -r row; do
    [ -n "$row" ] || continue
    local kib path
    kib="$(printf '%s\n' "$row" | awk '{print $1+0}')"
    path="$(printf '%s\n' "$row" | cut -f2-)"
    log "  $(bytes_to_human_kib "$kib")  $path"
  done

  log "Top files under $base:"
  find "$base" -xdev -type f -exec du -k {} + 2>/dev/null | sort -nr | head -n "$limit" | while IFS= read -r row; do
    [ -n "$row" ] || continue
    local kib path
    kib="$(printf '%s\n' "$row" | awk '{print $1+0}')"
    path="$(printf '%s\n' "$row" | cut -f2-)"
    log "  $(bytes_to_human_kib "$kib")  $path"
  done
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run-all)
        MODE="dry-run"
        LEVEL="heavy"
        WITH_XCODE=1
        WITH_NODE=1
        WITH_PYTHON=1
        WITH_HOMEBREW=1
        WITH_DOCKER=1
        WITH_BROWSER_CACHES=1
        WITH_DEV_CACHES=1
        WITH_XCODE_ARCHIVES=1
        WITH_ROSETTA_CACHE=1
        WITH_SYSTEM_CACHES=1
        WITH_LOCAL_SNAPSHOTS=1
        WITH_SIMULATOR_PRUNE=1
        ALL_DRIVES=1
        ;;
      --dry-run)
        MODE="dry-run"
        ;;
      --execute)
        MODE="execute"
        ;;
      --execute-all)
        MODE="execute"
        LEVEL="heavy"
        WITH_XCODE=1
        WITH_NODE=1
        WITH_PYTHON=1
        WITH_HOMEBREW=1
        WITH_DOCKER=1
        WITH_BROWSER_CACHES=1
        WITH_DEV_CACHES=1
        WITH_XCODE_ARCHIVES=1
        WITH_ROSETTA_CACHE=1
        WITH_SYSTEM_CACHES=1
        WITH_LOCAL_SNAPSHOTS=1
        WITH_SIMULATOR_PRUNE=1
        ALL_DRIVES=1
        ;;
      --report-top-space)
        REPORT_TOP_SPACE=1
        ;;
      --top-limit)
        shift
        [ "$#" -gt 0 ] || { warn "--top-limit requires a value"; usage; exit 1; }
        case "$1" in
          ''|*[!0-9]*)
            warn "Invalid --top-limit value: $1"
            usage
            exit 1
            ;;
          *)
            if [ "$1" -lt 1 ]; then
              warn "--top-limit must be >= 1"
              usage
              exit 1
            fi
            TOP_LIMIT="$1"
            ;;
        esac
        ;;
      --level)
        shift
        [ "$#" -gt 0 ] || { warn "--level requires a value"; usage; exit 1; }
        case "$1" in
          safe|heavy)
            LEVEL="$1"
            ;;
          *)
            warn "Invalid level: $1"
            usage
            exit 1
            ;;
        esac
        ;;
      --with-xcode)
        WITH_XCODE=1
        ;;
      --with-node)
        WITH_NODE=1
        ;;
      --with-python)
        WITH_PYTHON=1
        ;;
      --with-homebrew)
        WITH_HOMEBREW=1
        ;;
      --with-docker)
        WITH_DOCKER=1
        ;;
      --with-browser-caches)
        WITH_BROWSER_CACHES=1
        ;;
      --with-dev-caches)
        WITH_DEV_CACHES=1
        ;;
      --with-xcode-archives)
        WITH_XCODE_ARCHIVES=1
        ;;
      --with-rosetta-cache)
        WITH_ROSETTA_CACHE=1
        ;;
      --with-system-caches)
        WITH_SYSTEM_CACHES=1
        ;;
      --with-local-snapshots)
        WITH_LOCAL_SNAPSHOTS=1
        ;;
      --with-simulator-prune)
        WITH_SIMULATOR_PRUNE=1
        ;;
      --all-drives)
        ALL_DRIVES=1
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  require_macos
  parse_args "$@"

  if [ "$REPORT_TOP_SPACE" -eq 1 ]; then
    report_top_space
    exit 0
  fi

  build_targets

  log "Mode: $MODE"
  log "Level: $LEVEL"
  log "Disk before:"
  df -h

  local total_kib=0
  for t in "${TARGETS[@]}"; do
    if [ ! -e "$t" ]; then
      continue
    fi

    size_kib="$(kib_for_path "$t")"
    total_kib=$((total_kib + size_kib))

    if [ "$MODE" = "dry-run" ]; then
      log "[DRY-RUN] $t ($(bytes_to_human_kib "$size_kib"))"
    else
      log "[CLEAN] $t ($(bytes_to_human_kib "$size_kib"))"
      clean_contents "$t"
    fi
  done

  run_tool_cleanups

  log "Estimated reclaimable/reclaimed: $(bytes_to_human_kib "$total_kib")"
  log "Disk after:"
  df -h

  if [ "$MODE" = "dry-run" ]; then
    log "Dry-run only. Re-run with --execute to apply cleanup."
  fi
}

main "$@"
