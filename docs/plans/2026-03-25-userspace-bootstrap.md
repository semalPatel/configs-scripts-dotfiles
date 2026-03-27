# Userspace Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a portable userspace bootstrap workflow that installs the current toolset and applies repo-managed shell, git, SSH, and app config on a new Unix machine without machine-specific absolute paths.

**Architecture:** Extend `scripts/required_tools.sh` into a repo-root-aware bootstrap entrypoint with an interactive installer menu, provider abstraction for Homebrew and ZeroBrew, optional Codex CLI install, and core Git/SSH setup. Keep portable configuration in repo-managed manifests and dotfiles, and continue using the capture helper to refresh those managed files from the current machine while excluding secrets.

**Tech Stack:** POSIX shell, Homebrew, ZeroBrew, apt/dnf/pacman best-effort package installation, shell tests, symlink-based dotfile application

---

### Task 1: Inventory the repo and add bootstrap support files

**Files:**
- Create: `configs/Brewfile`
- Create: `configs/packages/apt.txt`
- Create: `configs/packages/dnf.txt`
- Create: `configs/packages/pacman.txt`
- Create: `scripts/lib/bootstrap_common.sh`
- Modify: `README.md`

**Step 1: Write the failing test**

Create a shell test file that asserts the repo now contains the required manifests and shared bootstrap library paths.

```sh
test -f configs/Brewfile
test -f configs/packages/apt.txt
test -f configs/packages/dnf.txt
test -f configs/packages/pacman.txt
test -f scripts/lib/bootstrap_common.sh
```

**Step 2: Run test to verify it fails**

Run: `test -f ../configs/Brewfile && test -f ../configs/packages/apt.txt && test -f ../configs/packages/dnf.txt && test -f ../configs/packages/pacman.txt && test -f ../scripts/lib/bootstrap_common.sh`
Expected: FAIL because the support files do not exist yet.

**Step 3: Write minimal implementation**

- Add `configs/Brewfile` based on the current machine inventory:
  - taps: `neurosnap/tap`, `schollz/tap`
  - brews: `beads`, `colima`, `docker`, `docker-compose`, `go`, `gradle`, `helm`, `kubernetes-cli`, `minikube`, `mkcert`, `neomutt`, `node@22`, `nmap`, `notmuch`, `rustup`, `uv`, `vim`, `yarn`
  - casks: `aerial`, `alacritty`, `codex`, `ghostty`, `joplin`, `monitorcontrol`, `rectangle`
- Add Linux package manifests with best-effort equivalents and comments for unsupported GUI apps.
- Add `scripts/lib/bootstrap_common.sh` with helpers for:
  - repo root resolution
  - OS detection
  - package manager detection
  - logging
  - safe backup naming

**Step 4: Run test to verify it passes**

Run: `test -f ../configs/Brewfile && test -f ../configs/packages/apt.txt && test -f ../configs/packages/dnf.txt && test -f ../configs/packages/pacman.txt && test -f ../scripts/lib/bootstrap_common.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add ../configs/Brewfile ../configs/packages/apt.txt ../configs/packages/dnf.txt ../configs/packages/pacman.txt ../scripts/lib/bootstrap_common.sh ../README.md
git commit -m "feat: add bootstrap manifests and shared shell helpers"
```

### Task 2: Add portable managed dotfiles and shell plugin manifest

**Files:**
- Create: `dotfiles/.zshrc`
- Create: `dotfiles/.zprofile`
- Create: `dotfiles/.zshenv`
- Create: `dotfiles/.gitconfig`
- Create: `dotfiles/.ssh/config`
- Create: `dotfiles/.zsh_plugins.txt`

**Step 1: Write the failing test**

Create a shell test that verifies each managed file exists and does not contain source-machine absolute home paths.

```sh
for file in dotfiles/.zshrc dotfiles/.zprofile dotfiles/.zshenv dotfiles/.gitconfig dotfiles/.ssh/config dotfiles/.zsh_plugins.txt; do
  test -f "$file" || exit 1
done
! rg -n '/Users/corrupt' dotfiles
```

**Step 2: Run test to verify it fails**

Run: `for file in ../dotfiles/.zshrc ../dotfiles/.zprofile ../dotfiles/.zshenv ../dotfiles/.gitconfig ../dotfiles/.ssh/config ../dotfiles/.zsh_plugins.txt; do test -f "$file" || exit 1; done && ! rg -n '/Users/corrupt' ../dotfiles`
Expected: FAIL because several files do not exist and the current shell config still contains absolute paths.

**Step 3: Write minimal implementation**

- Replace the existing repo `.zshrc` with a new managed config for `plain zsh + antidote`.
- Add `.zsh_plugins.txt` containing:
  - `mattmc3/ez-compinit`
  - `zsh-users/zsh-autosuggestions`
  - `zdharma-continuum/fast-syntax-highlighting`
  - `sindresorhus/pure`
- Move PATH logic into home-relative/XDG-safe forms.
- Keep portable aliases and toolchain hooks where safe.
- Remove `oh-my-zsh` references entirely.
- Add `.gitconfig` with clean `user.name` and `user.email`.
- Add `.ssh/config` with:
  - `github.com` host entry using `~/.ssh/github_noreply`
  - shared multiplexing settings
  - optional personal host aliases guarded by comments
- Exclude any key material.

**Step 4: Run test to verify it passes**

Run: `for file in ../dotfiles/.zshrc ../dotfiles/.zprofile ../dotfiles/.zshenv ../dotfiles/.gitconfig ../dotfiles/.ssh/config ../dotfiles/.zsh_plugins.txt; do test -f "$file" || exit 1; done && ! rg -n '/Users/corrupt' ../dotfiles`
Expected: PASS

**Step 5: Commit**

```bash
git add ../dotfiles/.zshrc ../dotfiles/.zprofile ../dotfiles/.zshenv ../dotfiles/.gitconfig ../dotfiles/.ssh/config ../dotfiles/.zsh_plugins.txt
git commit -m "feat: add portable managed shell and identity dotfiles"
```

### Task 3: Replace `required_tools.sh` with a portable bootstrap entrypoint

**Files:**
- Modify: `scripts/required_tools.sh`
- Modify: `scripts/lib/bootstrap_common.sh`
- Test: `scripts/tests/test_required_tools.sh`

**Step 1: Write the failing test**

Add shell tests that stub package-manager detection and assert:
- repo root is resolved relative to the script
- supported package managers dispatch correctly
- unsupported platforms fail clearly
- dotfile mapping includes expected targets

```sh
run_required_tools --dry-run --platform darwin --package-manager brew
assert_output_contains "configs/Brewfile"
assert_output_contains "$HOME/.zshrc"
```

**Step 2: Run test to verify it fails**

Run: `sh ../scripts/tests/test_required_tools.sh`
Expected: FAIL because the current script is a hardcoded apt installer with no dispatch, no dry-run model, and no config application logic.

**Step 3: Write minimal implementation**

Refactor `scripts/required_tools.sh` to:
- source `scripts/lib/bootstrap_common.sh`
- support `--dry-run`, `--apply`, `--copy`, and `--help`
- detect `darwin` vs `linux`
- prefer `brew bundle --file configs/Brewfile` on macOS
- install Linux packages from the corresponding manifest
- install `zsh` and `antidote` when needed
- create directories such as `~/.ssh`, `~/.ssh/control`, and `~/.config`
- link managed repo files into target locations
- back up existing unmanaged targets before replacement
- print skipped items for unsupported packages or apps

**Step 4: Run test to verify it passes**

Run: `sh ../scripts/tests/test_required_tools.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add ../scripts/required_tools.sh ../scripts/lib/bootstrap_common.sh ../scripts/tests/test_required_tools.sh
git commit -m "feat: replace required_tools with portable bootstrap"
```

### Task 4: Add a capture helper for refreshing repo-managed config from the current machine

**Files:**
- Create: `scripts/capture_userspace.sh`
- Test: `scripts/tests/test_capture_userspace.sh`
- Modify: `README.md`

**Step 1: Write the failing test**

Add tests for a capture helper that:
- copies only approved files into repo-managed paths
- rejects private keys and secrets
- normalizes source-machine absolute paths to home-relative forms where applicable

```sh
run_capture_fixture
assert_file_exists "dotfiles/.ssh/config"
assert_file_not_exists "dotfiles/.ssh/id_rsa"
assert_no_match "/Users/corrupt" "dotfiles/.zshenv"
```

**Step 2: Run test to verify it fails**

Run: `sh ../scripts/tests/test_capture_userspace.sh`
Expected: FAIL because no capture helper or tests exist yet.

**Step 3: Write minimal implementation**

Implement `scripts/capture_userspace.sh` to:
- capture only approved source files:
  - `~/.zshrc`
  - `~/.zprofile`
  - `~/.zshenv`
  - `~/.gitconfig`
  - `~/.ssh/config`
- write them into repo-managed destinations
- normalize absolute home prefixes to `$HOME`-relative forms where possible
- strip known machine-specific lines that should stay conditional
- skip secrets and print a summary of what was captured

**Step 4: Run test to verify it passes**

Run: `sh ../scripts/tests/test_capture_userspace.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add ../scripts/capture_userspace.sh ../scripts/tests/test_capture_userspace.sh ../README.md
git commit -m "feat: add userspace capture helper"
```

### Task 5: Verify zsh bootstrap behavior and document migration from `oh-my-zsh`

**Files:**
- Modify: `README.md`
- Modify: `dotfiles/.zshrc`
- Test: `scripts/tests/test_required_tools.sh`

**Step 1: Write the failing test**

Extend tests to verify the generated `.zshrc` references `antidote` and does not reference `oh-my-zsh`.

```sh
rg -n 'antidote' dotfiles/.zshrc
! rg -n 'oh-my-zsh' dotfiles/.zshrc
```

**Step 2: Run test to verify it fails**

Run: `rg -n 'antidote' ../dotfiles/.zshrc && ! rg -n 'oh-my-zsh' ../dotfiles/.zshrc`
Expected: FAIL until the managed shell config is fully migrated.

**Step 3: Write minimal implementation**

- Ensure `.zshrc` bootstraps `antidote` and loads plugins from `dotfiles/.zsh_plugins.txt`.
- Ensure the prompt setup still uses `pure`.
- Add README migration notes for:
  - first bootstrap on a clean machine
  - re-running after config changes
  - removing or archiving `~/.oh-my-zsh`

**Step 4: Run test to verify it passes**

Run: `rg -n 'antidote' ../dotfiles/.zshrc && ! rg -n 'oh-my-zsh' ../dotfiles/.zshrc`
Expected: PASS

**Step 5: Commit**

```bash
git add ../dotfiles/.zshrc ../README.md ../scripts/tests/test_required_tools.sh
git commit -m "docs: document antidote-based zsh migration"
```

### Task 6: End-to-end verification on the current machine

**Files:**
- Modify: `README.md`
- Test: `scripts/tests/test_required_tools.sh`
- Test: `scripts/tests/test_capture_userspace.sh`

**Step 1: Write the failing test**

Create a final verification checklist in the README and add any missing assertions required to support it.

```sh
sh scripts/tests/test_required_tools.sh
sh scripts/tests/test_capture_userspace.sh
sh scripts/required_tools.sh --dry-run
```

**Step 2: Run test to verify it fails**

Run: `sh ../scripts/tests/test_required_tools.sh && sh ../scripts/tests/test_capture_userspace.sh && sh ../scripts/required_tools.sh --dry-run`
Expected: FAIL until all prior tasks are complete.

**Step 3: Write minimal implementation**

- Fill in any missing README usage notes.
- Fix any broken dry-run output, mapping paths, or capture behavior surfaced by the tests.
- Confirm bootstrap output includes install and apply actions without executing destructive changes in dry-run mode.

**Step 4: Run test to verify it passes**

Run: `sh ../scripts/tests/test_required_tools.sh && sh ../scripts/tests/test_capture_userspace.sh && sh ../scripts/required_tools.sh --dry-run`
Expected: PASS

**Step 5: Commit**

```bash
git add ../README.md ../scripts/tests/test_required_tools.sh ../scripts/tests/test_capture_userspace.sh ../scripts/required_tools.sh
git commit -m "test: verify userspace bootstrap workflow"
```

### Task 7: Add interactive provider selection, core Git setup, and optional Codex install

**Files:**
- Modify: `scripts/required_tools.sh`
- Modify: `scripts/lib/bootstrap_common.sh`
- Modify: `scripts/tests/test_required_tools.sh`
- Modify: `README.md`

**Step 1: Write the failing test**

Extend the shell test to assert:
- interactive mode offers Homebrew vs ZeroBrew selection
- unattended mode defaults to Homebrew and skips optional installs
- Git setup runs as part of core bootstrap
- optional Codex CLI install can be selected interactively
- SSH multiplexing directory/config remain part of the applied setup

```sh
printf '2\ny\n' | sh scripts/required_tools.sh --dry-run
```

Expected assertions:
- output contains `provider: zerobrew`
- output contains `optional-codex: yes`
- output contains Git setup actions
- output still maps `~/.ssh/config` and `~/.ssh/control`

**Step 2: Run test to verify it fails**

Run: `sh ../scripts/tests/test_required_tools.sh`
Expected: FAIL because the current bootstrap has no interactive provider menu, no ZeroBrew branch, no optional Codex selection, and no explicit Git setup phase.

**Step 3: Write minimal implementation**

- Add an interactive prompt flow in `scripts/required_tools.sh` when stdin/stdout are attached to a TTY.
- Default unattended runs to Homebrew on macOS and native Linux managers on Linux, while skipping optional installs.
- Add provider helpers in `scripts/lib/bootstrap_common.sh` for detecting/bootstrapping ZeroBrew alongside Homebrew.
- Add a core Git setup step that:
  - ensures Git is installed through the chosen provider when possible
  - applies managed `.gitconfig`
  - sets safe Git defaults such as default branch and credential helper when supported
- Add an optional Codex install path selected from the interactive menu.
- Keep SSH multiplexing setup in the core flow by always creating `~/.ssh/control` and applying managed SSH config.
- Update README usage to describe the interactive choices and unattended defaults.

**Step 4: Run test to verify it passes**

Run: `sh ../scripts/tests/test_required_tools.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add ../scripts/required_tools.sh ../scripts/lib/bootstrap_common.sh ../scripts/tests/test_required_tools.sh ../README.md
git commit -m "feat: add interactive provider and git setup flow"
```
