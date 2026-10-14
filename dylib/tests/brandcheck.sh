#!/bin/sh
# Fails while an upstream NotProton identifier remains in a bucket Proton-ish renames.
# Usage: brandcheck.sh [support|dylib|tools|identity|updates|strings|release|docs]...
set -u

cd "$(git rev-parse --show-toplevel)" || exit 2

# Paths that may name upstream: credit docs, licences, the spec/plans, this script.
EXCLUDE=":(exclude)docs/superpowers :(exclude)LICENSE* :(exclude)NOTICE :(exclude)README.md :(exclude)CONTRIBUTING.md :(exclude).github/ISSUE_TEMPLATE :(exclude)dylib/tests/brandcheck.sh :(exclude)scripts/rebrand_strings.py"

failed=0

# Pathspecs below contain globs meant for git, not the shell
set -f

# check <section> <extended-regex>
check() {
    section=$1; pattern=$2
    # shellcheck disable=SC2086
    hits=$(git grep -n -E -e "$pattern" -- . $EXCLUDE 2>/dev/null || true)
    if [ -n "$hits" ]; then
        printf '==> brandcheck %s: upstream identifier /%s/ still present\n%s\n' "$section" "$pattern" "$hits"
        failed=1
    fi
}

run_section() {
    case $1 in
    support)
        check support 'Application Support/notproton'
        check support 'supportDirName = "notproton"'
        check support 'notproton-steam-bundles\.json'
        ;;
    dylib)
        check dylib 'notproton(\.arm64|\.x86_64)?\.dylib'
        check dylib 'Info\.plist\.before-notproton'
        check dylib 'notproton\.log'
        ;;
    tools)
        check tools 'notproton(-fex|-preview|-26\.3)'
        check tools 'TOOL_DIR_NAME +"notproton"'
        check tools 'legacyToolName = "notproton"'
        check tools 'hasPrefix\("notproton"\)'
        check tools 'notproton\.none'
        check tools '# notproton CrossOver compatibility tool shim'
        ;;
    identity)
        check identity 'com\.notproton\.'
        ;;
    updates)
        check updates 'NotProtonNot/NotProton/releases'
        check updates 'rDOXzJ\+vt12aWeu9hATgvz6q46MlRcgR4gbTfj5YuWQ='
        ;;
    strings)
        # User-visible "NotProton" outside comments. Skips NotProtonApp/NotProtonLaunchMigrated (regex),
        # and the fork credit (AboutCredits.swift, catalog lines naming NotProtonNot).
        hits=$(git grep -n -E 'NotProton([^A-Za-z]|$)' -- \
                 'app/Sources/*.swift' 'app/Sources/*.xcstrings' 'dylib/*.c' 'dylib/*.h' 'dylib/feats/compat_run.sh' \
                 ':(exclude)app/Sources/NotProtonApp/Support/AboutCredits.swift' 2>/dev/null \
               | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*(//|#|\*|/\*)' \
               | grep -v 'NotProtonNot' || true)
        if [ -n "$hits" ]; then
            printf '==> brandcheck strings: user-visible "NotProton" still present\n%s\n' "$hits"
            failed=1
        fi
        check strings '\[notproton\]'
        check strings 'notproton-(run|wine)\.log'
        ;;
    release)
        check release 'NotProton\.(app|zip|txt|icon|icns)'
        check release 'name: NotProton$'
        check release 'user\.name NotProtonNot'
        check release 'NotProtonNot@users\.noreply'
        check release 'app-icon NotProton'
        check release '<string>NotProton</string>'   # CFBundleName, CFBundleIconFile, CFBundleIconName
        ;;
    docs)
        for f in NOTICE README.md CONTRIBUTING.md; do
            grep -q 'Proton-ish' "$f" || { echo "==> brandcheck docs: $f does not mention Proton-ish"; failed=1; }
        done
        grep -q 'fork of NotProton' README.md || { echo "==> brandcheck docs: README lacks the fork credit"; failed=1; }
        grep -q 'not affiliated' README.md || { echo "==> brandcheck docs: README lacks the no-affiliation statement"; failed=1; }
        grep -q 'Modified by Proton-ish contributors' NOTICE || { echo "==> brandcheck docs: NOTICE lacks the modification notice"; failed=1; }
        [ -d .github/ISSUE_TEMPLATE ] || { echo "==> brandcheck docs: .github/ISSUE_TEMPLATE missing"; failed=1; }
        # Until Highball support ships (M2), docs must not offer or promise it
        ! grep -q 'Highball' .github/ISSUE_TEMPLATE/bug_report.yml || { echo "==> brandcheck docs: bug template offers Highball before it is supported"; failed=1; }
        ! grep -q 'that adds free Wine' CONTRIBUTING.md || { echo "==> brandcheck docs: CONTRIBUTING claims Highball support exists"; failed=1; }
        ! grep -q 'read "Proton-ish" unless' README.md || { echo "==> brandcheck docs: README rewrites upstream policy text as Proton-ish's"; failed=1; }
        ;;
    *)
        echo "brandcheck: unknown section $1" >&2; exit 2 ;;
    esac
}

if [ $# -eq 0 ]; then
    set -- support dylib tools identity updates strings release docs
fi
for s in "$@"; do run_section "$s"; done

if [ $failed -eq 0 ]; then
    echo "==> brandcheck: clean ($*)"
fi
exit $failed
