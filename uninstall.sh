#!/usr/bin/env bash

set -Eeuo pipefail

readonly INSTALL_MARKER='.whsprflow-arch-install'
readonly INSTALL_MARKER_VALUE='whsprflow-arch-v1'
readonly UDEV_RULE='/usr/lib/udev/rules.d/70-wispr-flow-input.rules'

case "${1:-}" in
	'') purge=false ;;
	--purge) purge=true ;;
	*) printf 'Uso: %s [--purge]\n' "$0" >&2; exit 2 ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
user_bin="$HOME/.local/bin/wispr-flow"
user_configurer="$HOME/.local/bin/wispr-flow-configure"
user_root="${WISPR_FLOW_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/whsprflow-arch/app}"
user_root="$(realpath -m -- "$user_root")"
install_user="$(id -un)"
group_marker="/var/lib/whsprflow-arch/input-group-added-$install_user"
cleanup_failed=false
group_removed=false

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

wrapper_owned() {
	local wrapper="$1"
	[[ -f $wrapper ]] && grep -qF 'WISPR_FLOW_ARCH_WRAPPER=1' "$wrapper"
}

root_owned() {
	local root="$1" allow_legacy="$2"
	[[ -e $root ]] || return 0
	[[ $root == /* && $root != / && $root != "$HOME" && ! -L $root ]] || return 1
	if [[ -f $root/$INSTALL_MARKER ]] \
			&& [[ $(< "$root/$INSTALL_MARKER") == "$INSTALL_MARKER_VALUE" ]]; then
		return 0
	fi
	$allow_legacy
}

stop_install() {
	local root="$1"
	[[ -x $root/usr/lib/wispr-flow/wispr-flow ]] || return 0
	WISPR_FLOW_INSTALL_ROOT="$root" "$script_dir/bin/wispr-flow" --stop
}

system_owned=false
user_owned=false
wrapper_owned /usr/local/bin/wispr-flow && system_owned=true
wrapper_owned "$user_bin" && user_owned=true

# Stop every owned installation before removing executable paths. If two are
# active, the first pass may still see the other's virtual keyboard; retry once
# after both exact process trees have received the shutdown request.
stop_retry=false
if $system_owned && ! stop_install /opt/wispr-flow; then
	stop_retry=true
fi
if $user_owned && [[ $user_root != /opt/wispr-flow ]] && ! stop_install "$user_root"; then
	stop_retry=true
fi
if $stop_retry; then
	if $system_owned; then
		stop_install /opt/wispr-flow || die 'No se pudo detener la instalacion de sistema.'
	fi
	if $user_owned && [[ $user_root != /opt/wispr-flow ]]; then
		stop_install "$user_root" || die 'No se pudo detener la instalacion de usuario.'
	fi
fi

configurer="$script_dir/bin/wispr-flow-configure"
if [[ -x $configurer ]]; then
	if ! WISPR_FLOW_SKIP_HYPR_RELOAD=1 "$configurer" autostart off; then
		printf 'AVISO: no se pudo retirar el autostart gestionado.\n' >&2
		cleanup_failed=true
	fi
	if ! "$configurer" hyprland-rules off; then
		printf 'AVISO: no se pudieron retirar las reglas Hyprland gestionadas.\n' >&2
		cleanup_failed=true
	fi
else
	printf 'AVISO: falta %s; no se limpia la integracion Hyprland.\n' "$configurer" >&2
	cleanup_failed=true
fi

if $system_owned; then
	root_owned /opt/wispr-flow true \
		|| die '/opt/wispr-flow no pertenece de forma verificable a whsprflow-arch.'
	sudo rm -f /usr/local/bin/wispr-flow /usr/local/bin/wispr-flow-configure
	sudo rm -rf /opt/wispr-flow
fi

if $user_owned; then
	allow_legacy=true
	[[ -n ${WISPR_FLOW_INSTALL_ROOT:-} ]] && allow_legacy=false
	root_owned "$user_root" "$allow_legacy" \
		|| die "$user_root no pertenece de forma verificable a whsprflow-arch."
	rm -f "$user_bin" "$user_configurer"
	rm -rf "$user_root"
fi

rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/wispr-flow.desktop"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/wispr-flow.svg"
command -v update-desktop-database >/dev/null 2>&1 \
	&& update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications"

rule_owned=false
if [[ -f $UDEV_RULE ]]; then
	if grep -qxF '# Wispr Flow Linux helper: injection plus push-to-talk on the active seat.' "$UDEV_RULE"; then
		rule_owned=true
	else
		printf 'AVISO: %s no coincide con la regla gestionada; no se elimina.\n' "$UDEV_RULE" >&2
		cleanup_failed=true
	fi
fi

if $rule_owned || [[ -f $group_marker ]]; then
	$rule_owned && sudo rm -f "$UDEV_RULE"
	sudo udevadm control --reload-rules
	sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput || true
	sudo udevadm trigger --subsystem-match=input || true
	[[ -e /dev/uinput ]] && sudo setfacl -x "u:$install_user" /dev/uinput 2>/dev/null || true
	for event in /dev/input/event*; do
		[[ -e $event ]] || continue
		sudo setfacl -x "u:$install_user" "$event" 2>/dev/null || true
	done
	if [[ -f $group_marker ]]; then
		sudo gpasswd -d "$install_user" input
		sudo rm -f "$group_marker"
		group_removed=true
		printf '%s fue retirado del grupo input; cierra sesion para revocar la membresia actual.\n' "$install_user"
	fi
	sudo rmdir /var/lib/whsprflow-arch 2>/dev/null || true
fi

if $purge; then
	rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/Wispr Flow"
	rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/whsprflow-arch"
	rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/wispr-flow"
fi

printf 'Wispr Flow desinstalado. Se retiraron la regla udev y los ACL gestionados.\n'
if ! $group_removed && id -nG "$install_user" | tr ' ' '\n' | grep -qx input; then
	printf 'La membresia preexistente/no registrada en el grupo input se conserva.\n'
fi
printf 'Usa --purge para borrar tambien cuenta local, preferencias, logs y descargas.\n'
if $cleanup_failed; then
	exit 1
fi
