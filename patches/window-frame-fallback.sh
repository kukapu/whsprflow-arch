#!/usr/bin/env bash
# Wispr 1.6.957 explicitly adds frame:false to the Windows meeting window.
set -Eeuo pipefail
bundle="${1:-}"
[[ -f $bundle ]] || exit 2
python3 - "$bundle" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
marker = 'WISPR_LINUX_FRAMELESS'
if marker in source:
    raise SystemExit(0)
anchor = re.compile(
    r'"win32"===process\.platform(?P<config>&&Object\.assign\([\w$]+,'
    r'\{titleBarStyle:"hidden",frame:!1,autoHideMenuBar:!0\}\))'
)
patched, count = anchor.subn(lambda m:
    f'(/*{marker}*/"win32"===process.platform||"linux"===process.platform)'
    + m['config'], source)
if count != 1:
    raise SystemExit(f'ERROR: expected one frameless meeting window, found {count}')
path.write_text(patched)
PY
node --check "$bundle"
