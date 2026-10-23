# Proton-ish

## Keep the website in step

The website at https://proton-ish.pladsen.dev lives in its own repo, `MagnusPladsen/proton-ish-site`
(React, Vite, Tailwind, shadcn). It retells what this repo says, so it goes stale whenever the two drift.

When a change here alters anything a user reads, update the site in the same piece of work, as its own commit
or PR in `proton-ish-site`:

- **README, `docs/using-proton-ish.md`, CHANGELOG highlights:** features, requirements (macOS version, Apple
  silicon, Rosetta, CrossOver), install steps, Homebrew command, FAQ answers, known limits. These map to the
  site's sections in `src/components/sections/` (`features`, `how-it-works`, `engines`, `install`, `faq`,
  `games`, `hero`).
- **Links:** repo, releases, Homebrew tap, Highball and highball-db URLs live in the site's `src/lib/links.ts`.
- **App icon** (`helpers/icon.swift`): mirror the geometry and colours in the site's `scripts/app-icon.py`, run it,
  and refresh `public/favicon.svg` and `public/apple-touch-icon.png` from the new `public/app-icon.svg`.
- **App screens:** when the Status, Compatibility or game screens change visibly, refresh `public/screens/`.

If the site doesn't need a change, say so in the PR body so the check is visible.
