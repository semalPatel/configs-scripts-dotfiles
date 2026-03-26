# Userspace Bootstrap Design

## Goal
Create a portable machine bootstrap workflow that can recreate the current userspace setup on a new Unix machine by running a repo-managed script, without depending on absolute paths from the source machine.

## Scope
- Turn `scripts/required_tools.sh` into a cross-platform bootstrap entrypoint.
- Detect `macOS` and common Linux package managers and install a curated toolset.
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
2. Detect platform and package manager.
3. Install base packages and platform-specific packages.
4. Install the selected zsh plugin manager if needed.
5. Create destination directories in the target home directory.
6. Symlink or copy repo-managed config into target locations.
7. Print post-install manual notes for anything intentionally excluded.

### 3. Config Application Model
Use a declarative mapping in the script for repo-relative source paths to target home-relative destinations. The script should:
- create parents as needed
- back up existing unmanaged files once
- install links by default
- support a copy mode if symlinks are undesirable on a target machine

### 4. Identity and Safety Model
- Include Git `user.name` and `user.email` in managed config.
- Include safe SSH config structure and host aliases.
- Exclude `~/.ssh/id_*`, agent sockets, tokens, and app credentials.
- Replace source-machine includes such as the Colima SSH include with conditional or portable alternatives.

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
- Verify generated links and expected file targets under `$HOME`.
- Verify zsh startup on a clean shell.
- Verify package installation branch selection on macOS and at least one Linux path.
