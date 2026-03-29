# dot-files-scripts
Collection of scripts as well some config files for repetitive tasks. This is a continuous list.

##### Userspace Bootstrap

The bootstrap is meant to work as the first command you run on a fresh machine.

What it handles:
- installs a minimal base userspace on Linux/LXC and the managed tool set on macOS
- applies the managed shell, Git, and SSH config from this repo
- sets up `antidote` + `pure` for zsh
- creates `~/.ssh/control` and enables SSH multiplexing in the managed SSH config
- installs optional tools like `Codex CLI`, `Docker`, and `Podman` when you choose them interactively

The script is idempotent. Re-running it is expected and safe.

##### Quick Start

Fresh machine, normal user:

```bash
BOOTSTRAP_DIR="$(mktemp -d)" && \
curl -fsSL https://github.com/semalPatel/configs-scripts-dotfiles/archive/refs/heads/main.tar.gz | tar -xzf - -C "$BOOTSTRAP_DIR" && \
sh "$BOOTSTRAP_DIR/configs-scripts-dotfiles-main/scripts/required_tools.sh" --apply --copy
```

Fresh Linux/LXC where you only have `root`:

```bash
BOOTSTRAP_DIR="$(mktemp -d)" && \
curl -fsSL https://github.com/semalPatel/configs-scripts-dotfiles/archive/refs/heads/main.tar.gz | tar -xzf - -C "$BOOTSTRAP_DIR" && \
sh "$BOOTSTRAP_DIR/configs-scripts-dotfiles-main/scripts/required_tools.sh" --apply --copy
```

Expected root/LXC flow:
- the script creates or reuses a real non-root user
- repairs that user’s home ownership
- reruns the bootstrap as that user
- then opens a login shell as that user

If you SSH from Ghostty into a fresh remote Linux machine and the remote shell is already broken, force a safe terminal type once before bootstrap:

```bash
export TERM=xterm-256color
```

After bootstrap finishes, start a fresh login shell if the script does not already hand you one:

```bash
exec zsh -l
```

##### Install Flow

Interactive runs ask only in the user-owned bootstrap phase:
- package provider: `Homebrew`, `ZeroBrew`, or the native system package manager when supported
- optional `Codex CLI`
- optional `Docker`
- optional `Podman`

Linux and LXC default to a minimal base set. Heavy runtimes and project toolchains should be installed per project, not as part of the default machine bootstrap.

`--copy` is the recommended mode for archive-based bootstrap on a fresh machine. It copies managed files into place instead of linking them back to a temporary extracted directory.

For local repo usage:

```bash
sh scripts/required_tools.sh --dry-run
sh scripts/required_tools.sh --apply
```

##### Bootstrap Inventory

Portable machine bootstrap manifests now live under `configs/`:
- `configs/Brewfile` for macOS/Homebrew
- `configs/packages/zerobrew.txt` for the curated minimal ZeroBrew userspace set
- `configs/packages/*.txt` for best-effort Linux package mappings

Shared bootstrap shell helpers live in `scripts/lib/bootstrap_common.sh`.

Notes:
- On macOS, run the bootstrap from your normal user account, not as `root`.
- `ZeroBrew` is a userspace choice and is only offered in the user-owned bootstrap phase.
- When run unattended, the script defaults to the native Linux package manager when one is available, otherwise `Homebrew`; optional installs are skipped.
- The archive-based bootstrap flow does not require `git` to already be installed on the target machine.

##### Zsh Migration

The managed shell setup now uses `plain zsh + antidote` instead of `oh-my-zsh`.

- `dotfiles/.zshrc` loads `antidote` and the plugin list from `dotfiles/.zsh_plugins.txt`
- the prompt is provided by `pure`
- managed config should not reference `~/.oh-my-zsh`

If an older machine still has `~/.oh-my-zsh`, you can leave it in place during migration, then remove or archive it after confirming the new managed `~/.zshrc` starts cleanly.

##### Git And SSH

The bootstrap now treats Git as part of core setup:
- installs Git if needed through the selected provider
- applies the managed [`dotfiles/.gitconfig`](dotfiles/.gitconfig)
- configures safe defaults such as `init.defaultBranch`
- adds credential-helper and SSH-signing defaults when the supporting tools are present

When selected on non-Homebrew paths, `Codex CLI` is installed from the prebuilt release binary into `~/.local/bin/codex` instead of through `npm`.

The managed SSH config includes multiplexing defaults and the bootstrap always creates `~/.ssh/control`.

##### Capture Current Userspace

Use `scripts/capture_userspace.sh` to refresh the managed dotfiles from the current machine:

```bash
sh scripts/capture_userspace.sh
```

It captures only the approved files in `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.gitconfig`, and `~/.ssh/config`, normalizes home-relative paths where possible, and keeps machine-specific SSH includes commented out. For test fixtures or alternate roots, set `CAPTURE_SOURCE_HOME` and `CAPTURE_REPO_ROOT`.

##### Easily switch JDK Versions

```java
unset JAVA_HOME
export JAVA8_HOME="$(/usr/libexec/java_home -v1.8)"
export JAVA11_HOME="$(/usr/libexec/java_home -v11)"
alias jdk_11='export JAVA_HOME="$JAVA11_HOME" && export PATH="$PATH:$JAVA_HOME/bin"'
alias jdk_8='export JAVA_HOME="$JAVA8_HOME" && export PATH="$PATH:$JAVA_HOME/bin"'
# jdk_11 # Use jdk 11 as the default jdk
jdk_8  # Mobile dev still needs jdk 8 :/
```

##### macOS Deep Clean (Safe + Heavy)

Script: `scripts/macos_deep_clean.sh`

One-flag full cleanup:

```bash
sudo scripts/macos_deep_clean.sh --execute-all
```

One-flag full preview:

```bash
scripts/macos_deep_clean.sh --dry-run-all
```

Top space report:

```bash
scripts/macos_deep_clean.sh --report-top-space --top-limit 30
```

Preview cleanup (equivalent long form):

```bash
scripts/macos_deep_clean.sh --level heavy --with-xcode --with-node --with-python --with-homebrew --with-docker --with-browser-caches --with-dev-caches --with-xcode-archives --with-rosetta-cache --with-system-caches --with-local-snapshots --with-simulator-prune --all-drives
```

Apply cleanup:

```bash
sudo scripts/macos_deep_clean.sh --execute --level heavy --with-xcode --with-node --with-python --with-homebrew --with-docker --with-system-caches --all-drives
```

Safety notes:
- Only known cache/temp locations are targeted.
- Deletes contents of approved paths, not protected system roots.
- Use dry-run first to inspect estimated reclaimable size.
- `--with-system-caches` enables OS-level cache locations (`/Library`, `/private/var/*` cache/log/temp targets).
- `--all-drives` extends OS-level cache targets to mounted volumes in `/Volumes/*`.
- `--with-dev-caches` includes Gradle/Maven/Ivy/Cargo/Composer/Playwright/Cypress cache locations.
- `--with-browser-caches` includes Safari/Chrome/Firefox and containerized app cache locations.
