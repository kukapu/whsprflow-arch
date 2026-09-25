#!/usr/bin/env bash
# Fallback para Wispr Flow >= 1.6.774: el spawn del helper paso de
#   env:{sentryDSN,...}
# a
#   env:N()
# con N=(e=a.app.isPackaged)=>({sentryDSN:f.kL,...}).
# El script helper-env.sh del port (upstream) ancla en `env:{` y falla con
# "expected exactly 1 helper-spawn env anchor, found 0". Este fallback ancla
# en el nucleo `sentryDSN:<mod>.kL,...,sentryLocalDebug:...` (1 ocurrencia
# en 1.6.447, 1.6.774 y 1.6.957), deriva el identificador del modulo e inserta el
# mismo spread `...process.env` con el mismo marcador WISPR_LINUX_HELPER_ENV,
# de modo que el helper Linux herede WAYLAND_DISPLAY/DISPLAY/XDG_RUNTIME_DIR.
# Uso: helper-env-fallback.sh <.webpack/main/index.js>

set -Eeuo pipefail

BUNDLE="${1:-}"
[[ -f $BUNDLE ]] || { printf 'Uso: %s <.webpack/main/index.js>\n' "$0" >&2; exit 2; }

ENV_MARKER="WISPR_LINUX_HELPER_ENV"
if grep -qF "$ENV_MARKER" "$BUNDLE"; then
	echo "Already patched ($ENV_MARKER present in $BUNDLE) - nothing to do."
	exit 0
fi

if [[ ! -f "$BUNDLE.orig" ]]; then
	cp -p "$BUNDLE" "$BUNDLE.orig"
	echo "Backup written: $BUNDLE.orig"
fi

python3 - "$BUNDLE" "$ENV_MARKER" <<'PY'
import io
import re
import sys

path, marker = sys.argv[1], sys.argv[2]
with io.open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
    data = f.read()

# Derivar el modulo: f en 1.6.774, b en 1.6.957. No fijar su nombre minificado.
pattern = re.compile(
    r'sentryDSN:(?P<module>[\w$]+)\.kL,environment:(?P=module)\.M0,'
    r'segmentWriteKey:(?P=module)\.yj,postHogProjectKey:(?P=module)\.jd,'
    r'sentryLocalDebug:(?P=module)\.iP\?"true":""'
)
matches = list(pattern.finditer(data))
n = len(matches)
if n != 1:
    sys.exit(f"ERROR: expected exactly 1 helper-env N anchor, found {n}.")

anchor = matches[0].group(0)
at = matches[0].start()
window = data[max(0, at - 200):at + len(anchor) + 50]
if marker in window:
    sys.exit(0)

repl = f"/*{marker}*/...process.env," + anchor
data = data.replace(anchor, repl, 1)

with io.open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(data)
print("Patched: spread process.env into the helper env factory N() (1).")
PY

if ! grep -qF "$ENV_MARKER" "$BUNDLE"; then
	echo "ERROR: post-patch verification failed (marker not found)." >&2
	echo "       Restoring backup." >&2
	cp -p "$BUNDLE.orig" "$BUNDLE"
	exit 1
fi

if command -v node >/dev/null; then
	if ! node --check "$BUNDLE"; then
		echo "ERROR: node --check failed on patched bundle. Restoring backup." >&2
		cp -p "$BUNDLE.orig" "$BUNDLE"
		exit 1
	fi
	echo "node --check OK"
fi
echo "OK: helper-spawn env factory now inherits the session environment in $BUNDLE"
