# Developing Proton-ish

## Building from source

- Xcode 27 (the same toolchain upstream CI uses); older Xcode versions fail to type-check the app.
- `brew install shellcheck node` for the lint and panel checks.
- `make dobby && make all && make app-tests` builds the dylib and runs the Swift tests;
  `make bridge fonts app` builds the full `out/Proton-ish.app` (the bridge step compiles a Wine tree and takes a while).
- `make brandcheck` must stay clean: it fails if an upstream NotProton identifier slips back in.

## Source layout

- `app/`: the macOS app (SwiftUI) that sets everything up.
- `dylib/`: the code injected into Steam that enables Steam Play and adds the compatibility tools.
- `lsteamclient/`: Valve's lsteamclient, ported to macOS, so Windows games can talk to the macOS Steam client.
- `steam-shim/`: Valve's steam_helper from Proton 9.0, ported.
- `ntdll-patch/`: patches each runner's copy of Wine (in `~/Library/Application Support/protonish/runners/`) so it
  loads lsteamclient.

## Maintenance

A workflow every three hours (`.github/workflows/upstream-sync.yml`, also on demand under Actions) keeps the fork
current:

- **NotProton:** a new upstream commit becomes a PR that merges it into main, or an issue listing the conflicting
  files when the merge is not clean. The fork's own README always wins (`.gitattributes`, `merge=ours`), so an
  upstream README edit never blocks a merge.
- **Highball:** a new Highball release bumps the HighballKit pin, and a new highball-db commit refreshes the bundled
  snapshot, in one PR.
- **Highball engines:** a new engine revision that reuses a Wine build Proton-ish supports is pinned in the Highball
  PR (`scripts/sync/pin-engines.sh`) and becomes the engine Proton-ish downloads, unless it needs a newer macOS than
  Proton-ish does. A new Wine build becomes an issue with the steps to support it.

A sync PR bumps `dylib/version.h` to the next beta (or the next patch after 1.0), adds its dated line to CHANGELOG.md's
"Changes from upstream", and merges itself once the required checks pass; the merge publishes the release, so the
app updates through Sparkle without anyone pressing a button. A merge with conflicts stays with a person: merge by
hand on a branch, run `scripts/sync/bump-release.sh "NotProton <sha> merged"`, open the PR. The workflow needs a
repository secret `SYNC_TOKEN`: a fine-grained GitHub token for this repository only, with Contents, Pull requests,
Issues and Workflows set to read and write, so that CI runs on the PRs it opens. When the token expires the workflow
skips with a notice until it is renewed. Run the scripts' tests with `make synccheck`.
