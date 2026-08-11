#!/usr/bin/env bash

set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for script in "$root/install.sh" "$root/uninstall.sh" "$root/bin/wispr-flow" \
	"$root/bin/wispr-flow-configure"; do
	bash -n "$script"
done

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" bootstrap

config="$tmp/config/Wispr Flow/config.json"
jq -e '.prefs.user.hideFlowBarPermanently == false' "$config" >/dev/null

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" bootstrap --hide-flow-bar

jq -e '
	.prefs.user.shortcuts["162+91"] == "ptt" and
	.prefs.user.modifierShortcut == "164" and
	.prefs.user.hideFlowBarPermanently == true and
	(.prefs.cache.splitKeybinds | any(.value == "ptt" and .shortcut == [162, 91]))
' "$config" >/dev/null

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" flow-bar on
jq -e '.prefs.user.hideFlowBarPermanently == false' "$config" >/dev/null

HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
	"$root/bin/wispr-flow-configure" check

printf 'Smoke tests OK\n'
