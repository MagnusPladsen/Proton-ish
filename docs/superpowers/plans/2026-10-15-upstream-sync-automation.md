# Upstream Sync Automation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When NotProton or Highball changes, Proton-ish gets a ready-to-merge pull request (or, when a human is needed, an issue) without anyone watching those repos. Merging stays the one manual step, because merging is what ships.

**Architecture:** One scheduled GitHub Actions workflow, `.github/workflows/upstream-sync.yml` (daily plus `workflow_dispatch`), with three independent jobs. Each job is idempotent: it names its branch after the upstream version it brings in and does nothing if that branch, PR or issue already exists. PRs run the normal `app.yml` and `lint.yml` checks. Nothing auto-merges.

**Tech Stack:** GitHub Actions, `gh`, git, POSIX sh, SwiftPM.

**Depends on:** M2b Task 1 (the HighballKit pin) and Task 4 (`scripts/refresh-highball-db.sh`) for job 2. Job 1 and job 3 can land first.

## Global Constraints

- **Token:** PRs opened with the default `GITHUB_TOKEN` do not trigger other workflows, so CI would never run on them. Use a fine-grained PAT secret `SYNC_TOKEN` scoped to `MagnusPladsen/Proton-ish` only: Contents read/write, Pull requests read/write, Issues read/write, Workflows read/write (a NotProton merge can touch `.github/workflows`). The user creates it; values never enter chat or the repo.
- **Never** open PRs or issues on NotProtonNot/NotProton or on Highball's repos. Read-only access to them.
- **Git identity for bot commits:** `Proton-ish sync <93226629+MagnusPladsen@users.noreply.github.com>` as committer, so no work address lands in history.
- **No version bumps.** Sync PRs never touch `dylib/version.h`; a release happens when the user merges a version bump (existing flow). Each sync PR body says so.
- **Labels:** `upstream-sync` on every PR/issue the workflow opens, plus `notproton`, `highball` or `highball-engine`.
- Shellcheck-clean scripts in `scripts/sync/`, called from the workflow, so they can be run locally too.

## Jobs

| Job | Watches | Opens |
|---|---|---|
| 1. NotProton | `NotProtonNot/NotProton` `main` | PR `sync/notproton-<short sha>` merging upstream into `main`; on conflicts, an issue listing the conflicting files instead |
| 2. Highball | latest non-pre-release tag of `gauthierpiarrette/highball`; head of `gauthierpiarrette/highball-db` `main` | PR `sync/highball-<tag>` bumping the HighballKit pin; PR `sync/highball-db-<short sha>` refreshing the snapshot (one PR if both changed) |
| 3. Highball engines | releases of `gauthierpiarrette/highball-engine` with tag prefix `engine-wine-` | issue "New Highball engine <tag>" (a new engine needs payload pins and a supported-runner entry, which is manual work) |

## Review Focus

1. **Conflicts merged blindly** — job 1 must never commit conflict markers or resolve conflicts automatically. Pinned by a script test with a conflicting fixture repo (Task 1).
2. **Brand regressions** — upstream text reintroducing NotProton identifiers. `make brandcheck` runs in CI on the PR (already part of the checks; confirm in Task 1).
3. **Duplicate PRs/issues every day** — pinned by running each script twice against the same upstream state (Tasks 1–3).
4. **Pre-release Highball tags** — job 2 must skip pre-releases (Highball tags most builds as beta). Pinned by a script test with a fake release list (Task 2).

---

### Task 0: Token and labels (user)

- [ ] User creates the `SYNC_TOKEN` PAT (scopes above, 1-year expiry, calendar reminder) and runs `! gh secret set SYNC_TOKEN -R MagnusPladsen/Proton-ish`, pasting from the clipboard.
- [ ] Create the labels with `gh label create`.

### Task 1: NotProton job

- [ ] `scripts/sync/notproton.sh`: fetch upstream; exit 0 if `upstream/main` is an ancestor of `origin/main`; skip if branch `sync/notproton-<sha>` exists remotely or an open `upstream-sync` issue names that sha; else branch from `origin/main`, `git merge --no-ff upstream/main -m "Merge NotProton <sha>"`. Clean → push, `gh pr create` with the upstream commit list (`git log --oneline origin/main..upstream/main`) and a "check the README changelog line" reminder. Conflicts → `git merge --abort`, open an issue listing `git diff --name-only --diff-filter=U` and the upstream commits.
- [ ] Test script `scripts/sync/test-notproton.sh` with local fixture repos (clean merge, conflict, already merged, run twice); `gh` replaced by a stub that records calls.
- [ ] Workflow job 1. Commit (after approval).
- [ ] First real run: today upstream has one new commit (`dae593c`, "Fix output logging bug that broke games that run in a Windows console"), so the first run should open a PR.

### Task 2: Highball job

- [ ] `scripts/sync/highball.sh`: latest non-pre-release tag (`gh release list -R gauthierpiarrette/highball --exclude-pre-releases -L 1`); compare with the `exact:` pin in `app/Package.swift`; if newer, edit the pin, `swift package resolve --package-path app`, open the PR with a link to Highball's release notes. highball-db: compare `main`'s head with `Resources/highball-db/SOURCE`; if newer, run `scripts/refresh-highball-db.sh <sha>`. Both in one branch when both changed.
- [ ] Test with stubbed `gh` and a fake release list (pre-release newest, nothing new, both new, run twice).
- [ ] Workflow job 2 (needs a macOS runner for `swift package resolve`). Commit (after approval).

### Task 3: Highball engine job

- [ ] `scripts/sync/highball-engine.sh`: list `highball-engine` releases with the `engine-wine-` prefix; for each newer than the newest one Proton-ish knows (recorded in `scripts/sync/known-highball-engine`), open an issue unless one with that tag exists. The issue body lists what a new engine needs: payload hashes, detour payloads, `SupportedRunner` entry, E2E test.
- [ ] Test with stubbed `gh`. Workflow job 3. Commit (after approval).

### Task 4: Docs

- [ ] README "Building from source" or a new "Maintenance" section: what the sync workflow does, the `SYNC_TOKEN` secret and its renewal, and that sync PRs never release by themselves. Changelog line.
- [ ] `.claude/TODO.md`: add the `SYNC_TOKEN` renewal date.
