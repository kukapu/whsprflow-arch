#!/usr/bin/env bash

set -Eeuo pipefail

bundle="${1:-}"
[[ -f $bundle ]] || { printf 'Uso: %s <.webpack/main/index.js>\n' "$0" >&2; exit 2; }

python3 - "$bundle" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8", errors="surrogateescape")
show_marker = "WISPR_LINUX_HIDE_STATUS_WINDOW_SHOW"
dictation_marker = "WISPR_LINUX_HIDE_STATUS_WINDOW_DICTATION"
start_sound_marker = "WISPR_LINUX_LOCAL_START_SOUND"
stop_sound_marker = "WISPR_LINUX_LOCAL_STOP_SOUND"
compact_status_marker = "WISPR_LINUX_COMPACT_STATUS_WINDOW"
transient_hide_marker = "WISPR_LINUX_TRANSIENT_STATUS_HIDE"
status_zoom_marker = "WISPR_LINUX_STATUS_ZOOM"
status_geometry_marker = "WISPR_LINUX_STATUS_GEOMETRY"
status_interactive_marker = "WISPR_LINUX_STATUS_INTERACTIVE"
status_hittest_marker = "WISPR_LINUX_STATUS_HITTEST"
status_tour_marker = "WISPR_LINUX_STATUS_TOUR"

markers = (
    show_marker,
    dictation_marker,
    start_sound_marker,
    stop_sound_marker,
    compact_status_marker,
    transient_hide_marker,
    status_zoom_marker,
    status_geometry_marker,
    status_interactive_marker,
    status_hittest_marker,
    status_tour_marker,
)
markers_present = [marker in source for marker in markers]
if all(markers_present):
    print("Already patched (Status guards + local dictation sounds)")
    raise SystemExit(0)
if any(markers_present):
    raise SystemExit("ERROR: incomplete Flow Status Indicator patch detected")

show_anchor = re.compile(
    r'(?P<window>[\w$]+)\.showInactive\(\),'
    r'(?P<logger>[\w$]+)\(\)\.info\("Showing status window"\)'
)
matches = list(show_anchor.finditer(source))
if len(matches) != 1:
    raise SystemExit(
        f"ERROR: expected one Flow Status Indicator show site, found {len(matches)}"
    )

def replace_show(match: re.Match[str]) -> str:
    window = match.group("window")
    logger = match.group("logger")
    return (
        f'(/*{show_marker}*/"1"===process.env.WISPR_FLOW_HIDE_STATUS_WINDOW?'
        f'({window}.hide(),{logger}().info("Linux: Flow Status Indicator kept hidden")):'
        f'({window}.showInactive(),{logger}().info("Showing status window")))'
    )

patched, count = show_anchor.subn(replace_show, source, count=1)
if count != 1:
    raise SystemExit(f"ERROR: status-window substitution count was {count}")

dictation_anchor = re.compile(
    r'(?P<head>[\w$]+=\(e=[^)]+\)=>\{)'
    r'(?P<declaration>const (?P<window>[\w$]+)='
    r'(?P<status>[\w$]+\.RA\.statusWindow);'
    r'if\(!(?P=window)\|\|(?P=window)\.isDestroyed\(\)\)return '
    r'[\w$]+\(\)\.error\("Status window is not available or destroyed\. Recreating\."\))'
)
matches = list(dictation_anchor.finditer(patched))
if len(matches) != 1:
    raise SystemExit(
        f"ERROR: expected one dictation status-window recovery site, found {len(matches)}"
    )

def replace_dictation(match: re.Match[str]) -> str:
    window = match.group("window")
    status = match.group("status")
    guard = (
        f'if(/*{dictation_marker}*/"1"===process.env.WISPR_FLOW_HIDE_STATUS_WINDOW&&'
        f'"1"!==process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW)'
        f'{{const {window}={status};{window}&&!{window}.isDestroyed()&&{window}.hide();return}}'
    )
    return f'{match.group("head")}{guard}{match.group("declaration")}'

patched, count = dictation_anchor.subn(replace_dictation, patched, count=1)
if count != 1:
    raise SystemExit(f"ERROR: dictation status-window substitution count was {count}")

start_sound_anchor = '(0,ee.ui)(!0)})(e),ke(O._W.Listening),'
if patched.count(start_sound_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one dictation-start sound anchor, found {patched.count(start_sound_anchor)}"
    )
patched = patched.replace(
    start_sound_anchor,
    start_sound_anchor
    + '"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&'
    + 'ne.RA.statusWindow?.showInactive(),'
    + f'/*{start_sound_marker}*/ne.RA.prefs?.user.enableSounds&&'
    + '(0,V.Bn)(ne.RA.hubWindow,E.Y6.PlayDictationStartSound),',
    1,
)

transient_hide_anchor = 'p.ZZ.status=e,p.ZZ.statusLastUpdatedTime=Date.now();const s='
if patched.count(transient_hide_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one terminal-status hide anchor, found {patched.count(transient_hide_anchor)}"
    )
patched = patched.replace(
    transient_hide_anchor,
    'p.ZZ.status=e,p.ZZ.statusLastUpdatedTime=Date.now(),'
    + f'/*{transient_hide_marker}*/"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&'
    + '[O._W.Idle,O._W.Error,O._W.Dismissed].includes(e)&&ne.RA.statusWindow?.hide();const s=',
    1,
)

stop_sound_anchor = 'ke(O._W.Stopping),Ve(e),'
if patched.count(stop_sound_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one dictation-stop sound anchor, found {patched.count(stop_sound_anchor)}"
    )
patched = patched.replace(
    stop_sound_anchor,
    'ke(O._W.Stopping),'
    + f'/*{stop_sound_marker}*/ne.RA.prefs?.user.enableSounds&&'
    + '(0,V.Bn)(ne.RA.hubWindow,E.Y6.PlayDictationStopSound),Ve(e),',
    1,
)

compact_anchor = 'A.tD,A.H8,570,u,480),ne='
if patched.count(compact_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one status-window bounds anchor, found {patched.count(compact_anchor)}"
    )
zoom_expr = 'process.env.WISPR_FLOW_STATUS_ZOOM?parseFloat(process.env.WISPR_FLOW_STATUS_ZOOM):1.45'
height_expr = (
    '"1"===process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW?96:'
    f'/*{status_geometry_marker}*/(process.env.WISPR_FLOW_STATUS_H?+process.env.WISPR_FLOW_STATUS_H:'
    f'Math.round(570*({zoom_expr})))'
)
width_expr = (
    f'/*{compact_status_marker}*/"1"===process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW?180:'
    '(process.env.WISPR_FLOW_STATUS_W?+process.env.WISPR_FLOW_STATUS_W:'
    f'Math.round(480*({zoom_expr})))'
)
patched = patched.replace(
    compact_anchor,
    'A.tD,A.H8,' + height_expr + ',u,' + width_expr + '),ne=',
    1,
)

zoom_prefs_anchor = (
    'webPreferences:{...m.g,preload:require("path").resolve(__dirname,'
    '"../renderer","status","preload.js"),backgroundThrottling:!1}'
)
if patched.count(zoom_prefs_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one status webPreferences anchor, found {patched.count(zoom_prefs_anchor)}"
    )
patched = patched.replace(
    zoom_prefs_anchor,
    zoom_prefs_anchor[:-1]
    + f',/*{status_zoom_marker}*/zoomFactor:process.env.WISPR_FLOW_STATUS_ZOOM'
    '?parseFloat(process.env.WISPR_FLOW_STATUS_ZOOM)'
    ':("1"===process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW?1:1.45)}',
    1,
)

interactive_create_anchor = (
    'n.setAlwaysOnTop(!0,"screen-saver"),n.setIgnoreMouseEvents(!0,{forward:!0}),'
    'A.tD&&n.setVisibleOnAllWorkspaces'
)
if patched.count(interactive_create_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one status ignore-mouse anchor, found {patched.count(interactive_create_anchor)}"
    )
patched = patched.replace(
    interactive_create_anchor,
    'n.setAlwaysOnTop(!0,"screen-saver"),'
    f'/*{status_interactive_marker}*/"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&'
    'n.setIgnoreMouseEvents(!0,{forward:!0}),A.tD&&n.setVisibleOnAllWorkspaces',
    1,
)

interactive_ipc_anchor = ':V()?.setIgnoreMouseEvents(!0,{forward:!0}),(0,h.cA)(x.RA.statusWindow)'
if patched.count(interactive_ipc_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one status EnableMouseEvents anchor, found {patched.count(interactive_ipc_anchor)}"
    )
patched = patched.replace(
    interactive_ipc_anchor,
    ':("1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&V()?.setIgnoreMouseEvents(!0,{forward:!0}),'
    '(0,h.cA)(x.RA.statusWindow))',
    1,
)

position_anchor = 'return{x:c+(h-o)/2,y:u+m-s,width:o,height:s}'
if patched.count(position_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one status geometry return anchor, found {patched.count(position_anchor)}"
    )
patched = patched.replace(
    position_anchor,
    'return{x:c+(h-o)/2,y:u+m-s,width:o,height:s,'
    f'...(/*{status_geometry_marker}*/"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&'
    '"1"!==process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW'
    '?{y:Math.round(u+m*parseFloat(process.env.WISPR_FLOW_STATUS_Y||"0.83")-s/2)}:{})}',
    1,
)

hittest_anchor = 'O=(t,n)=>{v()&&A===n&&!e.isDestroyed()&&e.setIgnoreMouseEvents(t,{forward:!0})}'
if patched.count(hittest_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one alpha hit-test poller anchor, found {patched.count(hittest_anchor)}"
    )
patched = patched.replace(
    hittest_anchor,
    'O=(t,n)=>{v()&&A===n&&!e.isDestroyed()&&'
    f'/*{status_hittest_marker}*/(!t||"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE)&&'
    'e.setIgnoreMouseEvents(t,{forward:!0})}',
    1,
)

tour_anchor = 'x.RA.statusWindow&&!x.RA.statusWindow.isDestroyed()&&x.RA.statusWindow.setIgnoreMouseEvents(!0,{forward:!0})'
if patched.count(tour_anchor) != 1:
    raise SystemExit(
        f"ERROR: expected one feature-tour suspend anchor, found {patched.count(tour_anchor)}"
    )
patched = patched.replace(
    tour_anchor,
    'x.RA.statusWindow&&!x.RA.statusWindow.isDestroyed()&&'
    f'/*{status_tour_marker}*/"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&'
    'x.RA.statusWindow.setIgnoreMouseEvents(!0,{forward:!0})',
    1,
)

path.write_text(patched, encoding="utf-8", errors="surrogateescape")
print("Patched: Status guards, geometry, zoom, interactivity, local dictation sounds")
PY

grep -qF 'WISPR_LINUX_HIDE_STATUS_WINDOW_SHOW' "$bundle"
grep -qF 'WISPR_LINUX_HIDE_STATUS_WINDOW_DICTATION' "$bundle"
grep -qF 'WISPR_LINUX_LOCAL_START_SOUND' "$bundle"
grep -qF 'WISPR_LINUX_LOCAL_STOP_SOUND' "$bundle"
grep -qF 'WISPR_LINUX_COMPACT_STATUS_WINDOW' "$bundle"
grep -qF 'WISPR_LINUX_TRANSIENT_STATUS_HIDE' "$bundle"
grep -qF 'WISPR_LINUX_STATUS_ZOOM' "$bundle"
grep -qF 'WISPR_LINUX_STATUS_GEOMETRY' "$bundle"
grep -qF 'WISPR_LINUX_STATUS_INTERACTIVE' "$bundle"
grep -qF 'WISPR_LINUX_STATUS_HITTEST' "$bundle"
grep -qF 'WISPR_LINUX_STATUS_TOUR' "$bundle"
node --check "$bundle"
