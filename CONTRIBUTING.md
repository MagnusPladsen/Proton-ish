# Contributing to Proton-ish

Proton-ish is a fork of [NotProton](https://github.com/NotProtonNot/NotProton) that adds free Wine
runtimes (Highball first) next to CrossOver. Contributions are welcome here. Please do not send
Proton-ish changes or non-CrossOver issues to the upstream NotProton project, which does not accept them.

## Guidelines

1. Write pull request descriptions by hand where you can. Short and clear beats long.
2. Check closed PRs and issues before starting, to avoid duplicate work.
3. Keep upstream merges cheap. Do not rename internal identifiers: Swift module names (`NotProtonApp`),
   `np_`/`NP_` C symbols, `NOTPROTON_*` environment variables, and prefix marker files (`notproton-build`,
   `*.notproton-orig`, `notproton-template`, lock files).
4. Keep `make brandcheck` clean, and run the full check before opening a PR (see "Building from source"
   in README.md).
5. Comment style: short comments where the logic is complex, written for a human reader.
6. Code that runs inside Steam (the dylib), the run script and lsteamclient interact in subtle ways.
   Think about multiple Steam accounts, multiple libraries, multiple macOS users and different file
   systems before changing them.
7. Every change that affects users gets a dated line under "Changes from upstream" in README.md.

Upstream's own contribution guidelines, which much of the above is based on, are at
https://github.com/NotProtonNot/NotProton/blob/main/CONTRIBUTING.md.
