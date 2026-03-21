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

MDC_HOME="${MDC_HOME:-$HOME}"
MDC_TMPDIR="${MDC_TMPDIR:-${TMPDIR:-/tmp}}"

usage() {
  cat <<'USAGE'
Usage: macos_deep_clean.sh [options]

Safe by default: runs in dry-run mode unless --execute is provided.

Options:
  --dry-run               Print reclaimable targets (default)
  --execute               Perform deletion of approved targets
  --execute-all           Equivalent to full heavy cleanup in one flag
  --level safe|heavy      Cleanup depth (default: safe)

Heavy-level category toggles:
  --with-xcode            Include Xcode/CoreSimulator caches
  --with-node             Include npm/yarn/pnpm caches
  --with-python           Include pip/uv caches
  --with-homebrew         Run brew cache cleanup (if brew exists)
  --with-docker           Run docker builder prune (if docker exists)
  --with-system-caches    Include macOS-level caches (/Library, /private/var/*)
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

add_system_targets_for_root() {
  local root="$1"
  root="${root%/}"
  [ -n "$root" ] || root="/"

  add_target "$root/Library/Caches"
  add_target "$root/Library/Logs"
  add_target "$root/private/var/folders"
  add_target "$root/private/var/tmp"
  add_target "$root/private/var/log"
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

    if [ "$WITH_SYSTEM_CACHES" -eq 1 ]; then
      add_system_targets
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
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
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
        WITH_SYSTEM_CACHES=1
        ALL_DRIVES=1
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
      --with-system-caches)
        WITH_SYSTEM_CACHES=1
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
