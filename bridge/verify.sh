#!/bin/sh
# Check the bridge holds exactly what a launch consumes, and nothing else.
#
#   ./verify.sh          report what is missing, unexpected, or present
#   ./verify.sh --prune  also move anything unexpected out to scratch/bridge-attic
#
# The bridge is the staging area RUN_SCRIPT installs from on every launch, so what
# sits in it ends up in the CrossOver tree, the wine prefix, and the Steam client
# directory. Stray files there are not harmless:
#
# - legacycompat is copied by glob, so anything dropped in it is installed into the
#   Steam client directory verbatim.
# - a stale lsteamclient.so or steamclient64.so beside a PE of the same name makes
#   wine bind that builtin to the old unix half instead of loading the dll.
# - a wrong-arch PE on WINEDLLPATH aborts builtin lookup outright with c000007b.
#
# Backups belong outside the bridge for the same reason, which is why --prune moves
# rather than deletes: the attic is in scratch, which is disposable.
#
# Every file here is reproducible. The built ones come from make lsteamclient,
# make steam-shim and make ntdll-patch. The Valve ones come from the Steam client
# packages, fetched by fetch-valve.sh beside this script.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
BRIDGE_DIR="${BRIDGE_DIR:-$HOME/Library/Application Support/protonish/bridge}"
ATTIC="${ATTIC:-$repo/scratch/bridge-attic}"
# Stale whole-bridge copies get made next to it rather than inside it, where a
# check that only walks the bridge cannot see them.
SUPPORT_DIR="${SUPPORT_DIR:-$(dirname "$BRIDGE_DIR")}"
BRIDGE_NAME="$(basename "$BRIDGE_DIR")"

prune=0
[ "${1:-}" = "--prune" ] && prune=1

# What RUN_SCRIPT reads, taken from the manifest the companion app also ships, so
# this list and the one the installer stages from cannot drift apart. The manifest
# sits in the app's resource directory because that is the only place Swift Package
# Manager will package a file from.
MANIFEST="${MANIFEST:-$repo/app/Sources/NotProtonApp/Resources/payload.manifest}"
if [ ! -f "$MANIFEST" ]; then
    echo "==> no payload manifest at $MANIFEST" >&2
    exit 1
fi

# Three origins collapse to the two sections this check has always printed. The
# manifest separates built from patched because the installer treats them
# differently, the patched ntdlls being made from the user's own CrossOver. That
# distinction does not matter here.
origin() {
    awk -v want="$1" '$1 == want { print $2 }' "$MANIFEST"
}

built="$(origin built; origin patched)"
valve="$(origin valve)"

if [ -z "$built" ] || [ -z "$valve" ]; then
    echo "==> payload manifest has no usable entries: $MANIFEST" >&2
    exit 1
fi

if [ ! -d "$BRIDGE_DIR" ]; then
    echo "==> no bridge at $BRIDGE_DIR" >&2
    exit 1
fi

expected="$(printf '%s\n%s\n' "$built" "$valve" | sed '/^$/d')"
missing=0
unexpected=0

report() {
    label="$1"
    list="$2"
    echo "==> $label"
    for rel in $list; do
        f="$BRIDGE_DIR/$rel"
        if [ -f "$f" ]; then
            printf '    %-42s %10s  %s\n' "$rel" "$(wc -c < "$f" | tr -d ' ')" \
                "$(shasum -a 256 "$f" | cut -c1-16)"
        else
            printf '    %-42s %s\n' "$rel" "MISSING"
            missing=$((missing + 1))
        fi
    done
}

report "built here" "$built"
report "from Valve" "$valve"

# Listed relative to the bridge so the paths stay printable and the directory name
# containing spaces never has to be stripped by pattern. grep does the comparison
# because a case statement inside a command substitution does not parse in the sh
# macOS ships. Every line of $expected is one fixed whole-line pattern, and grep
# exits nonzero when nothing is left over, which is the ordinary result.
strays="$(cd "$BRIDGE_DIR" && { find . -mindepth 1 -type f | sed 's|^\./||' \
    | grep -Fxv "$expected" || true; })"

unexpected=0
[ -n "$strays" ] && unexpected="$(printf '%s\n' "$strays" | wc -l | tr -d ' ')"

echo "==> unexpected"
if [ "$unexpected" -eq 0 ]; then
    echo "    none"
else
    printf '%s\n' "$strays" | while read -r rel; do
        if [ "$prune" -eq 1 ]; then
            mkdir -p "$ATTIC/$(dirname "$rel")"
            mv "$BRIDGE_DIR/$rel" "$ATTIC/$rel"
            printf '    moved to attic: %s\n' "$rel"
        else
            printf '    %s\n' "$rel"
        fi
    done
fi

if [ "$prune" -eq 1 ] && [ "$unexpected" -gt 0 ]; then
    # Moving files leaves the directories that held them behind.
    ( cd "$BRIDGE_DIR" && find . -mindepth 1 -type d -empty -delete )
    unexpected=0
fi

# A whole copy of the bridge parked beside it is the other way this directory
# accumulates. Each one is a few hundred megabytes of binaries that no launch reads
# and that no build target maintains, so they only go stale.
copies="$(find "$SUPPORT_DIR" -maxdepth 1 -mindepth 1 -type d -name "$BRIDGE_NAME.*" \
    | sed "s|^$SUPPORT_DIR/||" | sort)"
stale=0
[ -n "$copies" ] && stale="$(printf '%s\n' "$copies" | wc -l | tr -d ' ')"

echo "==> stale bridge copies"
if [ "$stale" -eq 0 ]; then
    echo "    none"
else
    printf '%s\n' "$copies" | while read -r c; do
        sz="$(du -sh "$SUPPORT_DIR/$c" | awk '{print $1}')"
        if [ "$prune" -eq 1 ]; then
            mkdir -p "$ATTIC"
            rm -rf "${ATTIC:?}/${c:?}"
            mv "$SUPPORT_DIR/$c" "$ATTIC/$c"
            printf '    moved to attic: %-42s %s\n' "$c" "$sz"
        else
            printf '    %-42s %s\n' "$c" "$sz"
        fi
    done
    [ "$prune" -eq 1 ] && stale=0
fi


# RUN_SCRIPT rewrites the flat bridge files in each prefix's Steam directory and the one
# i386 lsteamclient.dll trigger in syswow64 on every launch, so a stale copy in either
# place heals itself and is only worth reporting. Anywhere else in a prefix is different:
# nothing rewrites it and nothing prunes it, so it keeps whatever build put it there.
# system32 is the case that matters. install_lsteamclient deliberately puts nothing there
# so that a 64 bit load never finds a trigger it did not stage, and a correct-arch PE
# appearing there defeats that on its own.
PREFIX_ROOT="${PREFIX_ROOT:-$HOME/Library/Application Support/Steam/steamapps/compatdata}"

prefix_strays=""
prefixes=0
prefix_stale=0
if [ -d "$PREFIX_ROOT" ]; then
    for pfx in "$PREFIX_ROOT"/*/pfx; do
        [ -d "$pfx" ] || continue
        prefixes=$((prefixes + 1))
        appid="$(basename "$(dirname "$pfx")")"

        staged="$pfx/drive_c/Program Files (x86)/Steam/lsteamclient.dll"
        trigger="$pfx/drive_c/windows/syswow64/lsteamclient.dll"
        for pair in "$staged:$BRIDGE_DIR/lsteamclient.dll" \
                    "$trigger:$BRIDGE_DIR/i386-windows/lsteamclient.dll"; do
            have="${pair%:*}"
            want="${pair##*:}"
            [ -f "$have" ] || continue
            cmp -s "$have" "$want" || prefix_stale=$((prefix_stale + 1))
        done

        while IFS= read -r f; do
            [ -n "$f" ] || continue
            rel="${f#"$pfx"/}"
            case "$rel" in
                "drive_c/Program Files (x86)/Steam/"*) continue ;;
                "drive_c/windows/syswow64/lsteamclient.dll") continue ;;
            esac
            prefix_strays="$prefix_strays$appid/$rel
"
        done <<STRAYS
$(find "$pfx" -type f \
    \( -name lsteamclient.dll -o -name lsteamclient.so \
    -o -name steamclient.dll -o -name steamclient64.dll \
    -o -name tier0_s64.dll -o -name vstdlib_s64.dll \
    -o -name steam.exe \) 2>/dev/null)
STRAYS
    done
fi

prefix_strays="$(printf '%s' "$prefix_strays" | sed '/^$/d')"
stray_count=0
[ -n "$prefix_strays" ] && stray_count="$(printf '%s\n' "$prefix_strays" | wc -l | tr -d ' ')"

echo "==> prefix strays ($prefixes prefixes, $prefix_stale staged copies stale, heal next launch)"
if [ "$stray_count" -eq 0 ]; then
    echo "    none"
else
    printf '%s\n' "$prefix_strays" | while read -r rel; do
        appid="${rel%%/*}"
        sub="${rel#*/}"
        src="$PREFIX_ROOT/$appid/pfx/$sub"
        if [ "$prune" -eq 1 ]; then
            mkdir -p "$ATTIC/prefix-strays/$appid/$(dirname "$sub")"
            mv "$src" "$ATTIC/prefix-strays/$appid/$sub"
            printf '    moved to attic: %s\n' "$rel"
        else
            printf '    %s\n' "$rel"
        fi
    done
    [ "$prune" -eq 1 ] && stray_count=0
fi

[ "$prune" -eq 1 ] && echo "==> attic: $ATTIC"
echo "==> $missing missing, $unexpected unexpected, $stale stale copies, $stray_count prefix strays"
[ "$missing" -eq 0 ] && [ "$unexpected" -eq 0 ] && [ "$stale" -eq 0 ] && [ "$stray_count" -eq 0 ]
