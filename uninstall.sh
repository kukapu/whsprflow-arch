#!/usr/bin/env bash

set -Eeuo pipefail

purge=false
[[ ${1:-} == --purge ]] && purge=true

user_bin="$HOME/.local/bin/wispr-flow"
user_configurer="$HOME/.local/bin/wispr-flow-configure"

if [[ -f /usr/local/bin/wispr-flow ]] \
		&& grep -q 'WISPR_FLOW_ARCH_WRAPPER=1' /usr/local/bin/wispr-flow; then
	sudo rm -f /usr/local/bin/wispr-flow /usr/local/bin/wispr-flow-configure
	sudo rm -rf /opt/wispr-flow
fi

if [[ -f $user_bin ]] && grep -q 'WISPR_FLOW_ARCH_WRAPPER=1' "$user_bin"; then
	rm -f "$user_bin" "$user_configurer"
	rm -rf "${WISPR_FLOW_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/whsprflow-arch/app}"
fi

rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/wispr-flow.desktop"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/wispr-flow.svg"
command -v update-desktop-database >/dev/null 2>&1 \
	&& update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications"

if $purge; then
	rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/Wispr Flow"
	rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/whsprflow-arch"
	rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/wispr-flow"
fi

printf 'Wispr Flow desinstalado. La regla udev y el grupo input se conservan para no romper otras herramientas.\n'
printf 'Usa --purge para borrar tambien cuenta local, preferencias, logs y descargas.\n'
