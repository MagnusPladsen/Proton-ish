#!/bin/sh
# Pins Highball engine revisions that reuse a Wine build Proton-ish already supports: same
# launcher and ntdll bytes, so the pinned hashes and patches carry over and only the id is new.
# Edits the Makefile, SupportedRunner.swift and NtdllPatcher.swift in place and prints one line
# per revision newer than the pinned ones on their engine line:
#   pinned <id> like <pinned id>[, needs macOS <version>]
#   unknown <id> <Wine download URL>   (a new Wine build: hashes and patches are manual work)
# A revision that runs on Proton-ish's minimum macOS becomes the engine it downloads; one that
# needs a newer macOS goes in before that one. --dry-run prints the same lines and edits nothing.
# Usage: scripts/sync/pin-engines.sh [--dry-run] <directory of Highball engine manifests>
set -eu
cd "$(dirname "$0")/../.."
exec python3 -I scripts/sync/engine_pins.py pin "$@"
