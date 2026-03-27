# Userspace Bootstrap Design

## Goal
Create a portable machine bootstrap workflow that can recreate the current userspace setup on a new Unix machine by running a repo-managed script, without depending on absolute paths from the source machine.

## Scope
- Turn `scripts/required_tools.sh` into a cross-platform bootstrap entrypoint.
- Detect `macOS` and common Linux package managers and install a curated toolset.
- Provide an interactive installer menu for package-provider and optional tool choices.
- Capture portable shell, git, SSH, and app config into repo-managed files.
- Apply repo-managed config to home-relative and XDG-relative destinations.
- Preserve safe personal identity config such as Git user identity and non-secret SSH config.
- Evaluate and standardize on a lighter `oh-my-zsh` replacement.

## Constraints
- No machine-specific absolute paths in managed config.
- No secrets, tokens, or private keys committed to the repo.
- No attempt to replicate opaque or brittle OS preference state.
- Prefer idempotent operations so the script can be re-run safely.
- Linux support is best-effort when package names or GUI apps differ by distro.

## Current State Summary
- Package management is primarily driven by Homebrew on the current machine.
- Active shell setup uses `oh-my-zsh` mainly for plugin loading while the prompt is already provided by `pure`.
- Safe portable config currently exists mostly in `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.gitconfig`, and `~/.ssh/config`.
- Terminal app presence exists through Homebrew casks such as `alacritty` and `ghostty`, but current Ghostty config is still the stock template.

## Recommended Architecture

### 1. Repo as Source of Truth
Store portable configuration in the repo rather than reading directly from the current machine at bootstrap time.

Suggested layout:
- `scripts/required_tools.sh`: entrypoint for installation and apply workflow
- `configs/Brewfile`: canonical Homebrew manifest for macOS
- `configs/packages/*.txt`: optional Linux package manifests by package manager
- `dotfiles/.zshrc`
- `dotfiles/.zprofile`
- `dotfiles/.zshenv`
- `dotfiles/.gitconfig`
- `dotfiles/.ssh/config`
- `dotfiles/.config/...`: app and tool config as it becomes relevant
- `scripts/capture_userspace.sh`: optional helper to refresh repo-managed config from the current machine

### 2. Bootstrap Flow
`required_tools.sh` should:
1. Resolve the repo root relative to the script location.
2. Detect platform and determine whether the run is interactive.
3. When interactive, offer installer choices for package provider and optional tools.
4. When unattended, default to Homebrew on macOS and native Linux managers on Linux, while skipping optional installs.
5. Install base packages and provider-specific packages.
6. Install the selected zsh plugin manager if needed.
7. Create destination directories in the target home directory.
8. Symlink or copy repo-managed config into target locations.
9. Print post-install manual notes for anything intentionally excluded.

### 3. Config Application Model
Use a declarative mapping in the script for repo-relative source paths to target home-relative destinations. The script should:
- create parents as needed
- back up existing unmanaged files once
- install links by default
- support a copy mode if symlinks are undesirable on a target machine

### 4. Identity and Safety Model
- Include Git `user.name` and `user.email` in managed config.
- Include safe SSH config structure and host aliases.
- Include SSH multiplexing defaults and ensure the control socket directory exists.
- Exclude `~/.ssh/id_*`, agent sockets, tokens, and app credentials.
- Replace source-machine includes such as the Colima SSH include with conditional or portable alternatives.

### 5. Provider and Optional Install Model
- Treat `Homebrew` and `ZeroBrew` as peer package providers where available.
- Expose provider selection through an interactive prompt rather than a required CLI flag.
- Keep optional installs such as `Codex CLI` off by default for unattended runs.
- Make `Git` part of the core setup rather than an optional package.
- Apply additional safe Git defaults after install, such as default branch name and credential helper configuration when supported.

## Zsh Direction
Replace `oh-my-zsh` with `plain zsh + antidote`.

Rationale:
- current usage only needs lightweight plugin loading
- `pure` prompt already replaces `oh-my-zsh` themes
- `antidote` is small, static, and easy to bootstrap
- plugin needs are modest: `git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`, and prompt support

Expected shell structure:
- `.zshenv`: minimal PATH/bootstrap-only logic
- `.zprofile`: login-shell PATH additions
- `.zshrc`: completion, history, prompt, plugins, aliases, language/toolchain hooks
- plugin list stored in a simple repo-managed file or inline in `.zshrc`

## Non-Goals
- Exporting macOS `defaults` databases or plist-heavy app state.
- Replicating private SSH keys or credentials.
- Guaranteeing feature parity for every GUI application across all Linux distros.
- Capturing transient caches, histories, or machine-generated shell artifacts.

## Verification
- Run the bootstrap in dry-run and apply mode on the current machine.
- Verify interactive selection and unattended defaults both work.
- Verify generated links and expected file targets under `$HOME`.
- Verify zsh startup on a clean shell.
- Verify package installation branch selection on macOS and at least one Linux path.
- Verify Git setup and SSH multiplexing directory/config are applied.
