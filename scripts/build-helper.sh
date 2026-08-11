#!/usr/bin/env bash

set -Eeuo pipefail

readonly HELPER_COMMIT='fa93fcf31d9ee7a9591a8dce1852f815d1b0dec5'
readonly RUSTC_VERSION='1.96.0'
readonly UPSTREAM_UINPUT_SHA256='ff2e65111f0a7f5b54af9e99bee8e8484011d35a15c8374fab00e956a59afba1'
readonly PATCHED_UINPUT_SHA256='e0ac469f0d3c6227802d7beb364b16b3b52f12b6838df35bae7e9950ab5cc919'
readonly UPSTREAM_WAYLAND_SHA256='04a5521656b3ba5711518add58aa82d868df3f118f3ecf3cc984b60423da379f'
readonly TERMINAL_PATCH_SHA256='6bcd4f2251e6a2793ff86052ccc48831b88f29c96bcdc46fa1641c9cda831c68'
readonly PATCHED_WAYLAND_SHA256='857e3341966f680f9d0ac33ad87135291a3e045d466587b7f8be6e31bbf431f9'
readonly BINARY_SHA256='5f069506ccf51964f05ba6b06b7a1bfbb42cd2a5d64437c965abba628c4b45b0'

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$root/assets/wispr-flow-linux-helper-x86_64}"

for command in cargo file git patch rustc sha256sum; do
	command -v "$command" >/dev/null 2>&1 || {
		printf 'ERROR: falta %s.\n' "$command" >&2
		exit 1
	}
done

actual_rustc="$(rustc --version | cut -d' ' -f2)"
[[ $actual_rustc == "$RUSTC_VERSION" ]] || {
	printf 'ERROR: se requiere rustc %s; se encontro %s.\n' "$RUSTC_VERSION" "$actual_rustc" >&2
	exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet --no-checkout https://github.com/wispr-flow-linux/helper.git "$work/helper"
git -C "$work/helper" checkout --quiet "$HELPER_COMMIT"
[[ $(git -C "$work/helper" rev-parse HEAD) == "$HELPER_COMMIT" ]]

upstream="$work/helper/src/backend/uinput.rs"
patch="$root/patches/helper/uinput.rs"
[[ $(sha256sum "$upstream" | cut -d' ' -f1) == "$UPSTREAM_UINPUT_SHA256" ]]
[[ $(sha256sum "$patch" | cut -d' ' -f1) == "$PATCHED_UINPUT_SHA256" ]]
install -m 0644 "$patch" "$upstream"

wayland="$work/helper/src/backend/wayland.rs"
terminal_patch="$root/patches/helper/terminal-paste.patch"
[[ $(sha256sum "$wayland" | cut -d' ' -f1) == "$UPSTREAM_WAYLAND_SHA256" ]]
[[ $(sha256sum "$terminal_patch" | cut -d' ' -f1) == "$TERMINAL_PATCH_SHA256" ]]
patch --batch --forward --fuzz=0 -d "$work/helper" -p1 < "$terminal_patch"
[[ $(sha256sum "$wayland" | cut -d' ' -f1) == "$PATCHED_WAYLAND_SHA256" ]]

unset RUSTFLAGS CARGO_ENCODED_RUSTFLAGS
export CARGO_INCREMENTAL=0
export CARGO_TARGET_DIR="$work/target"
export SOURCE_DATE_EPOCH=1781205638

cargo fmt --check --manifest-path "$work/helper/Cargo.toml"
cargo test --locked --manifest-path "$work/helper/Cargo.toml"
cargo clippy --locked --all-targets --manifest-path "$work/helper/Cargo.toml" -- -D warnings
cargo build --release --locked --manifest-path "$work/helper/Cargo.toml"

built="$work/target/release/wispr-flow-linux-helper"
file "$built" | grep -q 'ELF 64-bit.*x86-64'
actual_sha="$(sha256sum "$built" | cut -d' ' -f1)"
[[ $actual_sha == "$BINARY_SHA256" ]] || {
	printf 'ERROR: SHA-256 no reproducible: esperado %s, obtenido %s.\n' \
		"$BINARY_SHA256" "$actual_sha" >&2
	exit 1
}

mkdir -p "$(dirname "$output")"
install -m 0755 "$built" "$output"
printf 'Helper reproducido: %s\nSHA-256: %s\n' "$output" "$actual_sha"
