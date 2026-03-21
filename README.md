# dot-files-scripts
Collection of scripts as well some config files for repetitive tasks. This is a continuous list.

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

Preview cleanup (default dry-run):

```bash
scripts/macos_deep_clean.sh --level heavy --with-xcode --with-node --with-python --with-homebrew --with-docker --with-system-caches --all-drives
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
