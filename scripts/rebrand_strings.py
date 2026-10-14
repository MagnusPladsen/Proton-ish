#!/usr/bin/env python3
"""One-off dev tool: rename the user-visible product name NotProton -> Proton-ish.

Rewrites string literals in Swift sources and the keys + values of Localizable.xcstrings
together, so catalog keys keep matching source strings. Leaves NotProtonApp, NotProtonNot,
NotProtonLaunchMigrated_ and comments alone. Writes the catalog in the exact format
dylib/tests/l10ncheck.py expects.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "app/Sources/NotProtonApp"
CATALOG = SOURCES / "Resources/Localization/Localizable.xcstrings"
WORD = re.compile(r"NotProton(?![A-Za-z_])")
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def rename(text: str) -> str:
    return WORD.sub("Proton-ish", text)


def rewrite_swift(path: pathlib.Path) -> bool:
    original = path.read_text()
    out = []
    for line in original.splitlines(keepends=True):
        if line.lstrip().startswith("//"):
            out.append(line)
            continue
        out.append(STRING_LITERAL.sub(lambda m: rename(m.group(0)), line))
    updated = "".join(out)
    if updated != original:
        path.write_text(updated)
        return True
    return False


def rewrite_catalog() -> None:
    data = json.loads(CATALOG.read_text())
    strings = {}
    for key, entry in data["strings"].items():
        new_key = rename(key)
        if new_key in strings and new_key != key:
            sys.exit(f"collision after rename: {new_key!r}")
        strings[new_key] = json.loads(rename(json.dumps(entry, ensure_ascii=False)))
    data["strings"] = strings
    formatted = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
    formatted = re.sub(r"^( *)(.*) : \{\}", lambda m: f"{m[1]}{m[2]} : {{\n\n{m[1]}}}", formatted, flags=re.M)
    CATALOG.write_text(formatted)


def main() -> None:
    changed = [p for p in sorted(SOURCES.rglob("*.swift")) if rewrite_swift(p)]
    rewrite_catalog()
    for p in changed:
        print(f"rewrote {p.relative_to(ROOT)}")
    print(f"rewrote {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
