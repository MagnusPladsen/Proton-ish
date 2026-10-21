"""Checks a Highball engine with a new Wine build against the builds Proton-ish pins.

Usage, from the repository root:
  python3 -I scripts/sync/wine_build.py check <engine dir>
<engine dir> holds bin/wine and lib/wine/{x86_64,i386}-windows/ntdll.dll. check prints one JSON
object (loader, clean, match, patched, differences, report) and exits 0 whatever it finds.
RESOLVE and APPLY name the ntdll-patch commands, so tests can run without capstone.
"""
import hashlib
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import engine_pins  # noqa: E402

ARCHES = ("x86_64-windows", "i386-windows")
# resolve.py's PINNED records the hook; the app's NtdllPatcher table records the cave and image
HOOK_FIELDS = ("hookRVA", "stolen", "wm", "resume", "load_path", "exports")
IMAGE_FIELDS = ("caveRVA", "caveSize", "fill", "machine", "magic", "imageBase", "placement")
RESOURCES = pathlib.Path("app/Sources/NotProtonApp/Resources")


def command(name, default):
    return shlex.split(os.environ.get(name, default))


def sha256(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def run(arguments):
    return subprocess.run(arguments, capture_output=True, text=True)


def number(text):
    return int(text.replace("_", ""), 0)


def clean_hashes(runner_text, engine):
    block = engine_pins.runner_block(runner_text, engine)[0]
    clean = re.search(r"cleanNtdll: \[\n(.*?)\n            \],", block, re.S)[1]
    return {arch: re.search(r'\.%s: "([0-9a-f]+)"' % key, clean)[1] for arch, key in engine_pins.ARCH_KEYS.items()}


def table_name(patcher_text, engine):
    found = re.search(r'^        "%s": (\w+),$' % re.escape(engine), patcher_text, re.M)
    return found and found[1]


def table_image(patcher_text, name):
    """The cave and image fields of each architecture in a named NtdllPatcher table."""
    body = re.search(r"static let %s: \[NtdllPatch\] = \[\n(.*?)\n    \]\n" % re.escape(name), patcher_text, re.S)[1]
    arches = {key: arch for arch, key in engine_pins.ARCH_KEYS.items()}
    image = {}
    for entry in re.findall(r"NtdllPatch\((.*?)\n            \),", body, re.S):
        field = lambda key: re.search(r"\b%s: ([0-9a-fA-Fx_]+)" % key, entry)[1]
        placement = re.search(r"placement: \.(\w+)", entry)
        image[arches[re.search(r"arch: \.(\w+)", entry)[1]]] = {
            "caveRVA": number(field("caveRVA")), "caveSize": number(field("caveSize")),
            "fill": number(field("cavePad")), "machine": number(field("machine")),
            "magic": number(field("magic")), "imageBase": number(field("imageBase")),
            "placement": placement[1] if placement else "padding"}
    return image


def shown(value):
    return f"{value:#x}" if isinstance(value, int) else str(value)


def differences(arch, new, pin, image):
    found = []
    expected = {key: pin.get(key) for key in HOOK_FIELDS}
    expected.update(image or {})
    for key, want in expected.items():
        got = new.get(key)
        if key == "exports":
            # Only the exports the pinned payload calls; resolve.py also lists ones it does not
            found += [f"{arch} exports.{name} {shown(want[name])} != {shown(got.get(name))}"
                      for name in sorted(want) if want[name] != got.get(name)]
        elif want != got:
            found.append(f"{arch} {key} {shown(want)} != {shown(got)}")
    return found


def payload_file(digest):
    return next((path for path in sorted(RESOURCES.glob("*.bin")) if sha256(path) == digest), None)


def patch(dlls, pins):
    """The patched hash of each ntdll, or the reason apply.py refused one."""
    patched = {}
    with tempfile.TemporaryDirectory() as scratch:
        for arch in ARCHES:
            payload = payload_file(pins[arch]["payload"])
            if payload is None:
                return None, f"{arch}: no payload in {RESOURCES} has sha256 {pins[arch]['payload']}"
            out = pathlib.Path(scratch, arch)
            done = run(command("APPLY", "python3 -I ntdll-patch/apply.py") + [str(dlls[arch]), str(out), str(payload)])
            if done.returncode:
                return None, f"{arch}: apply.py: {(done.stderr or done.stdout).strip()}"
            patched[arch] = sha256(out)
    return patched, None


def check(engine_dir):
    resolve = command("RESOLVE", "python3 -I ntdll-patch/resolve.py")
    dlls = {arch: engine_dir / "lib/wine" / arch / "ntdll.dll" for arch in ARCHES}
    result = {"loader": sha256(engine_dir / "bin/wine"), "clean": {arch: sha256(dlls[arch]) for arch in ARCHES},
              "match": None, "patched": None, "differences": [], "report": ""}
    resolved, reports = {}, []
    for arch in ARCHES:
        done = run(resolve + ["--json", str(dlls[arch])])
        if done.returncode:
            result["differences"].append(f"{arch}: {done.stderr.strip()}")
            reports.append(done.stderr)
            continue
        resolved[arch] = json.loads(done.stdout)
        report = run(resolve + [str(dlls[arch])])
        reports.append(report.stdout if report.returncode == 0 else report.stderr)
    result["report"] = "\n".join(reports)
    if result["differences"]:
        return result

    runner_text = engine_pins.RUNNER.read_text()
    patcher_text = engine_pins.PATCHER.read_text()
    engines = sorted(engine_pins.pinned_engines(engine_pins.MAKEFILE.read_text()), key=engine_pins.revision, reverse=True)
    for n, engine in enumerate(engines):
        pins = {}
        for arch, digest in clean_hashes(runner_text, engine).items():
            done = run(resolve + ["--pinned", digest])
            if done.returncode == 0:
                pins[arch] = json.loads(done.stdout)
        table = table_name(patcher_text, engine)
        if len(pins) < len(ARCHES):
            continue
        image = table_image(patcher_text, table) if table else {}
        found = [line for arch in ARCHES for line in differences(arch, resolved[arch], pins[arch], image.get(arch))]
        if n == 0:
            result["differences"] = found
        if found or not table:
            continue
        patched, refusal = patch(dlls, pins)
        if refusal:
            result["differences"] = [refusal]
            return result
        result.update(match=engine, patched=patched, differences=[])
        return result
    return result


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "check":
        sys.exit(f"usage: {sys.argv[0]} check <engine dir>")
    print(json.dumps(check(pathlib.Path(sys.argv[2])), indent=1, sort_keys=True))
