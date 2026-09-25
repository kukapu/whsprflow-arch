#!/usr/bin/env bash

set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for script in "$root/install.sh" "$root/uninstall.sh" "$root/bin/wispr-flow" \
	"$root/bin/wispr-flow-configure" "$root/patches/linux-runtime-fixes.sh" \
	"$root/patches/helper-env-fallback.sh" \
	"$root/patches/helper-resolver-fallback.sh" \
	"$root/patches/window-frame-fallback.sh" \
	"$root/scripts/assemble-app.sh" "$root/scripts/build-helper.sh"; do
	bash -n "$script"
done

python3 "$root/tests/patch-fallbacks.py"

aur_dir="$root/packaging/aur"
pkgbuild="$aur_dir/PKGBUILD"
bash -n "$pkgbuild"
bash -n "$aur_dir/wispr-flow-hyprland.install"

support_commit='d092cfb3344715fcd794091feea9b1dd678df26b'
support_sha256='e7433c7291a1828da4572cbfb1e93d7bbe754400bf17a90fbbd1385e599f545c'
bash -c '
	set -Eeuo pipefail
	CARCH=x86_64
	source "$1"
	support_commit="$2"
	support_sha256="$3"
	[[ $pkgname == wispr-flow-hyprland ]]
	[[ $pkgver == 1.6.774 && $pkgrel == 1 ]]
	[[ ${arch[*]} == x86_64 ]]
	[[ $url == https://github.com/kukapu/whsprflow-arch ]]
	[[ ${license[*]} == "0BSD AND BSD-3-Clause AND LicenseRef-Proprietary AND MIT AND Unlicense" ]]
	[[ ${provides[*]} == "wispr-flow=1.6.774" ]]
	[[ ${conflicts[*]} == wispr-flow ]]
	[[ -z ${replaces+x} ]]
	[[ ${options[*]} == "!strip !debug" ]]
	[[ $install == wispr-flow-hyprland.install ]]
	[[ $_support_commit == "$support_commit" ]]
	[[ ${sha256sums[0]} == "$support_sha256" ]]
	[[ ${#source[@]} -eq ${#sha256sums[@]} ]]
	[[ ${noextract[*]} == "WisprFlow-1.6.774-full.nupkg electron-v42.3.0-linux-x64.zip" ]]
	for dependency in hicolor-icon-theme hyprland libcups libgcc libstdc++ nodejs pango; do
		[[ " ${depends[*]} " == *" $dependency "* ]]
	done
	for dependency in asar perl python unzip; do
		[[ " ${makedepends[*]} " == *" $dependency "* ]]
	done
	[[ " ${makedepends[*]} " != *" nodejs "* ]]
	[[ ${optdepends[*]} == uwsm:* ]]
' _ "$pkgbuild" "$support_commit" "$support_sha256"

pkg_functions="$(bash -c 'source "$1"; declare -f build package' _ "$pkgbuild")"
if grep -Eiq '(^|[^[:alnum:]_])(sudo|pacman|curl|wget)([^[:alnum:]_]|$)|git[[:space:]]+clone|/usr/local|/home/|\$\{?HOME' \
		<<< "$pkg_functions"; then
	printf 'ERROR: build/package contiene una operacion prohibida.\n' >&2
	exit 1
fi
grep -qF -- '--asar-bin /usr/bin/asar' <<< "$pkg_functions"
grep -qF '"$srcdir/' <<< "$pkg_functions"
! grep -qF '/opt/' <<< "$(bash -c 'source "$1"; declare -f build' _ "$pkgbuild")"
! grep -qF '/usr/local' "$pkgbuild"
! grep -qF '/home/' "$pkgbuild"
placeholder='TO_BE_''PINNED'
if grep -r -I -q --exclude-dir=.git --exclude-dir=src --exclude-dir=pkg \
		--exclude='wispr-flow-linux-helper-x86_64' \
		-- "$placeholder" "$root"; then
	printf 'ERROR: quedan placeholders del pin AUR.\n' >&2
	exit 1
fi

sha256sum "$aur_dir/wispr-flow.desktop" \
	| grep -q '^3b65d10698a9c944c5494cfd9a5fa3f04dd7b5a02f8fce0ace9333b6f1646ba5 '
sha256sum "$aur_dir/70-wispr-flow-input.rules" \
	| grep -q '^3d7d9cab9b2af22cfd60b0dd965ff1b0f6e315e03c203add9f9646ae320bb97d '

if command -v desktop-file-validate >/dev/null 2>&1; then
	desktop-file-validate "$aur_dir/wispr-flow.desktop"
fi

if command -v makepkg >/dev/null 2>&1; then
	srcinfo="$(cd "$aur_dir" && makepkg --printsrcinfo)"
	[[ -f $aur_dir/.SRCINFO ]]
	cmp -s <(printf '%s\n' "$srcinfo") "$aur_dir/.SRCINFO"
	grep -qxF 'pkgbase = wispr-flow-hyprland' <<< "$srcinfo"
	grep -qxF 'pkgname = wispr-flow-hyprland' <<< "$srcinfo"
	grep -qxF $'\tprovides = wispr-flow=1.6.774' <<< "$srcinfo"
	grep -qxF $'\tconflicts = wispr-flow' <<< "$srcinfo"
	! grep -q 'replaces = ' <<< "$srcinfo"
fi

python3 - "$root/REUSE.toml" "$aur_dir/REUSE.toml" <<'PY'
import pathlib
import sys
import tomllib

for value in sys.argv[1:]:
    data = tomllib.loads(pathlib.Path(value).read_text())
    assert data["version"] == 1
    assert data["annotations"]
PY
cmp "$root/LICENSE" "$root/LICENSES/0BSD.txt"
cmp "$root/LICENSE" "$aur_dir/LICENSE"
cmp "$root/LICENSE" "$aur_dir/LICENSES/0BSD.txt"
cmp "$root/assets/UNLICENSE" "$root/LICENSES/Unlicense.txt"

assembler="$root/scripts/assemble-app.sh"
[[ -x $assembler ]]
assembler_help="$($assembler --help)"
for flag in --version --nupkg --electron-zip --sqlite --helper --port-dir \
	--output-dir --asar-bin; do
	grep -q -- "$flag" <<< "$assembler_help"
done
grep -qF 'por defecto: asar' <<< "$assembler_help"

assembler_home="$tmp/assembler-home"
if HOME="$assembler_home" "$assembler" >/dev/null 2>&1; then
	printf 'ERROR: el ensamblador debe rechazar flags requeridos ausentes.\n' >&2
	exit 1
fi
[[ ! -e $assembler_home ]]
if "$assembler" --version >/dev/null 2>&1; then
	printf 'ERROR: un flag del ensamblador sin valor debe fallar.\n' >&2
	exit 1
fi

mkdir "$tmp/existing-runtime"
if "$assembler" \
		--version 1.0.0 \
		--nupkg /dev/null \
		--electron-zip /dev/null \
		--sqlite /dev/null \
		--helper /dev/null \
		--port-dir "$tmp" \
		--output-dir "$tmp/existing-runtime" \
		--asar-bin /bin/true >"$tmp/assembler.out" 2>"$tmp/assembler.err"; then
	printf 'ERROR: el ensamblador debe rechazar un output existente.\n' >&2
	exit 1
fi
grep -qF 'directorio de salida ya existe' "$tmp/assembler.err"
! grep -qF 'pnpm dlx' "$assembler"
grep -qF 'scripts/assemble-app.sh' "$root/install.sh"
grep -qF -- '--asar-bin /usr/bin/asar' "$root/install.sh"
grep -qF '/opt/wispr-flow-hyprland/usr/lib/wispr-flow/wispr-flow' \
	"$root/bin/wispr-flow"

sha256sum "$root/patches/helper/uinput.rs" \
	| grep -q '^e0ac469f0d3c6227802d7beb364b16b3b52f12b6838df35bae7e9950ab5cc919 '
sha256sum "$root/assets/wispr-flow-linux-helper-x86_64" \
	| grep -q '^5f069506ccf51964f05ba6b06b7a1bfbb42cd2a5d64437c965abba628c4b45b0 '
file "$root/assets/wispr-flow-linux-helper-x86_64" | grep -q 'ELF 64-bit.*x86-64'

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" bootstrap

config="$tmp/config/Wispr Flow/config.json"
jq -e '
	.prefs.user.hideFlowBarPermanently == false and
	.prefs.user.shortcuts["160+162"] == "ptt" and
	(.prefs.cache.splitKeybinds | any(.value == "ptt" and .shortcut == [160, 162]))
' "$config" >/dev/null

jq '
	.prefs.user.shortcuts = {"162+91": "ptt"} |
	.prefs.cache.splitKeybinds = [{shortcut: [162, 91], value: "ptt"}]
' "$config" > "$tmp/custom-shortcut.json"
mv "$tmp/custom-shortcut.json" "$config"

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" bootstrap --hide-flow-bar

jq -e '
	.prefs.user.shortcuts["162+91"] == "ptt" and
	.prefs.user.modifierShortcut == "164" and
	.prefs.user.hideFlowBarPermanently == true and
	(.prefs.cache.splitKeybinds | any(.value == "ptt" and .shortcut == [162, 91]))
' "$config" >/dev/null

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" fix-shortcut
jq -e '
	.prefs.user.shortcuts["160+162"] == "ptt" and
	(.prefs.cache.splitKeybinds | any(.value == "ptt" and .shortcut == [160, 162]))
' "$config" >/dev/null

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" flow-bar on
jq -e '.prefs.user.hideFlowBarPermanently == false' "$config" >/dev/null

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" check

mkdir -p "$tmp/config/hypr"
printf '# test hyprland config\n' > "$tmp/config/hypr/hyprland.conf"
printf '# test autostart config\n' > "$tmp/config/hypr/autostart.conf"

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules on
grep -qxF '# >>> whsprflow-arch rules >>>' "$tmp/config/hypr/hyprland.conf"
grep -qF 'match:class ^wispr-flow$, match:title ^((Flow )?Hub|Wispr Flow)$' "$tmp/config/hypr/wispr-flow.conf"

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" autostart on
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" autostart status
grep -qxF 'exec-once = uwsm-app -- wispr-flow --background' "$tmp/config/hypr/autostart.conf"

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" autostart off
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules off
! grep -qF 'whsprflow-arch' "$tmp/config/hypr/hyprland.conf"
[[ ! -e $tmp/config/hypr/wispr-flow.conf ]]

printf '# before\n%s\n# user setting\n' '# >>> whsprflow-arch rules >>>' \
	> "$tmp/config/hypr/hyprland.conf"
cp "$tmp/config/hypr/hyprland.conf" "$tmp/malformed.expected"
if HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules off 2>/dev/null; then
	printf 'ERROR: un bloque gestionado incompleto debe rechazarse.\n' >&2
	exit 1
fi
cmp "$tmp/malformed.expected" "$tmp/config/hypr/hyprland.conf"

rm -f "$tmp/config/hypr/hyprland.conf"
printf '# symlinked config\n' > "$tmp/config/hypr/hyprland.real.conf"
ln -s hyprland.real.conf "$tmp/config/hypr/hyprland.conf"
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules on
[[ -L $tmp/config/hypr/hyprland.conf ]]
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules off
[[ -L $tmp/config/hypr/hyprland.conf ]]
! grep -qF 'whsprflow-arch' "$tmp/config/hypr/hyprland.real.conf"

printf '# user-owned rules\n' > "$tmp/config/hypr/wispr-flow.conf"
cp "$tmp/config/hypr/wispr-flow.conf" "$tmp/rules.expected"
if HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules on 2>/dev/null; then
	printf 'ERROR: las reglas ajenas no deben sobrescribirse.\n' >&2
	exit 1
fi
cmp "$tmp/rules.expected" "$tmp/config/hypr/wispr-flow.conf"
rm "$tmp/config/hypr/wispr-flow.conf"

printf '# autostart\n' > "$tmp/config/hypr/autostart.conf"
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" autostart on
rm "$tmp/config/hypr/hyprland.conf"
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" autostart off
! grep -qF 'whsprflow-arch' "$tmp/config/hypr/autostart.conf"

printf '%s\n' '-- entrada lua de prueba' > "$tmp/config/hypr/hyprland.lua"

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules on
grep -qxF -- '-- >>> whsprflow-arch rules >>>' "$tmp/config/hypr/hyprland.lua"
grep -qF "dofile(\"$tmp/config/hypr/wispr-flow.lua\")" "$tmp/config/hypr/hyprland.lua"
grep -qF 'match = { class = "^wispr-flow$", title = "^((Flow )?Hub|Wispr Flow)$" }' \
	"$tmp/config/hypr/wispr-flow.lua"
grep -qF 'size = { 1350, 850 }' "$tmp/config/hypr/wispr-flow.lua"
grep -qF 'border_size = 0' "$tmp/config/hypr/wispr-flow.lua"

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules check

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules off
! grep -qF 'whsprflow-arch' "$tmp/config/hypr/hyprland.lua"
[[ ! -e $tmp/config/hypr/wispr-flow.lua ]]

cat > "$tmp/config/hypr/hyprland.conf" <<'EOF'
# >>> whsprflow-arch rules >>>
source = wispr-flow.conf
# <<< whsprflow-arch rules <<<
EOF
printf '%s\n' '# Managed by whsprflow-arch. Only the real Flow Hub is affected.' \
	'windowrule = float on, match:class ^wispr-flow$, match:title ^(Flow )?Hub$' \
	> "$tmp/config/hypr/wispr-flow.conf"
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules on
! grep -qF 'whsprflow-arch' "$tmp/config/hypr/hyprland.conf"
[[ ! -e $tmp/config/hypr/wispr-flow.conf ]]
[[ -f $tmp/config/hypr/wispr-flow.lua ]]

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" autostart on
grep -qF 'hl.exec_cmd("uwsm-app -- wispr-flow --background")' "$tmp/config/hypr/hyprland.lua"
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" autostart status
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" autostart off
! grep -qF 'whsprflow-arch' "$tmp/config/hypr/hyprland.lua"

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules off

printf '%s\n' '-- reglas propias del usuario' > "$tmp/config/hypr/wispr-flow.lua"
if HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
		"$root/bin/wispr-flow-configure" hyprland-rules on 2>/dev/null; then
	printf 'ERROR: las reglas Lua ajenas no deben sobrescribirse.\n' >&2
	exit 1
fi
grep -qxF -- '-- reglas propias del usuario' "$tmp/config/hypr/wispr-flow.lua"
rm -f "$tmp/config/hypr/wispr-flow.lua" "$tmp/config/hypr/hyprland.lua" \
	"$tmp/config/hypr/hyprland.conf"

cat > "$tmp/main.js" <<'EOF'
const G=()=>{const e=x.RA.statusWindow;e.showInactive(),a().info("Showing status window")};
Ye=(e=v.H8)=>{const t=ne.RA.statusWindow;if(!t||t.isDestroyed())return a().error("Status window is not available or destroyed. Recreating."),void(ne.RA.statusWindow=W());const n=t.isAlwaysOnTop(),r=t.isVisible();if(n&&r)e&&(t.setAlwaysOnTop(!0,"screen-saver"),t.showInactive());else{t.setAlwaysOnTop(!0,"screen-saver"),t.showInactive()}};
const start=e=>{(()=>{(0,ee.ui)(!0)})(e),ke(O._W.Listening),foo()};
const stop=e=>{ke(O._W.Stopping),Ve(e),foo()};
const te=e=>foo(e,A.tD,A.H8,570,u,480),ne=1;
const teInner=e=>{const{x:c,y:u,width:h,height:m}=p(e,t,r,i);return{x:c+(h-o)/2,y:u+m-s,width:o,height:s}};
const status=e=>{p.ZZ.status=e,p.ZZ.statusLastUpdatedTime=Date.now();const s=foo()};
const W=()=>{const e=i.screen.getDisplayNearestPoint(i.screen.getCursorScreenPoint()),t=te(e),n=new i.BrowserWindow({show:!1,webPreferences:{...m.g,preload:require("path").resolve(__dirname,"../renderer","status","preload.js"),backgroundThrottling:!1}},...t)};
const A1=n=>{n.setAlwaysOnTop(!0,"screen-saver"),n.setIgnoreMouseEvents(!0,{forward:!0}),A.tD&&n.setVisibleOnAllWorkspaces(!0,{vi:1})};
const ipc1=e=>{K||(e?Z(x.RA.statusWindow):V()?.setIgnoreMouseEvents(!0,{forward:!0}),(0,h.cA)(x.RA.statusWindow))};
const O=(t,n)=>{v()&&A===n&&!e.isDestroyed()&&e.setIgnoreMouseEvents(t,{forward:!0})};
const J=()=>{K||(K=!0,X(),x.RA.statusWindow&&!x.RA.statusWindow.isDestroyed()&&x.RA.statusWindow.setIgnoreMouseEvents(!0,{forward:!0}))};
EOF
"$root/patches/linux-runtime-fixes.sh" "$tmp/main.js"
"$root/patches/linux-runtime-fixes.sh" "$tmp/main.js"
grep -qF 'WISPR_LINUX_HIDE_STATUS_WINDOW_SHOW' "$tmp/main.js"
grep -qF '/*WISPR_LINUX_HIDE_STATUS_WINDOW_SHOW*/"1"===process.env.WISPR_FLOW_HIDE_STATUS_WINDOW?' "$tmp/main.js"
grep -qF 'WISPR_LINUX_HIDE_STATUS_WINDOW_DICTATION' "$tmp/main.js"
grep -qF 'WISPR_LINUX_LOCAL_START_SOUND' "$tmp/main.js"
grep -qF '"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&ne.RA.statusWindow?.showInactive()' "$tmp/main.js"
grep -qF 'WISPR_LINUX_LOCAL_STOP_SOUND' "$tmp/main.js"
grep -qF 'WISPR_LINUX_COMPACT_STATUS_WINDOW' "$tmp/main.js"
grep -qF 'WISPR_LINUX_TRANSIENT_STATUS_HIDE' "$tmp/main.js"
grep -qF 'WISPR_LINUX_STATUS_ZOOM' "$tmp/main.js"
grep -qF 'zoomFactor:process.env.WISPR_FLOW_STATUS_ZOOM' "$tmp/main.js"
grep -qF 'WISPR_LINUX_STATUS_GEOMETRY' "$tmp/main.js"
grep -qF 'WISPR_FLOW_STATUS_Y||"0.83"' "$tmp/main.js"
grep -qF '?{y:Math.round(u+m*parseFloat(process.env.WISPR_FLOW_STATUS_Y||"0.83")-s/2)}:{}' "$tmp/main.js"
grep -qF 'WISPR_LINUX_STATUS_INTERACTIVE' "$tmp/main.js"
grep -qF '"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&n.setIgnoreMouseEvents' "$tmp/main.js"
grep -qF 'WISPR_LINUX_STATUS_HITTEST' "$tmp/main.js"
grep -qF '(!t||"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE)&&e.setIgnoreMouseEvents(t' "$tmp/main.js"
grep -qF 'WISPR_LINUX_STATUS_TOUR' "$tmp/main.js"
grep -qF '"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&x.RA.statusWindow.setIgnoreMouseEvents' "$tmp/main.js"
grep -qF ':("1"===process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW?1:1.45)}' "$tmp/main.js"
grep -qF 'WISPR_FLOW_STATUS_ZOOM):1.45' "$tmp/main.js"
[[ $(grep -o 'WISPR_LINUX_' "$tmp/main.js" | wc -l) -eq 12 ]]

mkdir -p "$tmp/app/usr/lib/wispr-flow/resources/Release" "$tmp/fake-bin" "$tmp/home"
cat > "$tmp/app/usr/lib/wispr-flow/launcher-common.sh" <<'EOF'
setup_logging() { log_file="${TMPDIR:?}/wispr-flow-test.log"; }
setup_electron_env() { :; }
cleanup_stale_lock() { :; }
detect_display_backend() { :; }
check_display() { return 0; }
log_message() { :; }
log_session_env() { :; }
build_electron_args() {
	electron_args=()
	[[ ${WISPR_USE_WAYLAND:-0} == 1 ]] && electron_args+=(--wayland-test)
}
EOF
cat > "$tmp/app/usr/lib/wispr-flow/wispr-flow" <<'EOF'
#!/usr/bin/env bash
printf 'wayland=%s\nargs=%s\n' "${WISPR_USE_WAYLAND-unset}" "$*" > "${WISPR_TEST_OUTPUT:?}"
EOF
chmod +x "$tmp/app/usr/lib/wispr-flow/wispr-flow"
cat > "$tmp/fake-bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
[[ ${WISPR_TEST_HYPR_OFFLINE:-0} == 1 ]] && exit 1
case "$1" in
	clients) printf '[{"class":"wispr-flow","title":"Hub","address":"0x123","workspace":{"id":1,"name":"1"}}]\n' ;;
	dispatch) printf 'dispatch rejected\n' >&2; exit 1 ;;
	*) printf '{}\n' ;;
esac
EOF
chmod +x "$tmp/fake-bin/hyprctl"

cat > "$tmp/fake-bin/xdg-mime" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
	default)
		[[ $# -eq 3 ]]
		[[ $2 == wispr-flow.desktop ]]
		[[ $3 == x-scheme-handler/wispr-flow ]]
		printf '%s\n' "$2" > "${WISPR_TEST_XDG_DIR:?}/default"
		;;
	query)
		[[ ${2:-} == default ]]
		[[ ${3:-} == x-scheme-handler/wispr-flow ]]
		[[ -f ${WISPR_TEST_XDG_DIR:?}/default ]] && cat "$WISPR_TEST_XDG_DIR/default"
		;;
	*) exit 2 ;;
esac
EOF
cat > "$tmp/fake-bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo called\n' > "${WISPR_TEST_XDG_DIR:?}/sudo-called"
exit 99
EOF
chmod +x "$tmp/fake-bin/xdg-mime" "$tmp/fake-bin/sudo"

mkdir -p "$tmp/xdg-state"
printf '# setup Hyprland config\n' > "$tmp/config/hypr/hyprland.conf"
PATH="$tmp/fake-bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	XDG_CURRENT_DESKTOP=Hyprland HYPRLAND_INSTANCE_SIGNATURE=test \
	WISPR_FLOW_INSTALL_ROOT="$tmp/app" WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	WISPR_TEST_XDG_DIR="$tmp/xdg-state" \
	"$root/bin/wispr-flow" --setup
jq -e '.prefs.user.hideFlowBarPermanently == true' "$config" >/dev/null
grep -qxF 'wispr-flow.desktop' "$tmp/xdg-state/default"
grep -qxF '# >>> whsprflow-arch rules >>>' "$tmp/config/hypr/hyprland.conf"
[[ ! -e $tmp/xdg-state/sudo-called ]]

mkdir -p "$tmp/gnome-config" "$tmp/gnome-home" "$tmp/gnome-xdg-state"
PATH="$tmp/fake-bin:$PATH" HOME="$tmp/gnome-home" \
	XDG_CONFIG_HOME="$tmp/gnome-config" XDG_CURRENT_DESKTOP=GNOME \
	HYPRLAND_INSTANCE_SIGNATURE= WISPR_FLOW_INSTALL_ROOT="$tmp/app" \
	WISPR_TEST_XDG_DIR="$tmp/gnome-xdg-state" \
	"$root/bin/wispr-flow" --setup
jq -e '.prefs.user.hideFlowBarPermanently == false' \
	"$tmp/gnome-config/Wispr Flow/config.json" >/dev/null
[[ ! -e $tmp/gnome-config/hypr/wispr-flow.conf ]]
[[ ! -e $tmp/gnome-xdg-state/sudo-called ]]

printf '# offline Hyprland config\n' > "$tmp/config/hypr/hyprland.conf"
PATH="$tmp/fake-bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	WISPR_TEST_HYPR_OFFLINE=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules on
PATH="$tmp/fake-bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	WISPR_FLOW_SKIP_HYPR_RELOAD=1 \
	"$root/bin/wispr-flow-configure" hyprland-rules off

if PATH="$tmp/fake-bin:$PATH" HOME="$tmp/home" WISPR_FLOW_INSTALL_ROOT="$tmp/app" \
	"$root/bin/wispr-flow" --hide 2>/dev/null; then
	printf 'ERROR: --hide debe propagar un fallo de hyprctl.\n' >&2
	exit 1
fi

TMPDIR="$tmp" WISPR_TEST_OUTPUT="$tmp/electron.out" HOME="$tmp/home" \
	WISPR_FLOW_INSTALL_ROOT="$tmp/app" WISPR_FLOW_BACKEND=auto WISPR_USE_WAYLAND=1 \
	"$root/bin/wispr-flow"
grep -qxF 'wayland=unset' "$tmp/electron.out"
grep -qxF 'args=' "$tmp/electron.out"

jq '.prefs.user.hideFlowBarPermanently = false' "$config" > "$tmp/bar-config.json"
mv "$tmp/bar-config.json" "$config"
TMPDIR="$tmp" WISPR_TEST_OUTPUT="$tmp/electron-x11.out" HOME="$tmp/home" \
	XDG_CONFIG_HOME="$tmp/config" XDG_CURRENT_DESKTOP=Hyprland WAYLAND_DISPLAY=wayland-test \
	WISPR_FLOW_INSTALL_ROOT="$tmp/app" "$root/bin/wispr-flow"
grep -qF -- '--ozone-platform=x11' "$tmp/electron-x11.out"

jq '.prefs.user.hideFlowBarPermanently = true' "$config" > "$tmp/hidden-config.json"
mv "$tmp/hidden-config.json" "$config"
TMPDIR="$tmp" WISPR_TEST_OUTPUT="$tmp/electron-wayland.out" HOME="$tmp/home" \
	XDG_CONFIG_HOME="$tmp/config" XDG_CURRENT_DESKTOP=Hyprland WAYLAND_DISPLAY=wayland-test \
	WISPR_FLOW_INSTALL_ROOT="$tmp/app" "$root/bin/wispr-flow"
grep -qxF 'wayland=1' "$tmp/electron-wayland.out"
grep -qF -- '--wayland-test' "$tmp/electron-wayland.out"

TMPDIR="$tmp" WISPR_TEST_OUTPUT="$tmp/electron-transient.out" HOME="$tmp/home" \
	XDG_CONFIG_HOME="$tmp/config" XDG_CURRENT_DESKTOP=Hyprland WAYLAND_DISPLAY=wayland-test \
	WISPR_FLOW_INSTALL_ROOT="$tmp/app" WISPR_FLOW_TRANSIENT_STATUS_WINDOW=1 \
	"$root/bin/wispr-flow"
grep -qxF 'wayland=1' "$tmp/electron-transient.out"
grep -qF -- '--wayland-test' "$tmp/electron-transient.out"

TMPDIR="$tmp" WISPR_TEST_OUTPUT="$tmp/electron-no-status.out" HOME="$tmp/home" \
	XDG_CONFIG_HOME="$tmp/config" XDG_CURRENT_DESKTOP=Hyprland WAYLAND_DISPLAY=wayland-test \
	WISPR_FLOW_INSTALL_ROOT="$tmp/app" WISPR_FLOW_TRANSIENT_STATUS_WINDOW=0 \
	"$root/bin/wispr-flow"
grep -qxF 'wayland=1' "$tmp/electron-no-status.out"
grep -qF -- '--wayland-test' "$tmp/electron-no-status.out"

printf 'Smoke tests OK\n'
