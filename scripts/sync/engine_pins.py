"""Edits Proton-ish's Highball engine pins: SupportedRunner.swift, NtdllPatcher.swift, Makefile.

Shared by pin-engines.sh (revisions on a pinned Wine build) and wine_build.py (a new Wine build).
Usage: python3 -I scripts/sync/engine_pins.py pin [--dry-run] <engine manifest directory>
Run from the repository root.
"""
import json
import pathlib
import re
import sys

MAKEFILE = pathlib.Path("Makefile")
PACKAGE = pathlib.Path("app/Package.swift")
RUNNER = pathlib.Path("app/Sources/NotProtonApp/Model/SupportedRunner.swift")
PATCHER = pathlib.Path("app/Sources/NotProtonApp/Model/NtdllPatcher.swift")
ARCH_KEYS = {"x86_64-windows": "x86_64Windows", "i386-windows": "i386Windows"}


def revision(engine):
    return int(re.search(r"-r(\d+)$", engine)[1])


def line(engine):
    return re.sub(r"-r\d+$", "", engine)


def version(text):
    return tuple(int(part) for part in text.split("."))


def pinned_engines(makefile_text):
    return re.search(r"^HIGHBALL_ENGINES := (.*)$", makefile_text, re.M)[1].split()


def app_minimum_macos(package_swift_text):
    return re.search(r'platforms: \[\.macOS\("([\d.]+)"\)\]', package_swift_text)[1]


def needs_newer_macos(manifest, minimum):
    return version(manifest["minMacOS"]) > version(minimum)


def runner_block(runner_text, engine):
    return re.search(r'^        RunnerBuild\(\n            bundleVersion: "%s",\n.*?\n        \),\n' % re.escape(engine),
                     runner_text, re.M | re.S)


def tool_display(source_display, engine, manifest_display):
    display = source_display[:source_display.index("(") + 1] + f"r{revision(engine)}"
    if ", " in manifest_display:
        display += ", " + manifest_display.split(", ", 1)[1]
    return display + ")"


def _set_hashes(block, hashes):
    block = re.sub(r'loaderSHA256: "[0-9a-f]*"', f'loaderSHA256: "{hashes["loader"]}"', block)
    for section, key in (("cleanNtdll", "clean"), ("patchedNtdll", "patched")):
        def replace(found):
            text = found[0]
            for arch, swift in ARCH_KEYS.items():
                text = re.sub(r'\.%s: "[0-9a-f]*"' % swift, f'.{swift}: "{hashes[key][arch]}"', text)
            return text
        block = re.sub(r"%s: \[\n.*?\n            \]," % section, replace, block, flags=re.S)
    return block


def add_runner_build(runner_text, source, engine, display, needs_newer, hashes=None):
    entry = runner_block(runner_text, source)
    if not entry:
        return None
    copy = entry[0].replace(source, engine)
    copy = re.sub(r'releaseVersion: "[^"]*"', f'releaseVersion: "r{revision(engine)}"', copy)
    copy = re.sub(r'display: "[^"]*"', f'display: "{display}"', copy)
    if hashes:
        copy = _set_hashes(copy, hashes)
        note = f"{engine} has its own Wine build, patched like {source}"
    else:
        note = f"{engine} ships {source}'s Wine build"
    copy = f"        // {note}; pinned by scripts/sync/{'wine_build.py' if hashes else 'pin-engines.sh'}\n" + copy

    start = runner_text.index("    static let all: [RunnerBuild] = [\n")
    end = runner_text.index("\n    ]\n", start) + 1
    at = end
    if needs_newer:
        # Before the build Proton-ish downloads, the last Highball entry, and its comment
        download = list(re.finditer(r"^(?:        //.*\n)*        RunnerBuild\(\n(?:(?!        \),\n).*\n)*?            runtime: \.highball\n        \),\n",
                                    runner_text[start:end], re.M))[-1]
        at = start + download.start()
    return runner_text[:at] + copy + runner_text[at:]


def add_patch_entry(patcher_text, source, engine, table=None):
    found = re.search(r'^        "%s": (\w+),\n' % re.escape(source), patcher_text, re.M)
    if not found:
        return None
    return patcher_text[:found.end()] + f'        "{engine}": {table or found[1]},\n' + patcher_text[found.end():]


def add_bundled_engine(makefile_text, engine):
    found = re.search(r"^HIGHBALL_ENGINES := .*$", makefile_text, re.M)
    return makefile_text[:found.end()] + " " + engine + makefile_text[found.end():]


def pin(manifests, dry_run):
    """Pins revisions newer than the pinned ones whose Wine download matches a pinned build."""
    def manifest(engine):
        path = manifests / f"{engine}.json"
        if not path.is_file():
            sys.exit(f"pin-engines: {path} is missing, but the Makefile bundles {engine}")
        return json.loads(path.read_text())

    makefile_text, runner_text, patcher_text = MAKEFILE.read_text(), RUNNER.read_text(), PATCHER.read_text()
    pinned = pinned_engines(makefile_text)
    minimum = app_minimum_macos(PACKAGE.read_text())

    # The newest pinned revision of each Wine build, keyed by the Wine download's hash
    by_wine, newest = {}, {}
    for engine in sorted(pinned, key=revision):
        by_wine[manifest(engine)["components"]["wine"]["sha256"]] = engine
        newest[line(engine)] = revision(engine)
    candidates = sorted(
        (path.stem for path in manifests.glob("*.json")
         if re.search(r"-r\d+$", path.stem) and newest.get(line(path.stem), 1 << 30) < revision(path.stem)),
        key=revision)

    for engine in candidates:
        data = manifest(engine)
        wine = data["components"]["wine"]
        source = by_wine.get(wine["sha256"])
        entry = source and runner_block(runner_text, source)
        newer = needs_newer_macos(data, minimum)
        runner = entry and add_runner_build(
            runner_text, source, engine,
            tool_display(re.search(r'display: "([^"]*)"', entry[0])[1], engine, data["displayName"]), newer)
        patcher = runner and add_patch_entry(patcher_text, source, engine)
        if not patcher:
            print(f"unknown {engine} {wine.get('url', '')}")
            continue
        runner_text, patcher_text = runner, patcher
        makefile_text = add_bundled_engine(makefile_text, engine)
        by_wine[wine["sha256"]] = engine
        print(f"pinned {engine} like {source}" + (f", needs macOS {data['minMacOS']}" if newer else ""))

    if not dry_run and makefile_text != MAKEFILE.read_text():
        RUNNER.write_text(runner_text)
        PATCHER.write_text(patcher_text)
        MAKEFILE.write_text(makefile_text)


if __name__ == "__main__":
    args = sys.argv[1:]
    dry_run = args[1:2] == ["--dry-run"]
    if dry_run:
        del args[1]
    if len(args) != 2 or args[0] != "pin":
        sys.exit(f"usage: {sys.argv[0]} pin [--dry-run] <engine manifest directory>")
    pin(pathlib.Path(args[1]), dry_run)
