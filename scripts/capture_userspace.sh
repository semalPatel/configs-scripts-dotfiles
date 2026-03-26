#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
. "$SCRIPT_DIR/lib/bootstrap_common.sh"

REPO_ROOT="${CAPTURE_REPO_ROOT:-$(bootstrap_repo_root "$0")}"
SOURCE_HOME="${CAPTURE_SOURCE_HOME:-$HOME}"
DOTFILES_DIR="$REPO_ROOT/dotfiles"
TMP_DIR="$(mktemp -d)"

SUMMARY_CAPTURED=0
SUMMARY_SKIPPED=0

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

write_transformed() {
  input_path=$1
  output_path=$2
  transform_kind=$3
  escaped_source=$(printf '%s' "$SOURCE_HOME" | sed 's/[][\\.^$*+?(){}|]/\\&/g')

  case "$transform_kind" in
    shell)
      sed "s|$escaped_source|\\\$HOME|g" "$input_path" > "$output_path"
      ;;
    git)
      sed "s|$escaped_source|~|g" "$input_path" > "$output_path"
      ;;
    ssh)
      sed \
        -e "s|$escaped_source|~|g" \
        -e '/^[[:space:]]*Include[[:space:]].*\.colima\// s/^/# /' \
        "$input_path" > "$output_path"
      ;;
    raw)
      cp "$input_path" "$output_path"
      ;;
    *)
      bootstrap_fail "unsupported transform kind: $transform_kind"
      ;;
  esac
}

capture_file() {
  source_rel=$1
  target_rel=$2
  transform_kind=$3

  source_path="$SOURCE_HOME/$source_rel"
  target_path="$DOTFILES_DIR/$target_rel"

  if [ ! -f "$source_path" ]; then
    bootstrap_warn "skip: missing approved file $source_rel"
    SUMMARY_SKIPPED=$((SUMMARY_SKIPPED + 1))
    return 0
  fi

  bootstrap_mkdir_parent "$target_path"
  tmp_target="$TMP_DIR/$(basename -- "$target_rel")"
  write_transformed "$source_path" "$tmp_target" "$transform_kind"
  mv "$tmp_target" "$target_path"

  bootstrap_log "capture: dotfiles/${target_rel#./} from $source_rel"
  SUMMARY_CAPTURED=$((SUMMARY_CAPTURED + 1))
}

main() {
  if [ ! -d "$SOURCE_HOME" ]; then
    bootstrap_fail "source home not found: $SOURCE_HOME"
  fi

  bootstrap_log "capture-source: $SOURCE_HOME"
  bootstrap_log "capture-root: $REPO_ROOT"
  bootstrap_log "skip: secrets and private keys are intentionally excluded"

  capture_file ".zshrc" ".zshrc" shell
  capture_file ".zprofile" ".zprofile" shell
  capture_file ".zshenv" ".zshenv" shell
  capture_file ".gitconfig" ".gitconfig" git
  capture_file ".ssh/config" ".ssh/config" ssh

  bootstrap_log "summary: captured $SUMMARY_CAPTURED files, skipped $SUMMARY_SKIPPED missing approved files"
}

main "$@"
