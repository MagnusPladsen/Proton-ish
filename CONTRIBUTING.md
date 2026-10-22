# Contributing to Proton-ish

Proton-ish is a fork of [NotProton](https://github.com/NotProtonNot/NotProton) that adds free Wine
runtimes (Highball first) next to CrossOver. Contributions are welcome here. Please do not send
Proton-ish changes or non-CrossOver issues to the upstream NotProton project, which does not accept them.

## Branches and releases

- Work on a branch, never directly on `main`.
- Open a pull request into `main`. Merging it is what ships: when the merge bumps the version in
  `dylib/version.h`, the release workflow builds, signs the update feed and publishes the release.
  A merge without a version bump releases nothing.
- The pull request description becomes the release notes, so write it for players.
- A version with a suffix (`0.1.0-beta.3`) is published as a pre-release.
- The release also bumps the `proton-ish` cask in [MagnusPladsen/homebrew-tap](https://github.com/MagnusPladsen/homebrew-tap) (needs the `TAP_TOKEN` secret).

## Guidelines

1. Write pull request descriptions by hand where you can. Short and clear beats long.
2. Check closed PRs and issues before starting, to avoid duplicate work.
3. Keep upstream merges cheap. Do not rename internal identifiers: Swift module names (`NotProtonApp`),
   `np_`/`NP_` C symbols, `NOTPROTON_*` environment variables, and prefix marker files (`notproton-build`,
   `*.notproton-orig`, `notproton-template`, lock files).
4. Keep `make brandcheck` clean, and run the full check before opening a PR (see "Building from source"
   in docs/development.md).
5. Comment style: short comments where the logic is complex, written for a human reader.
6. Code that runs inside Steam (the dylib), the run script and lsteamclient interact in subtle ways.
   Think about multiple Steam accounts, multiple libraries, multiple macOS users and different file
   systems before changing them.
7. Every change that affects users gets a dated line under "Changes from upstream" in CHANGELOG.md.

Upstream's own contribution guidelines, which much of the above is based on, are at
https://github.com/NotProtonNot/NotProton/blob/main/CONTRIBUTING.md.
