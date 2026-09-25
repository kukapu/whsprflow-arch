#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
	cat <<'EOF'
Uso: assemble-app.sh --version VERSION --nupkg FILE --electron-zip FILE \
  --sqlite FILE --helper FILE --port-dir DIR --output-dir DIR \
  [--asar-bin COMMAND]

Ensamblado aislado, sin descargas ni instalacion del sistema.

  --version VERSION     Version esperada dentro de app.asar.
  --nupkg FILE          NUPKG oficial de Wispr Flow.
  --electron-zip FILE   ZIP oficial de Electron para Linux x86_64.
  --sqlite FILE         Modulo node_sqlite3 Linux x86_64.
  --helper FILE         Helper Linux x86_64.
  --port-dir DIR        Checkout local del port Linux fijado.
  --output-dir DIR      Runtime directo de salida; no debe existir.
  --asar-bin COMMAND    Ejecutable asar (por defecto: asar).
  -h, --help            Muestra esta ayuda.
EOF
}

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

usage_error() {
	printf 'ERROR: %s\n' "$*" >&2
	usage >&2
	exit 2
}

info() {
	printf '\n==> %s\n' "$*"
}

set_once() {
	local name="$1" value="$2"
	[[ -z ${!name} ]] || usage_error "$3 se indico mas de una vez."
	[[ -n $value ]] || usage_error "$3 necesita un valor."
	printf -v "$name" '%s' "$value"
}

version=''
nupkg=''
electron_zip=''
sqlite_bin=''
helper_bin=''
port_dir=''
output_dir=''
asar_bin='asar'
asar_seen=false

while (($#)); do
	case "$1" in
		--version|--nupkg|--electron-zip|--sqlite|--helper|--port-dir|--output-dir|--asar-bin)
			(($# >= 2)) || usage_error "$1 necesita un valor."
			flag="$1"
			value="$2"
			case "$flag" in
				--version) set_once version "$value" "$flag" ;;
				--nupkg) set_once nupkg "$value" "$flag" ;;
				--electron-zip) set_once electron_zip "$value" "$flag" ;;
				--sqlite) set_once sqlite_bin "$value" "$flag" ;;
				--helper) set_once helper_bin "$value" "$flag" ;;
				--port-dir) set_once port_dir "$value" "$flag" ;;
				--output-dir) set_once output_dir "$value" "$flag" ;;
				--asar-bin)
					$asar_seen && usage_error "$flag se indico mas de una vez."
					[[ -n $value ]] || usage_error "$flag necesita un valor."
					asar_bin="$value"
					asar_seen=true
					;;
			esac
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*) usage_error "Opcion desconocida: $1" ;;
	esac
done

[[ -n $version ]] || usage_error 'Falta --version.'
[[ -n $nupkg ]] || usage_error 'Falta --nupkg.'
[[ -n $electron_zip ]] || usage_error 'Falta --electron-zip.'
[[ -n $sqlite_bin ]] || usage_error 'Falta --sqlite.'
[[ -n $helper_bin ]] || usage_error 'Falta --helper.'
[[ -n $port_dir ]] || usage_error 'Falta --port-dir.'
[[ -n $output_dir ]] || usage_error 'Falta --output-dir.'

[[ $version =~ ^[0-9]+([.][0-9]+)*([+-][0-9A-Za-z.-]+)?$ ]] \
	|| die "Version invalida: $version"

output_dir="$(realpath -m -- "$output_dir")"
[[ $output_dir == /* && $output_dir != / ]] || die "Directorio de salida inseguro: $output_dir"
[[ ! -e $output_dir && ! -L $output_dir ]] || die "El directorio de salida ya existe: $output_dir"
output_parent="$(dirname -- "$output_dir")"
[[ -d $output_parent && -w $output_parent ]] \
	|| die "El padre del directorio de salida no existe o no es escribible: $output_parent"

for cmd in file grep install node od perl python3 realpath tr unzip; do
	command -v "$cmd" >/dev/null 2>&1 || die "Falta la dependencia de build '$cmd'."
done
asar_cmd="$(command -v "$asar_bin" 2>/dev/null)" \
	|| die "No se encontro el ejecutable asar: $asar_bin"
[[ -x $asar_cmd ]] || die "El ejecutable asar no se puede ejecutar: $asar_cmd"
asar_cmd="$(realpath -e -- "$asar_cmd")"

canonical_file() {
	local path="$1" label="$2"
	[[ -f $path && -r $path ]] || die "$label no es un archivo legible: $path"
	realpath -e -- "$path"
}

nupkg="$(canonical_file "$nupkg" 'El NUPKG')"
electron_zip="$(canonical_file "$electron_zip" 'El ZIP de Electron')"
sqlite_bin="$(canonical_file "$sqlite_bin" 'El modulo SQLite')"
helper_bin="$(canonical_file "$helper_bin" 'El helper')"
[[ -d $port_dir && -r $port_dir ]] || die "El port no es un directorio legible: $port_dir"
port_dir="$(realpath -e -- "$port_dir")"

patch_dir="$port_dir/scripts/patches"
for port_file in \
	"$patch_dir/helper-resolver.sh" \
	"$patch_dir/helper-env.sh" \
	"$patch_dir/mac-gates.sh" \
	"$patch_dir/linux-window-frame.sh" \
	"$patch_dir/linux-deeplink.sh" \
	"$patch_dir/linux-renderer-chrome.sh" \
	"$patch_dir/linux-renderer-treat-as-windows.sh" \
	"$port_dir/scripts/verify-patches.sh" \
	"$port_dir/scripts/launcher-common.sh" \
	"$port_dir/scripts/doctor.sh"
do
	[[ -f $port_file && -r $port_file ]] || die "Falta un archivo requerido del port: $port_file"
done
[[ -f $script_dir/patches/linux-runtime-fixes.sh ]] \
	|| die 'Falta patches/linux-runtime-fixes.sh.'
[[ -f $script_dir/assets/UNLICENSE ]] || die 'Falta assets/UNLICENSE.'

unzip -tq "$nupkg" >/dev/null || die 'El NUPKG no es un ZIP valido.'
unzip -tq "$electron_zip" >/dev/null || die 'El artefacto de Electron no es un ZIP valido.'
file "$helper_bin" | grep -q 'ELF 64-bit.*x86-64' \
	|| die 'El helper no es un ELF Linux x86_64.'
file "$sqlite_bin" | grep -q 'ELF 64-bit.*x86-64' \
	|| die 'El modulo SQLite no es un ELF Linux x86_64.'

work_dir="$(mktemp -d "$output_parent/.assemble-app.XXXXXX")"
cleanup() {
	rm -rf -- "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Keep every subprocess away from the invoking user's real home and caches.
mkdir -p "$work_dir/home" "$work_dir/config" "$work_dir/cache" \
	"$work_dir/nupkg" "$work_dir/app" "$work_dir/runtime"
export HOME="$work_dir/home"
export XDG_CONFIG_HOME="$work_dir/config"
export XDG_CACHE_HOME="$work_dir/cache"

"$asar_cmd" --version >/dev/null \
	|| die "No se pudo ejecutar asar: $asar_cmd"

info 'Extrayendo el cliente oficial y Electron Linux'
unzip -q "$nupkg" -d "$work_dir/nupkg"
unzip -q "$electron_zip" -d "$work_dir/runtime"

resources_src="$work_dir/nupkg/lib/net45/resources"
[[ -f $resources_src/app.asar ]] || die 'El NUPKG no contiene resources/app.asar.'
for resource_dir in assets migrations; do
	[[ -d $resources_src/$resource_dir ]] \
		|| die "El NUPKG no contiene resources/$resource_dir."
done
for electron_file in electron chrome-sandbox icudtl.dat resources.pak version; do
	[[ -f $work_dir/runtime/$electron_file ]] \
		|| die "El ZIP de Electron no contiene $electron_file."
done

info 'Desempaquetando y adaptando el cliente a Linux'
"$asar_cmd" extract "$resources_src/app.asar" "$work_dir/app"

[[ -f $work_dir/app/package.json ]] || die 'app.asar no contiene package.json.'
actual_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' \
	"$work_dir/app/package.json")"
[[ $actual_version == "$version" ]] \
	|| die "Version inesperada dentro de app.asar: $actual_version"

main_bundle="$work_dir/app/.webpack/main/index.js"
hub_renderer="$work_dir/app/.webpack/renderer/hub/index.js"
[[ -f $main_bundle ]] || die 'app.asar no contiene el bundle principal esperado.'
[[ -f $hub_renderer ]] || die 'app.asar no contiene el renderer de Flow Hub esperado.'

if ! bash "$patch_dir/helper-resolver.sh" "$main_bundle"; then
	bash "$script_dir/patches/helper-resolver-fallback.sh" "$main_bundle"
fi
if ! bash "$patch_dir/helper-env.sh" "$main_bundle"; then
	# Wispr >= 1.6.774 factored the helper env into N(): the upstream
	# anchor `env:{` no longer exists. Apply the nucleus-anchored fallback
	# carrying the same WISPR_LINUX_HELPER_ENV marker.
	bash "$script_dir/patches/helper-env-fallback.sh" "$main_bundle"
fi
bash "$patch_dir/mac-gates.sh" "$main_bundle"
if ! bash "$patch_dir/linux-window-frame.sh" "$main_bundle"; then
	bash "$script_dir/patches/window-frame-fallback.sh" "$main_bundle"
fi
bash "$patch_dir/linux-deeplink.sh" "$main_bundle"
bash "$patch_dir/linux-renderer-chrome.sh" "$hub_renderer"

renderer_count=0
for renderer in "$work_dir"/app/.webpack/renderer/*/index.js; do
	[[ -f $renderer ]] || continue
	grep -qF 'platform?.isWindows' "$renderer" || continue
	bash "$patch_dir/linux-renderer-treat-as-windows.sh" "$renderer"
	renderer_count=$((renderer_count + 1))
done
((renderer_count > 0)) || die 'No se adapto ningun renderer a Linux.'

# Warm callbacks need the same Linux deep-link handling as cold starts. The
# singleton exits synchronously so its ready listeners cannot start services.
perl -0777 -pi -e '
	$n += s/(e\.app\.on\("second-instance".{0,700}?else\{)if\([\w\x24]\.[\w\x24]{2}\)(\{const [\w\x24]+=[\w\x24]+\(r\.find\(e=>e\.startsWith\("wispr-flow:)/${1}if(true)${2}/s;
	$m += s/(title:"Flow Hub".{0,700}?)focusable:!1/${1}focusable:!0/s;
	$q += s/(App is already running, quitting"\),void e\.app\.)quit\(\)/${1}exit()/;
	END { die "expected one warm-deeplink, hub-focus, and singleton-exit patch; got deeplink=$n focus=$m singleton=$q\n" unless $n == 1 && $m == 1 && $q == 1 }
' "$main_bundle"

bash "$script_dir/patches/linux-runtime-fixes.sh" "$main_bundle"

# Patch scripts intentionally create backups. Never ship them in the ASAR.
shopt -s globstar nullglob dotglob
rm -f "$work_dir"/app/**/*.orig

native_dir="$work_dir/app/.webpack/main/native_modules/build/Release"
mkdir -p "$native_dir"
install -m 0755 "$sqlite_bin" "$native_dir/node_sqlite3.node"
[[ $(od -An -N4 -tx1 "$native_dir/node_sqlite3.node" | tr -d ' \n') == 7f454c46 ]] \
	|| die 'El modulo SQLite no conserva la cabecera ELF esperada.'

node --check "$main_bundle"
for renderer in "$work_dir"/app/.webpack/renderer/*/index.js; do
	[[ -f $renderer ]] && node --check "$renderer"
done

resources_dst="$work_dir/runtime/resources"
mkdir -p "$resources_dst/Release"
cp -a "$resources_src/assets" "$resources_dst/assets"
cp -a "$resources_src/migrations" "$resources_dst/migrations"
for extra in ax-inspect-lib.mjs ax-inspect-server.mjs ax-inspect.mjs; do
	[[ -f $resources_src/$extra ]] && cp "$resources_src/$extra" "$resources_dst/$extra"
done

rm -f "$work_dir/app/.webpack/main/native_modules/lib"/crypt32-*.node
"$asar_cmd" pack "$work_dir/app" "$resources_dst/app.asar" --unpack '*.node'
install -m 0755 "$sqlite_bin" \
	"$resources_dst/app.asar.unpacked/.webpack/main/native_modules/build/Release/node_sqlite3.node"
"$asar_cmd" list "$resources_dst/app.asar" > "$work_dir/asar-files.txt"
if grep -q 'crypt32-' "$work_dir/asar-files.txt"; then
	die 'El ASAR final todavia referencia modulos crypt32 exclusivos de Windows.'
fi
if grep -q '\.orig$' "$work_dir/asar-files.txt"; then
	die 'El ASAR final todavia contiene backups de los parches.'
fi

install -m 0755 "$helper_bin" "$resources_dst/Release/wispr-flow-linux-helper"
install -m 0644 "$script_dir/assets/UNLICENSE" "$resources_dst/Release/helper.UNLICENSE"
bash "$port_dir/scripts/verify-patches.sh" "$resources_dst/app.asar"

mv "$work_dir/runtime/electron" "$work_dir/runtime/wispr-flow"
chmod 0755 "$work_dir/runtime/wispr-flow"
install -m 0644 "$port_dir/scripts/launcher-common.sh" \
	"$work_dir/runtime/launcher-common.sh"
install -m 0644 "$port_dir/scripts/doctor.sh" "$work_dir/runtime/doctor.sh"
printf '%s\n' "$version" > "$work_dir/runtime/app-version"

info 'Verificando el runtime ensamblado'
for runtime_file in \
	"$work_dir/runtime/wispr-flow" \
	"$work_dir/runtime/chrome-sandbox" \
	"$resources_dst/app.asar" \
	"$resources_dst/app.asar.unpacked/.webpack/main/native_modules/build/Release/node_sqlite3.node" \
	"$resources_dst/Release/wispr-flow-linux-helper" \
	"$resources_dst/Release/helper.UNLICENSE" \
	"$work_dir/runtime/launcher-common.sh" \
	"$work_dir/runtime/doctor.sh" \
	"$work_dir/runtime/app-version"
do
	[[ -f $runtime_file ]] || die "El runtime final esta incompleto: $runtime_file"
done
[[ -x $work_dir/runtime/wispr-flow ]] || die 'El binario Electron final no es ejecutable.'
[[ -x $resources_dst/Release/wispr-flow-linux-helper ]] || die 'El helper final no es ejecutable.'
[[ ! -e $work_dir/runtime/electron ]] || die 'El binario Electron no fue renombrado.'
[[ $(< "$work_dir/runtime/app-version") == "$version" ]] || die 'app-version es incorrecto.'
cmp -s "$sqlite_bin" \
	"$resources_dst/app.asar.unpacked/.webpack/main/native_modules/build/Release/node_sqlite3.node" \
	|| die 'El SQLite final no coincide con el input verificado.'
cmp -s "$helper_bin" "$resources_dst/Release/wispr-flow-linux-helper" \
	|| die 'El helper final no coincide con el input verificado.'
cmp -s "$script_dir/assets/UNLICENSE" "$resources_dst/Release/helper.UNLICENSE" \
	|| die 'La licencia del helper final es incorrecta.'

# The work directory is on the output filesystem, so this final rename publishes
# the already-verified runtime atomically and leaves no partial output on error.
mv -- "$work_dir/runtime" "$output_dir"
printf '\nRuntime ensamblado: %s\n' "$output_dir"
