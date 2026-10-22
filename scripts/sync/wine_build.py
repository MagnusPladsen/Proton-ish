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

sys.dont_write_bytecode = True
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


# resolve.py refuses an ntdll with a one-line SystemExit; a traceback or a signal is resolve.py
# itself broken (capstone missing, a bug), which fails the job instead of opening an issue for good
def run_resolve(resolve, arguments):
    done = run(resolve + arguments)
    if done.returncode < 0 or "Traceback (most recent call last)" in done.stderr:
        sys.exit(f"wine_build: resolve.py crashed on {' '.join(arguments)}:\n{done.stderr.strip()}")
    return done


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
        done = run_resolve(resolve, ["--json", str(dlls[arch])])
        if done.returncode:
            result["differences"].append(f"{arch}: {done.stderr.strip()}")
            reports.append(done.stderr)
            continue
        resolved[arch] = json.loads(done.stdout)
        report = run_resolve(resolve, [str(dlls[arch])])
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
            done = run_resolve(resolve, ["--pinned", digest])
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


RESOLVE_PY = pathlib.Path("ntdll-patch/resolve.py")
APPLY_PY = pathlib.Path("ntdll-patch/apply.py")
BUILD_NTDLL = pathlib.Path("ntdll-patch/build-ntdll.sh")


def serial(wine):
    tag = wine["url"].rsplit("/", 2)[-2]
    found = re.search(r"-(\d{4})-", tag)
    return found[1] if found else wine["sha256"][:12]


def insert_after(text, anchor, addition):
    at = text.index(anchor) + len(anchor)
    return text[:at] + addition + text[at:]


def pin_resolve(text, old, new, note):
    """PINNED entries for the new ntdlls, copied from the matched build's, after its i386 entry."""
    entry = lambda digest: re.search(r"^    '%s':\n(?:        .*\n)+" % digest, text, re.M)[0]
    copies = "".join(entry(old[arch]).replace(old[arch], new[arch]) for arch in ARCHES)
    return insert_after(text, entry(old["i386-windows"]), f"    # {note}\n" + copies)


def pin_apply(text, old, new, note):
    line = lambda digest: re.search(r'^    "%s": "([^"]+)",\n' % digest, text, re.M)
    copies = "".join(f'    "{new[arch]}": "{line(old[arch])[1]}",\n' for arch in ARCHES)
    return insert_after(text, line(old["i386-windows"])[0], f"    # {note}\n" + copies)


def pin_build_ntdll(text, old_clean, engine, build, hashes, note):
    """Variables, detection, flavor list, tools and patch cases for flavor hb-<build>."""
    prefix = re.search(r"^HB_(\w+)_CLEAN_X86_64=%s$" % old_clean, text, re.M)[1]
    flavor, var = f"hb-{build}".lower(), f"HB_{build}".upper()
    old_flavor = re.search(r'"\$HB_%s_CLEAN_X86_64"\)\s+echo (\S+);' % prefix, text)[1]
    variables = "".join(f"{var}_{kind}_{name}={hashes[kind.lower()][arch]}\n"
                        for kind in ("CLEAN", "PATCHED") for arch, name in (("x86_64-windows", "X86_64"), ("i386-windows", "I386")))
    text = insert_after(text, re.search(r"^HB_%s_PATCHED_I386=.*\n" % prefix, text, re.M)[0], f"# {note}\n" + variables)
    detect = re.search(r'^( +)"\$HB_%s_CLEAN_X86_64"\)( +)echo %s; return 0 ;;\n' % (prefix, old_flavor), text, re.M)
    text = insert_after(text, detect[0], detect[0].replace(f"HB_{prefix}_", f"{var}_").replace(f"echo {old_flavor};", f"echo {flavor};"))
    text = text.replace(f"{old_flavor}, fex,", f"{old_flavor}, {flavor}, fex,", 1)
    tools = re.search(r"^    %s\)( +)tools=.*\n" % re.escape(old_flavor), text, re.M)[0]
    text = insert_after(text, tools, re.sub(r"BUILD=\S+ ;;", f"BUILD={engine} ;;", tools.replace(f"{old_flavor})", f"{flavor})")))
    case = re.search(r"^    %s\)\n(?:        .*\n)+?        ;;\n" % re.escape(old_flavor), text, re.M)[0]
    return insert_after(text, case, case.replace(f"{old_flavor})", f"{flavor})").replace(f"HB_{prefix}_", f"{var}_"))


def pin_patcher(text, match, engine, build, note):
    table = table_name(text, match)
    end = re.search(r"static let %s: \[NtdllPatch\] = \[\n.*?\n    \]\n" % table, text, re.S)
    text = insert_after(text, end[0], f"\n    // {note}\n    static let highballBuild{build} = {table}\n")
    return engine_pins.add_patch_entry(text, match, engine, f"highballBuild{build}")


def pin_new_build(result, engine, manifest):
    match = result["match"]
    if not match:
        sys.exit(2)
    wine = manifest["components"]["wine"]
    build = serial(wine)
    # A serial is one Wine build: the same serial with other bytes is a rebuild to look at by hand,
    # and pinning it again would declare its Swift table twice
    if re.search(rf"static let highballBuild{build}\b", engine_pins.PATCHER.read_text()):
        sys.exit(f"wine_build: build {build} is already pinned; {engine} uses Wine {wine['sha256'][:12]} with that serial")
    old = clean_hashes(engine_pins.RUNNER.read_text(), match)
    note = f"{engine} (engine build {build}): same offsets as {match}, pinned by scripts/sync/wine_build.py"
    runner_text = engine_pins.RUNNER.read_text()
    source_display = re.search(r'display: "((?:[^"\\]|\\.)*)"', engine_pins.runner_block(runner_text, match)[0])[1]
    edits = {
        RESOLVE_PY: pin_resolve(RESOLVE_PY.read_text(), old, result["clean"], note),
        APPLY_PY: pin_apply(APPLY_PY.read_text(), old, result["clean"], note),
        BUILD_NTDLL: pin_build_ntdll(BUILD_NTDLL.read_text(), old["x86_64-windows"], engine, build,
                                     {"clean": result["clean"], "patched": result["patched"]}, note),
        engine_pins.PATCHER: pin_patcher(engine_pins.PATCHER.read_text(), match, engine, build, note),
        engine_pins.RUNNER: engine_pins.add_runner_build(
            runner_text, match, engine, engine_pins.tool_display(source_display, engine, manifest["displayName"]),
            engine_pins.needs_newer_macos(manifest, engine_pins.app_minimum_macos(engine_pins.PACKAGE.read_text())),
            {"loader": result["loader"], "clean": result["clean"], "patched": result["patched"]}),
        engine_pins.MAKEFILE: engine_pins.add_bundled_engine(engine_pins.MAKEFILE.read_text(), engine),
    }
    for path, text in edits.items():
        path.write_text(text)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "check":
        print(json.dumps(check(pathlib.Path(sys.argv[2])), indent=1, sort_keys=True))
    elif len(sys.argv) == 4 and sys.argv[1] == "pin":
        pin_new_build(json.load(sys.stdin), sys.argv[2], json.loads(pathlib.Path(sys.argv[3]).read_text()))
    else:
        sys.exit(f"usage: {sys.argv[0]} check <engine dir>\n       {sys.argv[0]} pin <engine id> <manifest json> < check result")
