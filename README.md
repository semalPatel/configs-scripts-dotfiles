# dot-files-scripts
Collection of scripts as well some config files for repetitive tasks. This is a continuous list.

##### Userspace Bootstrap Inventory

Portable machine bootstrap manifests now live under `configs/`:
- `configs/Brewfile` for macOS/Homebrew
- `configs/packages/*.txt` for best-effort Linux package mappings

Shared bootstrap shell helpers live in `scripts/lib/bootstrap_common.sh`.

Bootstrap a machine from this repo with:

```bash
sh scripts/required_tools.sh --dry-run
sh scripts/required_tools.sh --apply
```

Use `--copy` if you want managed files copied into place instead of symlinked.

##### Zsh Migration

The managed shell setup now uses `plain zsh + antidote` instead of `oh-my-zsh`.

- `dotfiles/.zshrc` loads `antidote` and the plugin list from `dotfiles/.zsh_plugins.txt`
- the prompt is provided by `pure`
- managed config should not reference `~/.oh-my-zsh`

If an older machine still has `~/.oh-my-zsh`, you can leave it in place during migration, then remove or archive it after confirming the new managed `~/.zshrc` starts cleanly.

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
