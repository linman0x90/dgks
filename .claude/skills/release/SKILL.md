---
name: release
description: Release a new version of dG KillShot - draft player-facing release notes from the changes since the last tag, get them approved, then tag main, publish the GitHub release, and confirm the CurseForge build and package. Use when the user asks to release, ship, tag or publish a version (e.g. "release 12.0.011", "cut a release").
---

# Release dG KillShot

The mechanical steps live in `tools/release.sh`. This skill adds the part that needs judgment: the release notes, and the user's approval of them before anything is published.

## 1. Version

- Use the version the user names. If none, take the latest tag (`git describe --tags --abbrev=0`) and add one to the last part (12.0.010 -> 12.0.011), and say so.
- Releases come from `main`. If the repo is on another branch, has uncommitted changes, or is behind `origin/main`, tell the user and stop; don't switch branches, stash or pull without asking.

## 2. Draft the notes

- List the changes: `git log --oneline --no-merges <prev>..main`, and for merged PRs read their bodies (`gh pr view <n> --json title,body`). On this machine, call gh as `"/c/Program Files/GitHub CLI/gh.exe"` from Bash.
- Read the previous release's notes for tone and layout: `gh release view <prev> --json body`.
- Write for players, not developers:
  - Open with one or two sentences summing up the release.
  - Then `##` sections as needed (new features by name, `## Fixes`, `## Other`). Bullets, plain words, what changes for the player.
  - No code names, file names, commit hashes, test counts or internal function names.
  - Mention a trade-off or behaviour change players would notice.
- Leave out the title line; the script sets the release title to "dG KillShot <version>".
- Save to the session scratchpad as `release-<version>.md`, show the notes to the user in full, and say which changes have not been checked in game.

## 3. Approval

Publishing a tag and release is outward-facing and starts the CurseForge build that players download. Do not run the script until the user approves the notes in this conversation. Apply any edits they ask for and show the result again.

## 4. Release

Run from the repo root, in the background (`run_in_background`), since it waits up to 30 minutes for CurseForge (new files can take 20 minutes or more to show in its public list, probably while CurseForge reviews them):

```bash
bash tools/release.sh <version> "<scratchpad>/release-<version>.md"
```

Run it exactly like that: no pipe into `grep`, `tail` or the like. A pipe replaces the script's exit code with the last command's, so a failed release looks like a success. The script already drops Git for Windows' "credential-manager" noise itself.

Exit codes:
- `0`: released, and the CurseForge package passed the check.
- `1`: stopped before publishing anything (wrong branch, uncommitted changes, failing tests and so on), or the tag push or the GitHub release failed. The message says which.
- `2`: published on GitHub, but no CurseForge file appeared within 30 minutes.
- `3`: the CurseForge package was found but failed the check (or could not be downloaded).

The script:
1. Checks it is on a clean `main` that matches `origin/main`, the tag is new, and there are commits since the last tag.
2. Runs `python tests/run_all.py` and stops on a failure.
3. Creates a lightweight tag and pushes it (this fires the CurseForge webhook).
4. Creates the GitHub release with the notes (stripping a UTF-8 BOM).
5. Waits for the CurseForge file for this version.
6. Downloads the package to a temp folder and checks it has no `tests/`, `tools/`, `.claude/` or `.vscode/`, that `dgks.toc` has the right version and that debug blocks are commented out; then deletes the download.

On exit code 2, check that the webhook reached CurseForge, without printing its URL (it holds the token): `gh api repos/linman0x90/dgks/hooks/<id>/deliveries --jq '.[] | {delivered_at, status_code}'`. A 200 means CurseForge got the push, so the build is queued, held for review or failed on CurseForge's side; the user can see which on the project's Files page. Rerun only the wait and check later with `bash tools/release.sh --check <version>` (same exit codes; `RELEASE_WAIT_SECONDS` changes the wait). Do not delete or move a pushed tag without the user's say-so.

## 5. Report

Tell the user: the tag and the commit it points at, the release URL (`https://github.com/linman0x90/dgks/releases/tag/<version>`), the CurseForge file id, and the package check result. If any step failed, say which and what was left done or undone.

Never print or search for the CurseForge webhook token; the script does not need it.
