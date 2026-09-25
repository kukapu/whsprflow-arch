#!/usr/bin/env bash
# Wispr 1.6.957 extracts the path resolver into a separate webpack module.
set -Eeuo pipefail
bundle="${1:-}"
[[ -f $bundle ]] || exit 2
python3 - "$bundle" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
marker = 'WISPR_LINUX_HELPER_BRANCH'
if marker in source:
    raise SystemExit(0)
# Override the resolver result at its only consumer, before the existence check.
anchor = re.compile(
    r'const (?P<var>[\w$]+)=\(0,[\w$]+\.[\w$]+\)\(\);'
    r'(?P<guard>if\(![\w$]+\(\)\.existsSync\((?P=var)\)\)return '
    r'(?P<logger>[\w$]+)\(\)\.error\("Helper service script path not found")'
)
matches = list(anchor.finditer(source))
if len(matches) != 1:
    raise SystemExit(f'ERROR: expected one extracted helper resolver, found {len(matches)}')
match = matches[0]
original = match.group(0)
patched = original.replace('=', f'=/*{marker}*/"linux"===process.platform?'
    f'({match["logger"]}().info("Running packaged Linux Helper service"),'
    'require("path").join(process.resourcesPath,"Release","wispr-flow-linux-helper")):', 1)
source = source[:match.start()] + patched + source[match.end():]
path.write_text(source)
print('Patched: extracted helper resolver Linux override (1).')
PY
node --check "$bundle"
