#!/bin/sh
# shellcheck disable=SC2034,SC2154
set -e
SRC="${1:-$(dirname "$0")/../feats/compat_run.sh}"
[ -f "$SRC" ] || { echo "envcheck: $SRC not present, skipped"; exit 0; }

strip() { sed 's/^[[:space:]]*//'; }
dllpath_line=$(grep 'export WINEDLLPATH=' "$SRC" | grep 'x86_64-windows' | strip)
overrides_line=$(grep 'export WINEDLLOVERRIDES=' "$SRC" | grep 'lsteamclient=b' | strip)
[ -n "$dllpath_line" ] || { echo "FAIL: WINEDLLPATH merge not found"; exit 1; }
[ -n "$overrides_line" ] || { echo "FAIL: WINEDLLOVERRIDES merge not found"; exit 1; }

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n         want [%s]\n         got  [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); }
is() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

echo "== WINEDLLPATH (first match wins, runner first) =="
CX_ROOT=/R
wine_unix=/R/lib/wine/x86_64-unix
WINEDLLPATH=""
eval "$dllpath_line"
is "no user value" "/R/lib/wine/x86_64-windows:/R/lib/wine/x86_64-unix" "$WINEDLLPATH"
WINEDLLPATH="/user/dir"
eval "$dllpath_line"
is "user value last" "/R/lib/wine/x86_64-windows:/R/lib/wine/x86_64-unix:/user/dir" "$WINEDLLPATH"

echo "== WINEDLLOVERRIDES (last wins, trio last) =="
WINEDLLOVERRIDES=""
eval "$overrides_line"
is "no user value" "steamclient=n;steamclient64=n;lsteamclient=b" "$WINEDLLOVERRIDES"
WINEDLLOVERRIDES="winhttp=n,b"
eval "$overrides_line"
is "user value first" "winhttp=n,b;steamclient=n;steamclient64=n;lsteamclient=b" "$WINEDLLOVERRIDES"
WINEDLLOVERRIDES="lsteamclient=n"
eval "$overrides_line"
is "trio outranks user" "lsteamclient=n;steamclient=n;steamclient64=n;lsteamclient=b" "$WINEDLLOVERRIDES"
vc_overrides="vcruntime140_1=n,b;"
WINEDLLOVERRIDES="vcruntime140_1=b"
eval "$overrides_line"
is "user outranks the native runtime" \
  "vcruntime140_1=n,b;vcruntime140_1=b;steamclient=n;steamclient64=n;lsteamclient=b" "$WINEDLLOVERRIDES"
vc_overrides=""

echo "== Microsoft's Visual C++ runtime loads when it is installed =="
vc_fn=$(sed -n '/^native_vc_runtime() {/,/^}/p' "$SRC")
[ -n "$vc_fn" ] || { echo "FAIL: native_vc_runtime not found"; exit 1; }
eval "$vc_fn"
vc_work=$(mktemp -d)
WINEPREFIX="$vc_work/pfx"
sys32="$WINEPREFIX/drive_c/windows/system32"
mkdir -p "$sys32"
pe() { printf 'MZ%062d%s' 0 "$2" > "$sys32/$1.dll"; }
is "empty prefix overrides nothing" "" "$(native_vc_runtime)"
pe vcruntime140 "Wine builtin DLL"
pe msvcp140_2 "Wine builtin DLL"
is "Wine's own copies are left alone" "" "$(native_vc_runtime)"
pe msvcp140_2 "This program cannot be run in DOS mode."
pe vcruntime140_1 "This program cannot be run in DOS mode."
: > "$sys32/msvcp140.dll"
is "Microsoft's copies load first" "msvcp140=n,b;msvcp140_2=n,b;vcruntime140_1=n,b;" "$(native_vc_runtime)"
rm -rf "$vc_work"

echo "== Runtime read from the tool directory =="
# shellcheck disable=SC2016 # Match the literal script lines.
runtime_read=$(sed -n '/^np_runtime=crossover$/,/^case "$np_runtime"/p' "$SRC")
# shellcheck disable=SC2016 # Match the literal script line.
root_line=$(grep -F 'CX_ROOT="$np_support/runners/' "$SRC")
[ -n "$runtime_read" ] && [ -n "$root_line" ] || { echo "FAIL: runtime read or runner root not found"; exit 1; }
rt_work=$(mktemp -d)
np_tool_dir="$rt_work/tool"
mkdir -p "$np_tool_dir"
runtime_after() {
  rm -f "$np_tool_dir/runtime"
  [ "$1" = "<none>" ] || printf '%b' "$1" > "$np_tool_dir/runtime"
  eval "$runtime_read"
  printf '%s' "$np_runtime"
}
is "a recorded runtime is used" "highball" "$(runtime_after 'highball\n')"
is "crossover is read as crossover" "crossover" "$(runtime_after 'crossover\n')"
is "no runtime file means crossover" "crossover" "$(runtime_after '<none>')"
is "an empty runtime file means crossover" "crossover" "$(runtime_after '')"
is "a path in the runtime file cannot leave runners/" "crossover" "$(runtime_after '../x\n')"
is "a slash in the runtime file cannot leave runners/" "crossover" "$(runtime_after 'a/b\n')"
np_support=/S; np_runtime=crossover; np_build=26.3.0.39832
eval "$root_line"
is "the runner root is runners/<runtime>-<build>/root" "/S/runners/crossover-26.3.0.39832/root" "$CX_ROOT"
rm -rf "$rt_work"

echo "== Highball runner environment =="
# shellcheck disable=SC2016 # Match the literal script lines.
hb_block=$(sed -n '/^# Highball: server in bin/,/^fi # highball$/p' "$SRC")
[ -n "$hb_block" ] || { echo "FAIL: Highball block not found"; exit 1; }
hb=$(mktemp -d)
CX_ROOT="$hb/root"; np_runtime=highball
mkdir -p "$CX_ROOT/bin" "$CX_ROOT/lib/wine/x86_64-unix" "$CX_ROOT/renderers/dxmt/wine"
# shellcheck disable=SC2016 # The command substitution is the attack being tested.
printf 'DYLD_FALLBACK_LIBRARY_PATH=%s/frameworks\nlower=x\n$(touch %s/pwned)=x\nWINEDEBUG=fixme-all\n' "$CX_ROOT" "$hb" > "$CX_ROOT/runtime.env"
WINELOADER=/wrong; WINESERVER=/wrong; wine_unix=/wrong
eval "$hb_block"
is "Highball loader is the x86_64-unix wine, as for CrossOver" "$CX_ROOT/lib/wine/x86_64-unix/wine" "$WINELOADER"
is "Highball server is bin/wineserver" "$CX_ROOT/bin/wineserver" "$WINESERVER"
is "Highball unix dir" "$CX_ROOT/lib/wine/x86_64-unix" "$wine_unix"
is "runtime.env value exported" "$CX_ROOT/frameworks" "$DYLD_FALLBACK_LIBRARY_PATH"
is "runtime.env never executes" "no" "$([ -e "$hb/pwned" ] && echo yes || echo no)"
is "DXMT renderer is prepended" "$CX_ROOT/renderers/dxmt/wine" "$WINEDLLPATH_PREPEND"
is "Windows user is steamuser" "steamuser" "$WINEUSERNAME"
is "keys from runtime.env are remembered for the game" " DYLD_FALLBACK_LIBRARY_PATH WINEDEBUG" "$np_hb_keys"
# A user's launch option wins over the engine default; lowercase keys never pass, whatever the locale
unset -v lower DYLD_FALLBACK_LIBRARY_PATH
WINEDEBUG=+seh np_hb_keys=""
eval "$hb_block"
is "a launch option beats runtime.env" "+seh" "$WINEDEBUG"
# The locale must be set when the shell starts for pattern ranges to follow it
# shellcheck disable=SC2016 # Expanded by the child shell.
leaked=$(LC_ALL=en_US.UTF-8 CX_ROOT="$CX_ROOT" np_runtime=highball hb_block="$hb_block" \
  sh -c 'eval "$hb_block"; printf %s "${lower:-}"')
is "a lowercase key is ignored under a UTF-8 locale" "" "$leaked"

echo "== Highball environment reaches the game =="
hb_forward=$(sed -n '/^# Highball: forward the engine environment/,/^fi # highball forward$/p' "$SRC")
[ -n "$hb_forward" ] || { echo "FAIL: Highball forwarding block not found"; exit 1; }
np_hb_keys=" DYLD_FALLBACK_LIBRARY_PATH GST_PLUGIN_PATH"
GST_PLUGIN_PATH=/F/gst
set --
eval "$hb_forward"
is "engine and runtime keys are passed with --env" \
  "--env GST_PLUGIN_PATH=/F/gst --env CX_FWD_COMPAT_GL_CTX=1 --env WINEDLLPATH_PREPEND=$CX_ROOT/renderers/dxmt/wine --env WINEUSERNAME=steamuser " \
  "$(printf '%s ' "$@")"
# shellcheck disable=SC2016 # Match the literal script lines.
launcher_text=$(sed -n '/^cat > "$loader_macos\/launcher" <<LAUNCHER$/,/^LAUNCHER$/p' "$SRC")
case "$launcher_text" in
  *'DYLD_FALLBACK_LIBRARY_PATH=*|DYLD_FALLBACK_FRAMEWORK_PATH=*) export'*) ok "launcher re-exports the engine's DYLD fallback paths" ;;
  *) bad "launcher re-exports the engine's DYLD fallback paths" "a DYLD_FALLBACK case in the launcher" "none" ;;
esac
launcher_hb='DYLD_INSERT_LIBRARIES=*) export DYLD_INSERT_LIBRARIES='
# shellcheck disable=SC2016 # Match the literal launcher text.
case "$launcher_text" in
  *"$launcher_hb"*'done < "$np_hb_env_file"'*) ok "launcher takes DYLD values from Highball's file for the game" ;;
  *) bad "launcher takes DYLD values from Highball's file for the game" "a np_hb_env_file loop" "none" ;;
esac

echo "== Highball's own launch environment (highball-env) =="
hb_env_fn=$(sed -n '/^highball_environment() {$/,/^} # highball_environment$/p' "$SRC")
[ -n "$hb_env_fn" ] || { echo "FAIL: highball_environment not found"; exit 1; }
# shellcheck disable=SC2016 # Match the literal script lines.
hb_call=$(sed -n '/^  if \[ "$np_runtime" = highball \]; then$/,/^  fi$/p' "$SRC")
case "$hb_call" in
  *highball_environment*) ok "highball-env runs only for Highball runners" ;;
  *) bad "highball-env runs only for Highball runners" "a call guarded by np_runtime = highball" "$hb_call" ;;
esac
eval "$hb_env_fn"
np_support="$hb/support"; STEAM_COMPAT_DATA_PATH="$hb/compat"; WINEPREFIX="$hb/compat/pfx"
np_build=x64-crossover26.3-r19; app_id=1086940; log="$hb/run.log"
mkdir -p "$np_support" "$STEAM_COMPAT_DATA_PATH"
helper() { printf '#!/bin/sh\n%s\n' "$1" > "$np_support/highball-env"; chmod +x "$np_support/highball-env"; }
reset_hb() { WINEDLLPATH_PREPEND=/fallback/dxmt; np_hb_keys=""; np_hb_env_file=""; : > "$log"; }

reset_hb
# shellcheck disable=SC2016 # Single quotes keep the helper's text literal.
helper 'echo "args: $*" >&2
echo "# note: renderer d3dmetal"
echo "GST_PLUGIN_PATH=/HB/gst"
echo "WINEDLLPATH_PREPEND=/HB/d3dmetal/wine:/HB/dxmt/wine"
echo "CX_D3DMETALPATH=/HB/d3dmetal/external"
echo "DYLD_FALLBACK_FRAMEWORK_PATH=/HB/external:/HB/frameworks"
echo "WINELOADER=/HB/wine"
echo "lower=x"
echo "\$(touch '"$hb"'/pwned)=x"
echo "HB_VALUE=\$(touch '"$hb"'/pwned2)"'
WINELOADER=/ours/wine
highball_environment
is "Highball's renderer folders replace the DXMT default" "/HB/d3dmetal/wine:/HB/dxmt/wine" "$WINEDLLPATH_PREPEND"
is "Highball's variables are exported" "/HB/d3dmetal/external" "$CX_D3DMETALPATH"
is "the loader stays Proton-ish's" "/ours/wine" "$WINELOADER"
is "DYLD values wait for the launcher" "" "${DYLD_FALLBACK_FRAMEWORK_PATH:-}"
is "the DYLD value is kept for the launcher" "1" "$(grep -c '^DYLD_FALLBACK_FRAMEWORK_PATH=/HB/external' "$np_hb_env_file")"
is "a lowercase name is refused" "" "${lower:-}"
is "nothing the helper prints is executed" "no" "$([ -e "$hb/pwned" ] || [ -e "$hb/pwned2" ] && echo yes || echo no)"
# shellcheck disable=SC2016 # The literal text is the expected value.
is "a value is exported as text" '$(touch '"$hb"'/pwned2)' "$HB_VALUE"
is "the keys are remembered for the game" " GST_PLUGIN_PATH WINEDLLPATH_PREPEND CX_D3DMETALPATH HB_VALUE" "$np_hb_keys"
is "notes are logged" "1" "$(grep -c 'highball-env: note: renderer d3dmetal' "$log")"
is "the helper gets the prefix, engine, app id, database and recipe paths" \
  "args: --prefix $WINEPREFIX --engine x64-crossover26.3-r19 --appid 1086940 --db $np_support/highball-db.json --applied $WINEPREFIX/protonish-recipe --reg $WINEPREFIX/drive_c/protonish-recipe.reg --other-engines apply" \
  "$(grep '^args:' "$log")"
reset_hb
hb_game="$hb/Game.exe"; : > "$hb_game"
highball_environment "$hb_game"
is "the game's executable is passed when it exists" "1" "$(grep -c -- "--exe $hb_game --applied " "$log")"
reset_hb
highball_environment "$hb/missing.exe"
is "a missing executable is not passed" "0" "$(grep -c -- '--exe' "$log")"
# shellcheck disable=SC2016 # Match the literal script line.
hb_call_site=$(grep -c 'highball_environment "\$1"' "$SRC")
is "the run script hands the game's executable to the helper" "1" "$hb_call_site"
echo "== Prefix recipe (apply_prefix_recipe) =="
hb_apply_fn=$(sed -n '/^apply_prefix_recipe() {$/,/^} # apply_prefix_recipe$/p' "$SRC")
[ -n "$hb_apply_fn" ] || { echo "FAIL: apply_prefix_recipe not found"; exit 1; }
eval "$hb_apply_fn"
without_lock_fds() { "$@"; }
mkdir -p "$WINEPREFIX/drive_c"
# The marker lives inside the prefix, so Rebuild Prefix (which replaces pfx) takes it along
hb_marker="$WINEPREFIX/protonish-recipe"
hb_reg="$WINEPREFIX/drive_c/protonish-recipe.reg"
fake_wine() { printf '#!/bin/sh\necho "wine: $*" >> "%s"\nexit %s\n' "$log" "$1" > "$hb/wine"; chmod +x "$hb/wine"; }
WINELOADER="$hb/wine"
reset_recipe() { reset_hb; np_hb_recipe=""; np_hb_partial=0; rm -f "$hb_marker" "$hb_reg"; }

reset_recipe
STEAM_COMPAT_INSTALL_PATH="$hb/Portal 2"; mkdir -p "$STEAM_COMPAT_INSTALL_PATH"
# shellcheck disable=SC2016 # Single quotes keep the helper's text literal.
helper 'echo "args: $*" >&2; echo "# recipe: portal-2 483aac46 x64-crossover26.3-r19"; echo "# note: recipe portal-2: 1 registry value, 1 file, 0 copies"; echo "GST_PLUGIN_PATH=/HB/gst"'
highball_environment
is "the game folder is passed as the install path" "1" "$(grep -c -- "--install-path $hb/Portal 2 " "$log")"
is "the recipe line is kept for the import" "portal-2 483aac46 x64-crossover26.3-r19" "$np_hb_recipe"
is "the recipe line is not exported" "" "${recipe:-}"
unset -v STEAM_COMPAT_INSTALL_PATH

printf 'Windows Registry Editor Version 5.00\r\n' > "$hb_reg"
fake_wine 0
apply_prefix_recipe
is "the registry file is imported through C:" "1" "$(grep -c 'wine: reg import C:\\protonish-recipe.reg' "$log")"
is "the marker holds recipe, commit and engine" "portal-2 483aac46 x64-crossover26.3-r19" "$(tr '\n' ' ' < "$hb_marker" | sed 's/ $//')"
is "the marker is inside the prefix" "$WINEPREFIX/protonish-recipe" "$hb_marker"
is "the registry file is removed after the import" "no" "$([ -e "$hb_reg" ] && echo yes || echo no)"

reset_recipe
# shellcheck disable=SC2016 # Single quotes keep the helper's text literal.
helper 'echo "# recipe: portal-2 483aac46 x64-crossover26.3-r19 partial"'
highball_environment
is "a partial recipe keeps its three words" "portal-2 483aac46 x64-crossover26.3-r19" "$np_hb_recipe"
is "a partial recipe is flagged" "1" "$np_hb_partial"
printf 'Windows Registry Editor Version 5.00\r\n' > "$hb_reg"
fake_wine 0
apply_prefix_recipe
is "a partial recipe still imports its registry file" "1" "$(grep -c 'wine: reg import' "$log")"
is "a partial recipe writes no marker" "no" "$([ -e "$hb_marker" ] && echo yes || echo no)"
is "a partial recipe is logged as tried again" "1" "$(grep -c 'recipe: portal-2 483aac46 x64-crossover26.3-r19 not recorded, a step failed' "$log")"

reset_recipe
# shellcheck disable=SC2016 # Single quotes keep the helper's text literal.
helper 'echo "# recipe: portal-2  x64-crossover26.3-r19"'
highball_environment
is "a recipe line with an empty word is refused" "" "$np_hb_recipe"

reset_recipe
# shellcheck disable=SC2016 # Single quotes keep the helper's text literal.
helper 'echo "# recipe: portal-2 483aac46 x64-crossover26.3-r19 extra"'
highball_environment
is "a recipe line with an unknown fourth word is refused" "" "$np_hb_recipe"

reset_recipe
np_hb_recipe="portal-2 483aac46 x64-crossover26.3-r19"
printf 'Windows Registry Editor Version 5.00\r\n' > "$hb_reg"
fake_wine 1
apply_prefix_recipe
is "a failed import writes no marker" "no" "$([ -e "$hb_marker" ] && echo yes || echo no)"
is "a failed import is logged" "1" "$(grep -c 'recipe: registry import exited status=1' "$log")"

reset_recipe
np_hb_recipe="warframe 483aac46 x64-crossover26.3-r19"
fake_wine 0
apply_prefix_recipe
is "a recipe without registry values still gets its marker" "warframe" "$(head -1 "$hb_marker")"
is "nothing is imported without a registry file" "0" "$(grep -c 'wine: reg import' "$log")"

reset_recipe
printf 'stale\r\n' > "$hb_reg"
fake_wine 0
apply_prefix_recipe
is "a stale registry file is removed when no recipe applies" "no" "$([ -e "$hb_reg" ] && echo yes || echo no)"
is "a stale registry file is never imported" "0" "$(grep -c 'wine: reg import' "$log")"

reset_recipe
printf 'skip\n' > "$np_support/recipe-other-engines"
# shellcheck disable=SC2016 # Single quotes keep the helper's text literal.
helper 'echo "args: $*" >&2'
highball_environment
is "the switch file reaches the helper" "1" "$(grep -c -- '--other-engines skip' "$log")"
rm -f "$np_support/recipe-other-engines"
unset -v GST_PLUGIN_PATH CX_D3DMETALPATH HB_VALUE

reset_hb
rm -f "$np_support/highball-env"
highball_environment
is "without the helper the DXMT default stays" "/fallback/dxmt" "$WINEDLLPATH_PREPEND"
is "without the helper the launcher has no Highball file" "" "$np_hb_env_file"

reset_hb
helper 'echo "GST_PLUGIN_PATH=/HB/gst"; exit 1'
highball_environment
is "a failing helper leaves the DXMT default" "/fallback/dxmt" "$WINEDLLPATH_PREPEND"
is "a failing helper exports nothing" "" "${GST_PLUGIN_PATH:-}"

reset_hb
helper 'echo "# error: engine x64-crossover26.3-r19 not found"'
highball_environment
is "a helper with only an error keeps the DXMT default" "/fallback/dxmt" "$WINEDLLPATH_PREPEND"
is "the error is logged" "1" "$(grep -c 'highball-env: error: engine' "$log")"

reset_hb
helper 'echo "# note: renderer wined3d"; echo "CX_FWD_COMPAT_GL_CTX=1"'
highball_environment
is "WineD3D from Highball leaves no renderer folder" "" "${WINEDLLPATH_PREPEND:-}"

reset_hb
helper 'sleep 30; echo "GST_PLUGIN_PATH=/HB/gst"'
# shellcheck disable=SC2329 # Called by highball_environment's wait loop.
sleep() { :; }
highball_environment
unset -f sleep
is "a helper that hangs is given up on" "/fallback/dxmt" "$WINEDLLPATH_PREPEND"
is "the timeout is logged" "1" "$(grep -c 'no answer in 10 s' "$log")"

echo "== Renderer report after the game exits =="
hb_report_fn=$(sed -n '/^highball_renderer_report() {$/,/^} # highball_renderer_report$/p' "$SRC")
[ -n "$hb_report_fn" ] || { echo "FAIL: highball_renderer_report not found"; exit 1; }
eval "$hb_report_fn"
hb_logdir="$WINEPREFIX/drive_c/highball/logs"
mkdir -p "$hb_logdir"
printf 'info:  old run\n' > "$hb_logdir/Old_d3d11.log"
touch -t 202001010000 "$hb_logdir/Old_d3d11.log"
np_hb_launch_mark="$STEAM_COMPAT_DATA_PATH/protonish-launch.mark"
touch -t 202001010001 "$np_hb_launch_mark"
printf 'warn:  D3D11CoreCreateDevice: Adapter is not a DXVK adapter\ninfo:  Game: Game.exe\ninfo:  DXVK-Kegworks: v1.10.4-async\n' > "$hb_logdir/Game_d3d11.log"
: > "$hb_logdir/Game_dxgi.log"
: > "$log"
highball_renderer_report
is "the DXVK log is reported by its version line" "1" "$(grep -c 'renderer report: Game_d3d11.log: info:  DXVK-Kegworks: v1.10.4-async' "$log")"
is "an empty log is reported as empty" "1" "$(grep -c 'renderer report: Game_dxgi.log: empty' "$log")"
is "logs from earlier launches are left out" "0" "$(grep -c 'Old_d3d11' "$log")"
is "the launch marker is removed" "no" "$([ -e "$np_hb_launch_mark" ] && echo yes || echo no)"
unset -v STEAM_COMPAT_DATA_PATH WINEPREFIX app_id log np_hb_env_file
rm -rf "$hb"

echo "== Wine's server directory permissions =="
tighten=$(sed -n '/^tighten_wine_tmp() {$/,/^}$/p' "$SRC")
[ -n "$tighten" ] || { echo "FAIL: tighten_wine_tmp not found"; exit 1; }
eval "$tighten"
wt=$(mktemp -d)
log="$wt/run.log"
mkdir -m 755 "$wt/.wine-test"
tighten_wine_tmp "$wt/.wine-test"
is "an open server directory is tightened to 700" "drwx------" "$(stat -f %Sp "$wt/.wine-test")"
is "the fix is logged" "1" "$(grep -c 'tightened' "$log")"
tighten_wine_tmp "$wt/.wine-missing"
is "a missing directory is left for wineserver to create" "no" "$([ -e "$wt/.wine-missing" ] && echo yes || echo no)"
rm -rf "$wt"

echo "== Apple GPTK initialization and launcher environment =="
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
np_support="$work/Application Support/protonish"
np_build="test"
np_runtime=crossover
library="$np_support/runners/crossover-$np_build/root/lib64/apple_gptk/external/libd3dshared.dylib"
init=$(sed -n '/^CX_ROOT=/,/^wine_unix=/p' "$SRC")
# shellcheck disable=SC2016 # Match the literal launcher loop.
forward=$(sed -n '/^for name in $(env /,/^done$/p' "$SRC")
[ -n "$init" ] && [ -n "$forward" ] || { echo "FAIL: runner environment blocks not found"; exit 1; }
unset CX_APPLEGPTK_LIBD3DSHARED_PATH
eval "$init"
is "runner without the library leaves the path unset" "" "${CX_APPLEGPTK_LIBD3DSHARED_PATH:-}"
mkdir -p "$(dirname "$library")"
: > "$library"
eval "$init"
is "bundled library is selected" "$library" "${CX_APPLEGPTK_LIBD3DSHARED_PATH:-}"
is "helpers inherit the library path" "$library" "$(sh -c 'printf %s "$CX_APPLEGPTK_LIBD3DSHARED_PATH"')"
set --
eval "$forward"
forwarded=""
for arg in "$@"; do
  case "$arg" in CX_APPLEGPTK_LIBD3DSHARED_PATH=*) forwarded=${arg#*=} ;; esac
done
is "game launcher receives the path as one argument" "$library" "$forwarded"
# macOS sed stops at the first invalid UTF-8 value.
# shellcheck disable=SC2016 # The stub and loop expand inside the child shell.
after_bad=$(env -i PATH="$PATH" LANG=en_US.UTF-8 DXVK_HUD=1 sh -c '
  env() { printf "A_BAD=a\377b\nDXVK_HUD=1\n"; }
  f=$1; set --; eval "$f"; printf "%s " "$@"' sh "$forward")
is "settings after a non-UTF-8 value are forwarded" "--env DXVK_HUD=1 " "$after_bad"

echo "== Rosetta-only settings on arm64 Wine =="
drop=$(sed -n '/^np_dropped=""$/,/^fi$/p' "$SRC")
[ -n "$drop" ] || { echo "FAIL: the arm64 settings block was not found"; exit 1; }
defaults=$(sed -n '/^np_from_defaults() {$/,/^np_dropped=""$/p' "$SRC")
[ -n "$defaults" ] || { echo "FAIL: the defaults block was not found"; exit 1; }
verb=run
eval "$defaults"
drop_at=$(grep -n '^np_dropped=""$' "$SRC" | cut -d: -f1)
# shellcheck disable=SC2016 # Match the literal launcher loop.
forward_at=$(grep -n '^for name in $(env ' "$SRC" | cut -d: -f1)
[ "$drop_at" -lt "$forward_at" ] ||
  bad "the arm64 settings block runs before the forwarding loop" "< $forward_at" "$drop_at"
seen() { sh -c 'env | sed -nE "s/^(CX_GRAPHICS_BACKEND|D3DM_[A-Z0-9_]*|DXMT_[A-Z0-9_]*|ROSETTA_[A-Z0-9_]*)=.*/\1/p" | sort | tr "\n" " "'; }
for name in $(seen); do unset -v "$name"; done
CX_ROOT="/R R"
set_all() { export CX_GRAPHICS_BACKEND=d3dmetal D3DM_ENABLE_METALFX=1 ROSETTA_ADVERTISE_AVX=0 DXMT_CONFIG=x; }
set_all
wine_unix="/R R/lib/wine/x86_64-unix"
eval "$drop"
is "x86_64 Wine keeps every setting" \
  "CX_GRAPHICS_BACKEND D3DM_ENABLE_METALFX DXMT_CONFIG ROSETTA_ADVERTISE_AVX " "$(seen)"
is "x86_64 Wine logs nothing" "" "$np_dropped"
wine_unix="/R R/lib/wine/aarch64-unix"
eval "$drop"
is "D3DMetal and Rosetta settings leave the environment" "DXMT_CONFIG " "$(seen)"
is "the run log names what was ignored" \
  "CX_GRAPHICS_BACKEND=d3dmetal D3DM_ENABLE_METALFX ROSETTA_ADVERTISE_AVX" "$np_dropped"
set_all
export CX_GRAPHICS_BACKEND=dxmt
unset -v D3DM_ENABLE_METALFX ROSETTA_ADVERTISE_AVX
eval "$drop"
is "other backends stay" "CX_GRAPHICS_BACKEND DXMT_CONFIG " "$(seen)"
is "nothing to ignore logs nothing" "" "$np_dropped"
unset -v CX_GRAPHICS_BACKEND DXMT_CONFIG

echo "== Rosetta AVX =="
wine_unix="/R R/lib/wine/x86_64-unix"
eval "$drop"
is "x86_64 Wine turns it on" "1" "$ROSETTA_ADVERTISE_AVX"
is "the default is logged as the default" "default" "$avx_from"
is "helpers inherit it" "1" "$(sh -c 'printf %s "$ROSETTA_ADVERTISE_AVX"')"
ROSETTA_ADVERTISE_AVX=0
eval "$drop"
is "a launch option of 0 is kept" "0" "$ROSETTA_ADVERTISE_AVX"
is "a launch option is logged as one" "environment" "$avx_from"
ROSETTA_ADVERTISE_AVX=
eval "$drop"
is "an empty launch option turns it on" "1" "$ROSETTA_ADVERTISE_AVX"
wine_unix="/R R/lib/wine/aarch64-unix"
eval "$drop"
is "arm64 Wine leaves it unset" "unset" "${ROSETTA_ADVERTISE_AVX-unset}"

echo "== FEX reduced x87 precision =="
unset -v FEX_X87REDUCEDPRECISION
wine_unix="/R R/lib/wine/x86_64-unix"
eval "$drop"
is "x86_64 Wine leaves it unset" "unset" "${FEX_X87REDUCEDPRECISION-unset}"
wine_unix="/R R/lib/wine/aarch64-unix"
eval "$drop"
is "arm64 Wine turns it on" "1" "$FEX_X87REDUCEDPRECISION"
is "the default is logged as the default" "default" "$fex_from"
is "helpers inherit it" "1" "$(sh -c 'printf %s "$FEX_X87REDUCEDPRECISION"')"
FEX_X87REDUCEDPRECISION=0
eval "$drop"
is "a launch option of 0 is kept" "0" "$FEX_X87REDUCEDPRECISION"
is "a launch option is logged as one" "environment" "$fex_from"
FEX_X87REDUCEDPRECISION=
eval "$drop"
is "an empty launch option is kept" "" "$FEX_X87REDUCEDPRECISION"
export FEX_X87REDUCEDPRECISION=0 FEX_MULTIBLOCK=0
set --
eval "$forward"
fex_args=""
for arg in "$@"; do
  case "$arg" in FEX_*) fex_args="$fex_args$arg
" ;; esac
done
is "FEX settings reach the game" "FEX_MULTIBLOCK=0 FEX_X87REDUCEDPRECISION=0 " "$(printf %s "$fex_args" | sort | tr '\n' ' ')"
unset -v FEX_X87REDUCEDPRECISION FEX_MULTIBLOCK

echo "== Default Compatibility Settings =="
mkdir -p "$np_support"
cat > "$np_support/defaults-rosetta" <<'EOF'
MTL_HUD_ENABLED=1
WINEMSYNC=1
ROSETTA_ADVERTISE_AVX=0
CX_GRAPHICS_BACKEND=dxmt
DXMT_CONFIG=d3d11.metalSpatialUpscaleFactor=1.5
FEX_X87REDUCEDPRECISION=0
CX_GRAPHICS_BACKEND=vulkan
NOTPROTON_RETINA=yes
DXMT_CONFIG=d3d11.metalSpatialUpscaleFactor=1;touch x
WINEDEBUG=+all
FOO=$(touch "$work/ran")

EOF
printf 'D3DM_ENABLE_METALFX=1\nCX_GRAPHICS_BACKEND=d3dmetal\nWINEMSYNC=1\nFEX_X87REDUCEDPRECISION=0' \
  > "$np_support/defaults-fex"
keys="MTL_HUD_ENABLED WINEMSYNC ROSETTA_ADVERTISE_AVX CX_GRAPHICS_BACKEND DXMT_CONFIG \
FEX_X87REDUCEDPRECISION NOTPROTON_RETINA D3DM_ENABLE_METALFX WINEDEBUG FOO"
clear() { for k in $keys; do unset -v "$k"; done; }
clear
wine_unix="/R R/lib/wine/x86_64-unix"
verb=waitforexitandrun
eval "$defaults"
is "unset settings take the default" "1 1 0 dxmt" \
  "$MTL_HUD_ENABLED $WINEMSYNC $ROSETTA_ADVERTISE_AVX $CX_GRAPHICS_BACKEND"
is "the default factor is the DXMT_CONFIG" "d3d11.metalSpatialUpscaleFactor=1.5" "${DXMT_CONFIG-}"
is "the game gets them" "1" "$(sh -c 'printf %s "$MTL_HUD_ENABLED"')"
is "lines that are not settings for this runner are skipped" "unset unset unset unset" \
  "${FEX_X87REDUCEDPRECISION-unset} ${NOTPROTON_RETINA-unset} ${WINEDEBUG-unset} ${FOO-unset}"
is "nothing in the file runs" "absent" "$([ -e "$work/ran" ] && echo ran || echo absent)"
is "the run log names what came from the defaults" \
  "MTL_HUD_ENABLED=1 WINEMSYNC=1 ROSETTA_ADVERTISE_AVX=0 CX_GRAPHICS_BACKEND=dxmt DXMT_CONFIG=d3d11.metalSpatialUpscaleFactor=1.5" \
  "$np_defaulted"
is "the run log names the file" "defaults-rosetta" "${np_defaults_file##*/}"
eval "$drop"
is "a defaulted AVX2 is logged as one" "defaults-rosetta" "$avx_from"
is "a defaulted AVX2 keeps its 0" "0" "$ROSETTA_ADVERTISE_AVX"
if np_from_defaults WINEMSYNC; then msync=yes; else msync=no; fi
is "MSync knows it came from the defaults" "yes" "$msync"

clear
export MTL_HUD_ENABLED=0 CX_GRAPHICS_BACKEND=auto DXMT_CONFIG="d3d11.preferredMaxFrameRate=60" ROSETTA_ADVERTISE_AVX=1
eval "$defaults"
is "the game's settings win" "0 1" "$MTL_HUD_ENABLED $ROSETTA_ADVERTISE_AVX"
is "the game's Automatic wins and leaves the backend unset" "unset" "${CX_GRAPHICS_BACKEND-unset}"
is "the default factor joins the game's DXMT_CONFIG" \
  "d3d11.preferredMaxFrameRate=60;d3d11.metalSpatialUpscaleFactor=1.5" "$DXMT_CONFIG"
eval "$drop"
is "a game AVX2 is logged as the game's" "environment" "$avx_from"
if np_from_defaults MTL_HUD_ENABLED; then hud=yes; else hud=no; fi
is "a game setting is not from the defaults" "no" "$hud"
clear
export DXMT_CONFIG="a=1; d3d11.metalSpatialUpscaleFactor = 3.0"
eval "$defaults"
is "the game's factor wins" "a=1; d3d11.metalSpatialUpscaleFactor = 3.0" "$DXMT_CONFIG"
clear
cp "$np_support/defaults-rosetta" "$work/rosetta.keep"
printf 'DXMT_CONFIG=d3d11.metalSpatialUpscaleFactor=.\nDXMT_CONFIG=d3d11.metalSpatialUpscaleFactor=1234567\nDXMT_CONFIG=d3d11.metalSpatialUpscaleFactor=\n' \
  > "$np_support/defaults-rosetta"
eval "$defaults"
is "factors the Settings page would refuse are skipped" "unset" "${DXMT_CONFIG-unset}"
mv "$work/rosetta.keep" "$np_support/defaults-rosetta"

clear
verb=run
eval "$defaults"
is "helpers get no defaults" "unset" "${MTL_HUD_ENABLED-unset}"

clear
verb=waitforexitandrun
wine_unix="/R R/lib/wine/aarch64-unix"
eval "$defaults"
is "arm64 Wine reads the FEX file" "defaults-fex" "${np_defaults_file##*/}"
is "a last line without a newline is read" "1 0" "$WINEMSYNC $FEX_X87REDUCEDPRECISION"
is "FEX skips the Rosetta-only settings" "unset unset" "${D3DM_ENABLE_METALFX-unset} ${CX_GRAPHICS_BACKEND-unset}"
eval "$drop"
is "a defaulted x87 is logged as one" "defaults-fex" "$fex_from"
clear
rm -f "$np_support/defaults-fex"
eval "$defaults"
is "no file sets nothing" "unset" "${WINEMSYNC-unset}"
printf 'WINEMSYNC=1\n' > "$np_support/defaults-fex"
chmod 000 "$np_support/defaults-fex"
for sh in /bin/sh /bin/dash; do
  [ -x "$sh" ] || continue
  # shellcheck disable=SC2016
  is "an unreadable file is skipped by $sh, the launch goes on" "went on unset" \
    "$(np_support="$np_support" wine_unix="$wine_unix" verb="$verb" np_block="$defaults" \
      "$sh" -c 'set -e; eval "$np_block"; echo "went on ${WINEMSYNC-unset}"' 2>/dev/null)"
done
chmod 644 "$np_support/defaults-fex"
rm -f "$np_support/defaults-fex"

echo "== Per-build defaults =="
printf 'WINEMSYNC=1\nFEX_X87REDUCEDPRECISION=0\n' > "$np_support/defaults-fex"
printf 'MTL_HUD_ENABLED=1\nFEX_X87REDUCEDPRECISION=1\n' > "$np_support/defaults-override-26.1-fex"
printf 'NOTPROTON_RETINA=1\n' > "$np_support/defaults-override-26.1-rosetta"
clear; unset -v MTL_HUD_ENABLED NOTPROTON_RETINA
np_build=26.1 np_flavor=fex
eval "$defaults"
is "a build's own file replaces the runner's" "defaults-override-26.1-fex" "${np_defaults_file##*/}"
is "the build's settings apply, the runner's do not" "1 1 unset" \
  "${MTL_HUD_ENABLED-unset} $FEX_X87REDUCEDPRECISION ${WINEMSYNC-unset}"
clear; unset -v MTL_HUD_ENABLED
np_build=27.0
eval "$defaults"
is "a build without its own file, like a new one, uses the runner's" "defaults-fex 1" \
  "${np_defaults_file##*/} ${WINEMSYNC-unset}"
clear
: > "$np_support/defaults-override-27.0-fex"
eval "$defaults"
is "an empty build file means no defaults for that build" "unset" "${WINEMSYNC-unset}"
rm -f "$np_support/defaults-override-27.0-fex"
clear; unset -v NOTPROTON_RETINA
np_build=26.1 np_flavor=rosetta wine_unix="/R R/lib/wine/x86_64-unix"
eval "$defaults"
is "the same build on Rosetta reads its Rosetta file" "defaults-override-26.1-rosetta 1" \
  "${np_defaults_file##*/} ${NOTPROTON_RETINA-unset}"
clear; unset -v NOTPROTON_RETINA
np_build="" np_flavor=""
eval "$defaults"
is "no build reads the runner's file" "defaults-rosetta" "${np_defaults_file##*/}"
clear
np_build=27.0 np_flavor=fex
eval "$defaults"
is "a FEX tool on x86 Wine still reads the FEX file the page shows" "defaults-fex" "${np_defaults_file##*/}"
is "and still skips what x86 Wine cannot take" "unset" "${FEX_X87REDUCEDPRECISION-unset}"
rm -f "$np_support/defaults-fex" "$np_support/defaults-override-26.1-fex" "$np_support/defaults-override-26.1-rosetta"
unset -v np_build np_flavor
clear; unset -v MTL_HUD_ENABLED NOTPROTON_RETINA
verb=run

echo "== MSync carry-over =="
msync=$(sed -n '/^  msync_from=environment$/,/notproton-msync" 2>\/dev\/null || true$/p' "$SRC")
[ -n "$msync" ] || { echo "FAIL: the MSync block was not found"; exit 1; }
STEAM_COMPAT_DATA_PATH="$work/compat"
mkdir -p "$STEAM_COMPAT_DATA_PATH"
printf 1 > "$STEAM_COMPAT_DATA_PATH/notproton-msync"
np_defaulted="" WINEMSYNC="" verb=waitforexitandrun
eval "$msync"
is "a game without MSync set does not inherit its last launch" "0 default" "$WINEMSYNC $msync_from"
is "and helpers then follow it" "0" "$(cat "$STEAM_COMPAT_DATA_PATH/notproton-msync")"
printf 1 > "$STEAM_COMPAT_DATA_PATH/notproton-msync"
WINEMSYNC="" verb=run
eval "$msync"
is "a helper follows the game's last launch" "1 carried-over" "$WINEMSYNC $msync_from"
unset -v STEAM_COMPAT_DATA_PATH WINEMSYNC
verb=run

if [ "$fails" -eq 0 ]; then
	echo "==> envcheck: all assertions hold"
else
	echo "==> envcheck: $fails failed"
	exit 1
fi
