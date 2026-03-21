# macOS Deep Clean Design

## Goal
Create a macOS cleanup script that performs a deep cleanup of regenerable files to reclaim disk space without touching OS-required files.

## Scope
- Safe defaults with explicit execution guardrails.
- Two cleanup levels: `safe` and `heavy`.
- `dry-run` mode enabled by default.
- Optional heavy categories for developer tooling.
- Before/after reporting and clear skip behavior.

## Safety Constraints
- Never remove system roots or user data directories (`Documents`, `Desktop`, `Downloads`, media, keychains).
- Only clean known cache/temp paths and only delete contents, not parent roots.
- Refuse dangerous targets (`/`, `/System`, `/Library`, `/Users`, `/Applications`, empty path).
- Skip symlinked target roots.

## High-Level Behavior
1. Detect macOS (`Darwin`) and exit otherwise.
2. Build path targets by level:
   - Safe: user cache/log/temp buckets.
   - Heavy: Xcode/CoreSimulator and language/package caches.
3. In dry-run, print reclaimable sizes only.
4. In execute mode, clear target contents and report reclaimed estimate.
5. Print disk usage before and after.

## CLI Design
- `--dry-run` (default)
- `--execute`
- `--level safe|heavy` (default: safe)
- Heavy category toggles:
  - `--with-xcode`
  - `--with-node`
  - `--with-python`
  - `--with-homebrew`
  - `--with-docker`
- `--help`

## Non-Goals
- Removing app state/data that can cause data loss.
- Deleting protected system files.
- Cleaning mounted external volumes.
