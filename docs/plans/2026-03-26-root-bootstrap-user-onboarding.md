# Root Bootstrap User Onboarding Implementation Plan

1. Add root onboarding helpers to `scripts/lib/bootstrap_common.sh`
   - add Linux user existence checks
   - add username validation
   - add shell selection helper

2. Add root onboarding flow to `scripts/required_tools.sh`
   - detect root before provider selection
   - Linux interactive onboarding for user creation/reuse
   - preserve script flags when rerunning as target user
   - fail early on macOS root and Linux noninteractive root

3. Add Linux root setup helpers
   - ensure `sudo` is installed
   - create user/home if needed
   - add user to `sudo`
   - rerun bootstrap via `su` or `sudo -iu`

4. Update tests in `scripts/tests/test_required_tools.sh`
   - root Linux noninteractive failure
   - root Linux interactive onboarding rerun
   - root macOS failure
   - existing-user reuse

5. Update `README.md`
   - document root behavior
   - document LXC/Linux bootstrap expectations

6. Verify and ship
   - run shell tests
   - run dry-run checks
   - commit and push
