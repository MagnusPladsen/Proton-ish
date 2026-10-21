#!/bin/sh
# Pins Highball engine revisions that reuse a Wine build Proton-ish already supports: same
# launcher and ntdll bytes, so the pinned hashes and patches carry over and only the id is new.
# Edits the Makefile, SupportedRunner.swift and NtdllPatcher.swift in place and prints one line
# per revision newer than the pinned ones on their engine line:
#   pinned <id> like <pinned id>[, needs macOS <version>]
#   unknown <id> <Wine download URL>   (a new Wine build: hashes and patches are manual work)
# A revision that runs on Proton-ish's minimum macOS becomes the engine it downloads; one that
# needs a newer macOS goes in before that one.
# Usage: scripts/sync/pin-engines.sh <directory of Highball engine manifests>
set -eu
cd "$(dirname "$0")/../.."
[ $# -eq 1 ] || { echo "usage: $0 <engine manifest directory>" >&2; exit 2; }

exec python3 -I - "$1" <<'EOF'
import json, pathlib, re, sys

manifests = pathlib.Path(sys.argv[1])
makefile = pathlib.Path("Makefile")
runner = pathlib.Path("app/Sources/NotProtonApp/Model/SupportedRunner.swift")
patcher = pathlib.Path("app/Sources/NotProtonApp/Model/NtdllPatcher.swift")

def revision(engine): return int(re.search(r"-r(\d+)$", engine)[1])
def line(engine): return re.sub(r"-r\d+$", "", engine)
def version(text): return tuple(int(part) for part in text.split("."))
def manifest(engine):
    path = manifests / f"{engine}.json"
    if not path.is_file():
        sys.exit(f"pin-engines: {path} is missing, but the Makefile bundles {engine}")
    return json.loads(path.read_text())

engines_line = re.search(r"^HIGHBALL_ENGINES := (.*)$", makefile.read_text(), re.M)
pinned = engines_line[1].split()
minimum = re.search(r'platforms: \[\.macOS\("([\d.]+)"\)\]', pathlib.Path("app/Package.swift").read_text())[1]

# The newest pinned revision of each Wine build, keyed by the Wine download's hash
by_wine = {}
newest = {}
for engine in sorted(pinned, key=revision):
    by_wine[manifest(engine)["components"]["wine"]["sha256"]] = engine
    newest[line(engine)] = revision(engine)

candidates = sorted(
    (path.stem for path in manifests.glob("*.json")
     if re.search(r"-r\d+$", path.stem) and newest.get(line(path.stem), 1 << 30) < revision(path.stem)),
    key=revision)

runner_text = runner.read_text()
patcher_text = patcher.read_text()

def block(text, engine):
    found = re.search(r'^        RunnerBuild\(\n            bundleVersion: "%s",\n.*?\n        \),\n' % re.escape(engine),
                      text, re.M | re.S)
    return found

def pin(source, engine, data):
    global runner_text, patcher_text
    table = re.search(r'^        "%s": (\w+),\n' % re.escape(source), patcher_text, re.M)
    entry = block(runner_text, source)
    if not table or not entry:
        return False
    display = re.search(r'display: "([^"(]*\()', entry[0])[1] + f"r{revision(engine)}"
    if ", " in data["displayName"]:
        display += ", " + data["displayName"].split(", ", 1)[1]
    copy = entry[0].replace(source, engine)
    copy = re.sub(r'releaseVersion: "[^"]*"', f'releaseVersion: "r{revision(engine)}"', copy)
    copy = re.sub(r'display: "[^"]*"', f'display: "{display})"', copy)
    copy = f"        // {engine} ships {source}'s Wine build; pinned by scripts/sync/pin-engines.sh\n" + copy

    start = runner_text.index("    static let all: [RunnerBuild] = [\n")
    end = runner_text.index("\n    ]\n", start) + 1
    if version(data["minMacOS"]) <= version(minimum):
        at = end
    else:
        # Before the build Proton-ish downloads, the last Highball entry, and its comment
        download = list(re.finditer(r"^(?:        //.*\n)*        RunnerBuild\(\n(?:(?!        \),\n).*\n)*?            runtime: \.highball\n        \),\n",
                                    runner_text[start:end], re.M))[-1]
        at = start + download.start()
    runner_text = runner_text[:at] + copy + runner_text[at:]
    patcher_text = patcher_text[:table.end()] + f'        "{engine}": {table[1]},\n' + patcher_text[table.end():]
    return True

added = []
for engine in candidates:
    data = manifest(engine)
    wine = data["components"]["wine"]
    source = by_wine.get(wine["sha256"])
    if source and pin(source, engine, data):
        added.append(engine)
        by_wine[wine["sha256"]] = engine
        note = "" if version(data["minMacOS"]) <= version(minimum) else f", needs macOS {data['minMacOS']}"
        print(f"pinned {engine} like {source}{note}")
    else:
        print(f"unknown {engine} {wine.get('url', '')}")

if added:
    runner.write_text(runner_text)
    patcher.write_text(patcher_text)
    makefile.write_text(makefile.read_text().replace(engines_line[0], engines_line[0] + "".join(" " + e for e in added), 1))
EOF
