#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly APP_VERSION='1.6.447'
readonly ELECTRON_VERSION='42.3.0'
readonly PORT_COMMIT='6fb43cd809f8319a9e05da4b4e7a2d3264c126ab'
readonly NUPKG_NAME="WisprFlow-${APP_VERSION}-full.nupkg"
readonly NUPKG_URL="https://dl.wisprflow.com/wispr-flow/win32/x64/${NUPKG_NAME}"
readonly NUPKG_SHA256='c5a6175c74028c30b11c9a96a295df1b47780929ceaf3753a96ffa855b591f03'
readonly ELECTRON_NAME="electron-v${ELECTRON_VERSION}-linux-x64.zip"
readonly ELECTRON_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/${ELECTRON_NAME}"
readonly ELECTRON_SHA256='487a667ca6a734b958c16cff1df74d9d44d2c18a6cccdb4dd51f6301a356c420'
readonly HELPER_NAME='wispr-flow-linux-helper-x86_64'
readonly HELPER_URL="https://github.com/wispr-flow-linux/helper/releases/download/v0.1.2/${HELPER_NAME}"
readonly HELPER_SHA256='66f6ee8232fa22ec419493f7dbc91f0fc636cd84cd668c1d935b3c1140db2658'
readonly SQLITE_NAME='node_sqlite3-x86_64.node'
readonly SQLITE_URL="https://github.com/wispr-flow-linux/native-modules/releases/download/native-v1/${SQLITE_NAME}"
readonly SQLITE_SHA256='c9bd0419f77efb3b5d3a691fda04e265f740ad8dc195f0b56003cdeac92e9a34'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/whsprflow-arch"
system_install=true
system_setup=true

usage() {
	cat <<'EOF'
Uso: ./install.sh [--user] [--no-system-setup]

  --user             Instala la aplicacion en ~/.local/share (sin sandbox SUID).
  --no-system-setup  No instala paquetes, reglas udev ni permisos de entrada.
  -h, --help         Muestra esta ayuda.
EOF
}

while (($#)); do
	case "$1" in
		--user) system_install=false ;;
		--no-system-setup) system_setup=false ;;
		-h|--help) usage; exit 0 ;;
		*) printf 'Opcion desconocida: %s\n' "$1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

info() {
	printf '\n==> %s\n' "$*"
}

have() {
	command -v "$1" >/dev/null 2>&1
}

sha_ok() {
	local file="$1" expected="$2"
	[[ -f $file ]] && [[ "$(sha256sum "$file" | cut -d' ' -f1)" == "$expected" ]]
}

download() {
	local url="$1" output="$2" expected="$3"
	if sha_ok "$output" "$expected"; then
		printf 'Reutilizando %s (SHA-256 correcto)\n' "$(basename "$output")"
		return
	fi
	rm -f "$output"
	curl -fL --retry 3 --output "$output" "$url"
	sha_ok "$output" "$expected" || die "SHA-256 incorrecto para $(basename "$output")"
}

[[ $(uname -s) == Linux ]] || die 'Este instalador solo funciona en Linux.'
[[ $(uname -m) == x86_64 ]] || die 'Este build validado requiere x86_64.'

if [[ ! -r /etc/arch-release ]]; then
	printf 'AVISO: no se detecta Arch Linux; se omite la instalacion automatica de paquetes.\n' >&2
	system_setup=false
fi

if $system_setup; then
	info 'Instalando dependencias de Arch'
	sudo pacman -S --needed \
		acl alsa-lib at-spi2-core curl desktop-file-utils git gtk3 jq libpulse \
		libsecret nodejs npm nss perl python unzip wl-clipboard xdg-utils xorg-xwayland
fi

for cmd in curl git jq node npx perl python3 sha256sum unzip xdg-mime; do
	have "$cmd" || die "Falta '$cmd'. Instala las dependencias o no uses --no-system-setup."
done

mkdir -p "$cache_dir"
work_dir="$(mktemp -d "$cache_dir/build.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

nupkg="$cache_dir/$NUPKG_NAME"
electron_zip="$cache_dir/$ELECTRON_NAME"
helper_bin="$cache_dir/$HELPER_NAME"
sqlite_bin="$cache_dir/$SQLITE_NAME"

info 'Descargando y verificando artefactos'
download "$NUPKG_URL" "$nupkg" "$NUPKG_SHA256"
download "$ELECTRON_URL" "$electron_zip" "$ELECTRON_SHA256"
download "$HELPER_URL" "$helper_bin" "$HELPER_SHA256"
download "$SQLITE_URL" "$sqlite_bin" "$SQLITE_SHA256"

info 'Extrayendo el cliente oficial y Electron Linux'
mkdir -p "$work_dir/nupkg" "$work_dir/app" "$work_dir/stage/usr/lib/wispr-flow"
unzip -q "$nupkg" -d "$work_dir/nupkg"
unzip -q "$electron_zip" -d "$work_dir/stage/usr/lib/wispr-flow"

resources_src="$work_dir/nupkg/lib/net45/resources"
[[ -f $resources_src/app.asar ]] || die 'El NUPKG no contiene resources/app.asar.'

info 'Obteniendo el port Linux fijado por commit'
git clone --quiet --no-checkout https://github.com/wispr-flow-linux/wispr-flow-linux.git "$work_dir/port"
git -C "$work_dir/port" checkout --quiet "$PORT_COMMIT"
[[ $(git -C "$work_dir/port" rev-parse HEAD) == "$PORT_COMMIT" ]] \
	|| die 'El checkout del port no coincide con el commit fijado.'

info 'Desempaquetando y adaptando el cliente a Linux'
npx --yes @electron/asar@4.0.1 extract "$resources_src/app.asar" "$work_dir/app"

actual_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "$work_dir/app/package.json")"
[[ $actual_version == "$APP_VERSION" ]] \
	|| die "Version inesperada dentro de app.asar: $actual_version"

main_bundle="$work_dir/app/.webpack/main/index.js"
patch_dir="$work_dir/port/scripts/patches"
bash "$patch_dir/helper-resolver.sh" "$main_bundle"
bash "$patch_dir/helper-env.sh" "$main_bundle"
bash "$patch_dir/mac-gates.sh" "$main_bundle"
bash "$patch_dir/linux-window-frame.sh" "$main_bundle"
bash "$patch_dir/linux-deeplink.sh" "$main_bundle"
bash "$patch_dir/linux-renderer-chrome.sh" "$work_dir/app/.webpack/renderer/hub/index.js"

renderer_count=0
for renderer in "$work_dir"/app/.webpack/renderer/*/index.js; do
	[[ -f $renderer ]] || continue
	grep -qF 'platform?.isWindows' "$renderer" || continue
	bash "$patch_dir/linux-renderer-treat-as-windows.sh" "$renderer"
	renderer_count=$((renderer_count + 1))
done
((renderer_count > 0)) || die 'No se adapto ningun renderer a Linux.'

# The upstream cold-start patch does not cover callbacks delivered to an already
# running process. The singleton must also exit synchronously so its ready
# listeners cannot start SQLite and the helper before app.quit() takes effect.
perl -0777 -pi -e '
	$n += s/(e\.app\.on\("second-instance".{0,700}?else\{)if\([\w\x24]\.[\w\x24]{2}\)(\{const [\w\x24]+=[\w\x24]+\(r\.find\(e=>e\.startsWith\("wispr-flow:)/${1}if(true)${2}/s;
	$m += s/(title:"Flow Hub".{0,700}?)focusable:!1/${1}focusable:!0/s;
	$q += s/(App is already running, quitting"\),void e\.app\.)quit\(\)/${1}exit()/;
	END { die "expected one warm-deeplink, hub-focus, and singleton-exit patch; got deeplink=$n focus=$m singleton=$q\n" unless $n == 1 && $m == 1 && $q == 1 }
' "$main_bundle"

# Remove patch backups before repacking.
shopt -s globstar nullglob
rm -f "$work_dir"/app/**/*.orig

native_dir="$work_dir/app/.webpack/main/native_modules/build/Release"
mkdir -p "$native_dir"
install -m 0755 "$sqlite_bin" "$native_dir/node_sqlite3.node"
[[ $(od -An -N4 -tx1 "$native_dir/node_sqlite3.node" | tr -d ' \n') == 7f454c46 ]] \
	|| die 'El modulo SQLite descargado no es un ELF Linux.'

node --check "$main_bundle"
for renderer in "$work_dir"/app/.webpack/renderer/*/index.js; do
	[[ -f $renderer ]] && node --check "$renderer"
done

resources_dst="$work_dir/stage/usr/lib/wispr-flow/resources"
mkdir -p "$resources_dst/Release"
cp -a "$resources_src/assets" "$resources_dst/assets"
cp -a "$resources_src/migrations" "$resources_dst/migrations"
cp -a "$resources_src/app.asar.unpacked" "$resources_dst/app.asar.unpacked"
for extra in ax-inspect-lib.mjs ax-inspect-server.mjs ax-inspect.mjs; do
	[[ -f $resources_src/$extra ]] && cp "$resources_src/$extra" "$resources_dst/$extra"
done

npx --yes @electron/asar@4.0.1 pack "$work_dir/app" "$resources_dst/app.asar" --unpack '*.node'
install -m 0755 "$sqlite_bin" \
	"$resources_dst/app.asar.unpacked/.webpack/main/native_modules/build/Release/node_sqlite3.node"
rm -f "$resources_dst/app.asar.unpacked/.webpack/main/native_modules/lib"/crypt32-*.node
install -m 0755 "$helper_bin" "$resources_dst/Release/wispr-flow-linux-helper"

bash "$work_dir/port/scripts/verify-patches.sh" "$resources_dst/app.asar"

mv "$work_dir/stage/usr/lib/wispr-flow/electron" "$work_dir/stage/usr/lib/wispr-flow/wispr-flow"
chmod 0755 "$work_dir/stage/usr/lib/wispr-flow/wispr-flow"
install -m 0644 "$work_dir/port/scripts/launcher-common.sh" \
	"$work_dir/stage/usr/lib/wispr-flow/launcher-common.sh"
install -m 0644 "$work_dir/port/scripts/doctor.sh" \
	"$work_dir/stage/usr/lib/wispr-flow/doctor.sh"
printf '%s\n' "$APP_VERSION" > "$work_dir/stage/usr/lib/wispr-flow/app-version"

if $system_install; then
	install_root='/opt/wispr-flow'
	bin_target='/usr/local/bin/wispr-flow'
	package_type='system'
	info "Instalando en $install_root"
	sudo rm -rf "${install_root}.new"
	sudo cp -a "$work_dir/stage" "${install_root}.new"
	sudo chown -R root:root "${install_root}.new"
	sudo chmod 4755 "${install_root}.new/usr/lib/wispr-flow/chrome-sandbox"
	if [[ -d $install_root ]]; then
		sudo rm -rf "${install_root}.old"
		sudo mv "$install_root" "${install_root}.old"
	fi
	sudo mv "${install_root}.new" "$install_root"
	sudo rm -rf "${install_root}.old"
	sudo install -m 0755 "$script_dir/bin/wispr-flow" "$bin_target"
else
	install_root="${WISPR_FLOW_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/whsprflow-arch/app}"
	bin_target="${HOME}/.local/bin/wispr-flow"
	package_type='user'
	info "Instalando en $install_root"
	mkdir -p "$(dirname "$install_root")" "$(dirname "$bin_target")"
	rm -rf "${install_root}.new"
	cp -a "$work_dir/stage" "${install_root}.new"
	rm -rf "$install_root"
	mv "${install_root}.new" "$install_root"
	install -m 0755 "$script_dir/bin/wispr-flow" "$bin_target"
fi

configurer_target="$(dirname "$bin_target")/wispr-flow-configure"
if $system_install; then
	sudo install -m 0755 "$script_dir/bin/wispr-flow-configure" "$configurer_target"
else
	install -m 0755 "$script_dir/bin/wispr-flow-configure" "$configurer_target"
fi

info 'Registrando la aplicacion y el callback wispr-flow:'
applications_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
mkdir -p "$applications_dir" "$icons_dir"
install -m 0644 "$resources_src/assets/logos/flow-symbol.svg" "$icons_dir/wispr-flow.svg"

desktop_file="$applications_dir/wispr-flow.desktop"
cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=Wispr Flow
Comment=Voice dictation that types into the focused application
GenericName=Voice Dictation
Exec=${bin_target} %U
TryExec=${bin_target}
Icon=wispr-flow
Terminal=false
Type=Application
Categories=Utility;AudioVideo;Audio;
StartupWMClass=wispr-flow
MimeType=x-scheme-handler/wispr-flow;
Keywords=voice;dictation;speech;transcription;
EOF

have update-desktop-database && update-desktop-database "$applications_dir"
xdg-mime default wispr-flow.desktop x-scheme-handler/wispr-flow
[[ $(xdg-mime query default x-scheme-handler/wispr-flow) == wispr-flow.desktop ]] \
	|| die 'No se pudo registrar el callback wispr-flow:.'

hide_bar=false
desktop_name="${XDG_CURRENT_DESKTOP:-}"
[[ ${desktop_name,,} == *hyprland* ]] && hide_bar=true
configure_args=(bootstrap)
$hide_bar && configure_args+=(--hide-flow-bar)
"$configurer_target" "${configure_args[@]}"

if $system_setup; then
	info 'Configurando entrada global para Wayland'
	rule_tmp="$work_dir/70-wispr-flow-input.rules"
	cat > "$rule_tmp" <<'EOF'
# Wispr Flow Linux helper: injection plus push-to-talk on the active seat.
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess", GROUP="input", MODE="0660"
EOF
	sudo install -D -m 0644 "$rule_tmp" /usr/lib/udev/rules.d/70-wispr-flow-input.rules
	sudo modprobe uinput
	sudo udevadm control --reload-rules
	sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput || true
	sudo udevadm trigger --subsystem-match=input || true
	if ! id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
		sudo usermod -aG input "$USER"
		printf 'Se ha anadido %s al grupo input; cierra sesion al terminar.\n' "$USER"
	fi
	[[ -e /dev/uinput ]] && sudo setfacl -m "u:${USER}:rw" /dev/uinput || true
	for event in /dev/input/event*; do
		[[ -e $event ]] || continue
		if udevadm info --query=property --name="$event" 2>/dev/null \
			| grep -q '^ID_INPUT_KEYBOARD=1$'; then
			sudo setfacl -m "u:${USER}:r" "$event" || true
		fi
	done
fi

info 'Instalacion terminada'
printf 'Version:      %s\n' "$APP_VERSION"
printf 'Tipo:         %s\n' "$package_type"
printf 'Ejecutable:   %s\n' "$bin_target"
printf 'Diagnostico:  wispr-flow --doctor\n'
printf 'Inicio:       wispr-flow\n'
if $hide_bar; then
	printf 'Hyprland:     interfaz XWayland y Flow Bar oculta para evitar el bloqueo de clics.\n'
fi
printf '\nSi el diagnostico no puede leer /dev/input, cierra sesion y vuelve a entrar.\n'
