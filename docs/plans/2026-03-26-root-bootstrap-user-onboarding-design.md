# Root Bootstrap User Onboarding Design

## Goal

Make `scripts/required_tools.sh` behave correctly when launched as `uid 0` on a fresh Linux system, especially rootful LXCs. The bootstrap should stop treating `/root` as the target userspace, offer to create a real non-root user interactively, add that user to `sudo`, and rerun the userspace bootstrap under that account.

## Scope

In scope:
- Linux `uid 0` detection
- Interactive onboarding flow for creating a non-root bootstrap user
- Installing `sudo` if missing on Linux
- Adding the created user to the `sudo` group automatically
- Rerunning the bootstrap under the created user
- Clear messaging about shell/session behavior after handoff
- Tests for the root onboarding path

Out of scope:
- macOS user creation
- full account hardening
- SSH key provisioning
- passwordless sudo setup

## Approach

When `required_tools.sh` starts as `uid 0`, it should enter a dedicated root onboarding flow before package-provider prompts. This keeps the bootstrap aligned with its real purpose: setting up a user-owned shell, config, and toolchain.

On Linux:
- explain that the bootstrap is userspace-oriented
- offer to create a non-root user now
- collect a username interactively
- ensure `sudo` exists
- create the user with a home directory
- add the user to the `sudo` group
- choose an initial shell for the user (`zsh` if already available, else `/bin/bash`, else `/bin/sh`)
- rerun the same bootstrap script as that user using the same repo path

On macOS:
- fail early and instruct the operator to run the bootstrap from their normal user account

## Behavior Details

### Root Detection

`bootstrap_is_root()` remains the source of truth. If true:
- Linux enters root onboarding
- macOS exits with a clear error

### User Creation Flow

The Linux root flow should ask one question at a time:
- whether to create a bootstrap user
- desired username

Validation should reject:
- empty usernames
- usernames with unsafe characters
- already-existing users unless the operator confirms reuse

If the user already exists, the script should:
- ensure the account has a home directory
- ensure `sudo` group membership
- reuse that account for the rerun

### Rerun Model

The script should rerun itself as the created user with:
- the same script path
- the same repo root
- `--apply` or `--dry-run` and `--copy` preserved

It should not try to preserve interactive answers from the root flow. The user-owned run should ask provider and optional-install questions normally.

### PATH and Shell Expectations

The bootstrap cannot mutate the caller’s current shell environment after the process exits. Completion messaging should remain explicit:
- the userspace bootstrap was rerun under the target user
- start a new login shell for that user with `su - <user>` or `sudo -iu <user>`
- then run `exec zsh -l` if needed

## Error Handling

- If `sudo` installation fails, stop with a clear error
- If user creation fails, stop with a clear error
- If rerunning as the target user fails, stop and report the exact handoff command to run manually
- If the flow is noninteractive and root on Linux, fail with a message that a non-root user must be created first

## Testing

Add shell tests covering:
- Linux root noninteractive failure
- Linux root interactive user creation path
- Linux root existing-user reuse path
- macOS root early failure
- rerun command generation and preserved script flags
