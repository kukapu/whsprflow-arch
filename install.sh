#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly APP_VERSION='1.6.447'
readonly ELECTRON_VERSION='42.3.0'
readonly PORT_COMMIT='6fb43cd809f8319a9e05da4b4e7a2d3264c126ab'
readonly HELPER_COMMIT='fa93fcf31d9ee7a9591a8dce1852f815d1b0dec5'
readonly NUPKG_NAME="WisprFlow-${APP_VERSION}-full.nupkg"
readonly NUPKG_URL="https://dl.wisprflow.com/wispr-flow/win32/x64/${NUPKG_NAME}"
readonly NUPKG_SHA256='c5a6175c74028c30b11c9a96a295df1b47780929ceaf3753a96ffa855b591f03'
readonly ELECTRON_NAME="electron-v${ELECTRON_VERSION}-linux-x64.zip"
readonly ELECTRON_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/${ELECTRON_NAME}"
readonly ELECTRON_SHA256='487a667ca6a734b958c16cff1df74d9d44d2c18a6cccdb4dd51f6301a356c420'
readonly HELPER_NAME="wispr-flow-linux-helper-${HELPER_COMMIT}-arch-fixes-x86_64"
readonly HELPER_SHA256='5f069506ccf51964f05ba6b06b7a1bfbb42cd2a5d64437c965abba628c4b45b0'
readonly INSTALL_MARKER='.whsprflow-arch-install'
readonly INSTALL_MARKER_VALUE='whsprflow-arch-v1'
readonly SQLITE_NAME='node_sqlite3-x86_64.node'
readonly SQLITE_URL="https://github.com/wispr-flow-linux/native-modules/releases/download/native-v1/${SQLITE_NAME}"
readonly SQLITE_SHA256='c9bd0419f77efb3b5d3a691fda04e265f740ad8dc195f0b56003cdeac92e9a34'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/whsprflow-arch"
system_install=true
system_setup=true
custom_install_root=false
[[ -n ${WISPR_FLOW_INSTALL_ROOT:-} ]] && custom_install_root=true
install_user="$(id -un)"

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

wrapper_owned() {
	local wrapper="$1"
	[[ -f $wrapper ]] && grep -qF 'WISPR_FLOW_ARCH_WRAPPER=1' "$wrapper"
}

validate_install_root() {
	local root="$1" wrapper="$2" allow_legacy="$3"
	[[ $root == /* && $root != / && $root != "$HOME" && ! -L $root ]] \
		|| die "Ruta de instalacion insegura: $root"
	[[ -e $root ]] || return 0
	if [[ -f $root/$INSTALL_MARKER ]] \
			&& [[ $(< "$root/$INSTALL_MARKER") == "$INSTALL_MARKER_VALUE" ]]; then
		return 0
	fi
	$allow_legacy && wrapper_owned "$wrapper" && return 0
	die "$root ya existe y no tiene la marca de propiedad de whsprflow-arch; no se reemplaza."
}

stop_existing_install() {
	local root="$1"
	[[ -x $root/usr/lib/wispr-flow/wispr-flow ]] || return 0
	info "Deteniendo la instalacion existente en $root"
	WISPR_FLOW_INSTALL_ROOT="$root" "$script_dir/bin/wispr-flow" --stop \
		|| die "No se pudo detener de forma segura la instalacion en $root."
}

[[ $(uname -s) == Linux ]] || die 'Este instalador solo funciona en Linux.'
[[ $(uname -m) == x86_64 ]] || die 'Este build validado requiere x86_64.'

if $system_install; then
	install_root='/opt/wispr-flow'
	bin_target='/usr/local/bin/wispr-flow'
	package_type='system'
	validate_install_root "$install_root" "$bin_target" true
else
	install_root="${WISPR_FLOW_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/whsprflow-arch/app}"
	install_root="$(realpath -m -- "$install_root")"
	bin_target="${HOME}/.local/bin/wispr-flow"
	package_type='user'
	allow_legacy=true
	$custom_install_root && allow_legacy=false
	validate_install_root "$install_root" "$bin_target" "$allow_legacy"
fi

if [[ ! -r /etc/arch-release ]]; then
	printf 'AVISO: no se detecta Arch Linux; se omite la instalacion automatica de paquetes.\n' >&2
	system_setup=false
fi

if $system_setup; then
	info 'Instalando dependencias de Arch'
	sudo pacman -S --needed \
		acl alsa-lib asar at-spi2-core curl desktop-file-utils git gtk3 jq libpulse \
		libsecret nodejs nss perl python unzip wl-clipboard xdg-utils xorg-xwayland
fi

for cmd in asar curl file git jq node perl python3 sha256sum unzip xdg-mime; do
	have "$cmd" || die "Falta '$cmd'. Instala las dependencias o no uses --no-system-setup."
done
[[ -x /usr/bin/asar ]] \
	|| die "Falta '/usr/bin/asar'. Instala el paquete Arch 'asar'."

mkdir -p "$cache_dir"
work_dir="$(mktemp -d "$cache_dir/build.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

nupkg="$cache_dir/$NUPKG_NAME"
electron_zip="$cache_dir/$ELECTRON_NAME"
helper_bin="$script_dir/assets/wispr-flow-linux-helper-x86_64"
sqlite_bin="$cache_dir/$SQLITE_NAME"

info 'Descargando y verificando artefactos'
download "$NUPKG_URL" "$nupkg" "$NUPKG_SHA256"
download "$ELECTRON_URL" "$electron_zip" "$ELECTRON_SHA256"
download "$SQLITE_URL" "$sqlite_bin" "$SQLITE_SHA256"

sha_ok "$helper_bin" "$HELPER_SHA256" \
	|| die 'El helper Linux parcheado incluido no coincide con su SHA-256 fijado.'
file "$helper_bin" | grep -q 'ELF 64-bit.*x86-64' \
	|| die 'El helper incluido no es un ELF Linux x86_64.'
printf 'Verificado %s (commit %s, SHA-256 correcto)\n' "$HELPER_NAME" "$HELPER_COMMIT"

info 'Obteniendo el port Linux fijado por commit'
git clone --quiet --no-checkout https://github.com/wispr-flow-linux/wispr-flow-linux.git "$work_dir/port"
git -C "$work_dir/port" checkout --quiet "$PORT_COMMIT"
[[ $(git -C "$work_dir/port" rev-parse HEAD) == "$PORT_COMMIT" ]] \
	|| die 'El checkout del port no coincide con el commit fijado.'

info 'Ensamblando el runtime Linux aislado'
"$script_dir/scripts/assemble-app.sh" \
	--version "$APP_VERSION" \
	--nupkg "$nupkg" \
	--electron-zip "$electron_zip" \
	--sqlite "$sqlite_bin" \
	--helper "$helper_bin" \
	--port-dir "$work_dir/port" \
	--output-dir "$work_dir/runtime" \
	--asar-bin /usr/bin/asar

mkdir -p "$work_dir/stage/usr/lib"
mv "$work_dir/runtime" "$work_dir/stage/usr/lib/wispr-flow"
printf '%s\n' "$INSTALL_MARKER_VALUE" > "$work_dir/stage/$INSTALL_MARKER"

if $system_install; then
	stop_existing_install "$install_root"
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
	stop_existing_install "$install_root"
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
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$applications_dir" "$icons_dir" "$config_home"
install -m 0644 \
	"$work_dir/stage/usr/lib/wispr-flow/resources/assets/logos/flow-symbol.svg" \
	"$icons_dir/wispr-flow.svg"

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
	if ! id -nG "$install_user" | tr ' ' '\n' | grep -qx input; then
		sudo usermod -aG input "$install_user"
		sudo install -d -m 0755 /var/lib/whsprflow-arch
		sudo touch "/var/lib/whsprflow-arch/input-group-added-$install_user"
		printf 'Se ha anadido %s al grupo input; cierra sesion al terminar.\n' "$install_user"
	fi
	[[ -e /dev/uinput ]] && sudo setfacl -m "u:${install_user}:rw" /dev/uinput || true
	for event in /dev/input/event*; do
		[[ -e $event ]] || continue
		if udevadm info --query=property --name="$event" 2>/dev/null \
			| grep -q '^ID_INPUT_KEYBOARD=1$'; then
			sudo setfacl -m "u:${install_user}:r" "$event" || true
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
	"$configurer_target" hyprland-rules on
	printf 'Hyprland:     Hub flotante y Status visible solo durante el dictado.\n'
fi
printf '\nSi el diagnostico no puede leer /dev/input, cierra sesion y vuelve a entrar.\n'
