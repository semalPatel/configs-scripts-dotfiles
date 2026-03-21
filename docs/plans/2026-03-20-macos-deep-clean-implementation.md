# macOS Deep Clean Script Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a safe deep-clean macOS script with dry-run by default and heavy optional cleanup categories.

**Architecture:** A single POSIX-compatible shell script (`bash`/`zsh` compatible syntax) computes approved cleanup targets by level/category, estimates sizes with `du`, and either reports or removes contents in guarded mode.

**Tech Stack:** Shell (`/usr/bin/env bash`), standard macOS tools (`du`, `df`, `find`, `rm`).

---

### Task 1: Add failing tests for dry-run and execute behavior

**Files:**
- Create: `scripts/tests/test_macos_deep_clean.sh`
- Test: `scripts/tests/test_macos_deep_clean.sh`

1. Create a temp fixture root with mock `HOME` and `TMPDIR` style directories.
2. Write assertions for:
- dry-run does not delete files.
- safe execute deletes safe targets but not heavy-only targets.
- heavy execute deletes heavy targets.
3. Run test script and verify it fails before implementation.

### Task 2: Implement cleanup script

**Files:**
- Create: `scripts/macos_deep_clean.sh`
- Modify: `scripts/tests/test_macos_deep_clean.sh` (only if test contract adjustments are needed)

1. Implement CLI parsing (`--dry-run`, `--execute`, `--level`, toggles).
2. Add target generation for safe and heavy paths.
3. Add deletion guardrails and content-only cleanup behavior.
4. Add reporting: before/after disk output and estimated reclaimed size.

### Task 3: Verify green and document usage

**Files:**
- Modify: `README.md`

1. Run test script and verify full pass.
2. Add concise README usage examples and safety notes.
3. Re-run tests to ensure no regressions.
