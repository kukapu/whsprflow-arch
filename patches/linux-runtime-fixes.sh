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

patched = source

# Bundle flavour: Wispr 1.6.447 uses (0,ee.ui)/ke(O._W)/ne.RA/V.Bn/E.Y6 and
# 570x480 status bounds; 1.6.774 renamed them to (0,ne.ui)/qe(O._W)/ie.RA/
# K.Bn/_.Y6 with 586x512 bounds and factored the helper env into N().
OLD_START_ANCHOR = '(0,ee.ui)(!0)})(e),ke(O._W.Listening),'
NEW_START_ANCHOR = '(0,ne.ui)(!0)})(e),e===O.SB.BLE&&qe(O._W.Listening),'
old_flavour = OLD_START_ANCHOR in patched
new_flavour = NEW_START_ANCHOR in patched
if old_flavour == new_flavour:
    raise SystemExit(
        "ERROR: cannot determine bundle flavour "
        f"(old_start={old_flavour} new_start={new_flavour})"
    )
if new_flavour:
    RA_MOD = 'ie.RA'
    BN_MOD = 'K.Bn'
    Y_MOD = '_.Y6'
else:
    RA_MOD = 'ne.RA'
    BN_MOD = 'V.Bn'
    Y_MOD = 'E.Y6'


def replace_once(anchor: str, repl: str, label: str) -> None:
    global patched
    count = patched.count(anchor)
    if count != 1:
        raise SystemExit(
            f"ERROR: expected one {label} anchor, found {count}"
        )
    patched = patched.replace(anchor, repl, 1)


# Show site: 447 has `e.showInactive(),a().info("Showing status window")`;
# 774 inserts `,y.H8&&(J||ee(e),e.setAlwaysOnTop(...)),ge(ie),` in between.
show_anchor_old = re.compile(
    r'(?P<window>[\w$]+)\.showInactive\(\),'
    r'(?P<logger>[\w$]+)\(\)\.info\("Showing status window"\)'
)
matches = list(show_anchor_old.finditer(patched))
if len(matches) == 1:
    def replace_show(match: re.Match[str]) -> str:
        window = match.group("window")
        logger = match.group("logger")
        return (
            f'(/*{show_marker}*/"1"===process.env.WISPR_FLOW_HIDE_STATUS_WINDOW?'
            f'({window}.hide(),{logger}().info("Linux: Flow Status Indicator kept hidden")):'
            f'({window}.showInactive(),{logger}().info("Showing status window")))'
        )

    patched, count = show_anchor_old.subn(replace_show, patched, count=1)
    if count != 1:
        raise SystemExit(f"ERROR: status-window substitution count was {count}")
else:
    show_anchor_new = (
        'e.showInactive(),y.H8&&(J||ee(e),'
        'e.setAlwaysOnTop(!0,"screen-saver")),ge(ie),'
        'o().info("Showing status window")'
    )
    replace_once(
        show_anchor_new,
        '(/*' + show_marker + '*/"1"===process.env.WISPR_FLOW_HIDE_STATUS_WINDOW?'
        '(e.hide(),o().info("Linux: Flow Status Indicator kept hidden")):'
        '(e.showInactive(),y.H8&&(J||ee(e),'
        'e.setAlwaysOnTop(!0,"screen-saver")),ge(ie),'
        'o().info("Showing status window")))',
        'Flow Status Indicator show site',
    )

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

if old_flavour:
    replace_once(
        OLD_START_ANCHOR,
        OLD_START_ANCHOR
        + '"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&'
        + 'ne.RA.statusWindow?.showInactive(),'
        + f'/*{start_sound_marker}*/ne.RA.prefs?.user.enableSounds&&'
        + '(0,V.Bn)(ne.RA.hubWindow,E.Y6.PlayDictationStartSound),',
        'dictation-start sound',
    )
else:
    replace_once(
        NEW_START_ANCHOR,
        NEW_START_ANCHOR
        + '"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&'
        + f'{RA_MOD}.statusWindow?.showInactive(),'
        + f'/*{start_sound_marker}*/{RA_MOD}.prefs?.user.enableSounds&&'
        + f'(0,{BN_MOD})({RA_MOD}.hubWindow,{Y_MOD}.PlayDictationStartSound),',
        'dictation-start sound',
    )

transient_hide_anchor = 'p.ZZ.status=e,p.ZZ.statusLastUpdatedTime=Date.now();const s='
replace_once(
    transient_hide_anchor,
    'p.ZZ.status=e,p.ZZ.statusLastUpdatedTime=Date.now(),'
    + f'/*{transient_hide_marker}*/"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&'
    + f'[O._W.Idle,O._W.Error,O._W.Dismissed].includes(e)&&{RA_MOD}.statusWindow?.hide();const s=',
    'terminal-status hide',
)

OLD_STOP_ANCHOR = 'ke(O._W.Stopping),Ve(e),'
NEW_STOP_ANCHOR = 'qe(O._W.Stopping),nt(e),'
if old_flavour:
    replace_once(
        OLD_STOP_ANCHOR,
        'ke(O._W.Stopping),'
        + f'/*{stop_sound_marker}*/{RA_MOD}.prefs?.user.enableSounds&&'
        + f'(0,{BN_MOD})({RA_MOD}.hubWindow,{Y_MOD}.PlayDictationStopSound),Ve(e),',
        'dictation-stop sound',
    )
else:
    replace_once(
        NEW_STOP_ANCHOR,
        'qe(O._W.Stopping),'
        + f'/*{stop_sound_marker}*/{RA_MOD}.prefs?.user.enableSounds&&'
        + f'(0,{BN_MOD})({RA_MOD}.hubWindow,{Y_MOD}.PlayDictationStopSound),nt(e),',
        'dictation-stop sound',
    )

zoom_expr = 'process.env.WISPR_FLOW_STATUS_ZOOM?parseFloat(process.env.WISPR_FLOW_STATUS_ZOOM):1.45'
if old_flavour:
    base_height = '570'
    base_width = '480'
    compact_anchor = 'A.tD,A.H8,570,u,480),ne='
    compact_suffix = '),ne='
    compact_prefix = 'A.tD,A.H8,'
else:
    base_height = '586'
    base_width = '512'
    compact_anchor = 'y.tD,y.H8,586,u,512),Se='
    compact_suffix = '),Se='
    compact_prefix = 'y.tD,y.H8,'
height_expr = (
    '"1"===process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW?96:'
    f'/*{status_geometry_marker}*/(process.env.WISPR_FLOW_STATUS_H?+process.env.WISPR_FLOW_STATUS_H:'
    f'Math.round({base_height}*({zoom_expr})))'
)
width_expr = (
    f'/*{compact_status_marker}*/"1"===process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW?180:'
    '(process.env.WISPR_FLOW_STATUS_W?+process.env.WISPR_FLOW_STATUS_W:'
    f'Math.round({base_width}*({zoom_expr})))'
)
replace_once(
    compact_anchor,
    compact_prefix + height_expr + ',u,' + width_expr + compact_suffix,
    'status-window bounds',
)

if old_flavour:
    zoom_prefs_anchor = (
        'webPreferences:{...m.g,preload:require("path").resolve(__dirname,'
        '"../renderer","status","preload.js"),backgroundThrottling:!1}'
    )
else:
    zoom_prefs_anchor = (
        'webPreferences:{...f.g,preload:require("path").resolve(__dirname,'
        '"../renderer","status","preload.js"),backgroundThrottling:!1}'
    )
replace_once(
    zoom_prefs_anchor,
    zoom_prefs_anchor[:-1]
    + f',/*{status_zoom_marker}*/zoomFactor:process.env.WISPR_FLOW_STATUS_ZOOM'
    '?parseFloat(process.env.WISPR_FLOW_STATUS_ZOOM)'
    ':("1"===process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW?1:1.45)}',
    'status webPreferences',
)

if old_flavour:
    interactive_create_anchor = (
        'n.setAlwaysOnTop(!0,"screen-saver"),n.setIgnoreMouseEvents(!0,{forward:!0}),'
        'A.tD&&n.setVisibleOnAllWorkspaces'
    )
    replace_once(
        interactive_create_anchor,
        'n.setAlwaysOnTop(!0,"screen-saver"),'
        f'/*{status_interactive_marker}*/"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&'
        'n.setIgnoreMouseEvents(!0,{forward:!0}),A.tD&&n.setVisibleOnAllWorkspaces',
        'status ignore-mouse',
    )
else:
    interactive_create_anchor = (
        'n.setAlwaysOnTop(!0,"screen-saver"),'
        'y.H8?F.replaceWindow(n):n.setIgnoreMouseEvents(!0,{forward:!0}),'
        'y.tD&&n.setVisibleOnAllWorkspaces'
    )
    replace_once(
        interactive_create_anchor,
        'n.setAlwaysOnTop(!0,"screen-saver"),'
        'y.H8?F.replaceWindow(n):('
        f'/*{status_interactive_marker}*/"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&'
        'n.setIgnoreMouseEvents(!0,{forward:!0})),'
        'y.tD&&n.setVisibleOnAllWorkspaces',
        'status ignore-mouse',
    )

if old_flavour:
    interactive_ipc_anchor = ':V()?.setIgnoreMouseEvents(!0,{forward:!0}),(0,h.cA)(x.RA.statusWindow)'
    replace_once(
        interactive_ipc_anchor,
        ':("1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&V()?.setIgnoreMouseEvents(!0,{forward:!0}),'
        '(0,h.cA)(x.RA.statusWindow))',
        'status EnableMouseEvents',
    )
else:
    interactive_ipc_anchor = ':Y()?.setIgnoreMouseEvents(!0,{forward:!0}),(0,m.cA)(P.RA.statusWindow)'
    replace_once(
        interactive_ipc_anchor,
        ':("1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&Y()?.setIgnoreMouseEvents(!0,{forward:!0}),'
        '(0,m.cA)(P.RA.statusWindow))',
        'status EnableMouseEvents',
    )

if old_flavour:
    position_anchor = 'return{x:c+(h-o)/2,y:u+m-s,width:o,height:s}'
    replace_once(
        position_anchor,
        'return{x:c+(h-o)/2,y:u+m-s,width:o,height:s,'
        f'...(/*{status_geometry_marker}*/"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&'
        '"1"!==process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW'
        '?{y:Math.round(u+m*parseFloat(process.env.WISPR_FLOW_STATUS_Y||"0.83")-s/2)}:{})}',
        'status geometry return',
    )
else:
    position_anchor = 'return{x:c+(h-a)/2,y:u+m-s,width:a,height:s}'
    replace_once(
        position_anchor,
        'return{x:c+(h-a)/2,y:u+m-s,width:a,height:s,'
        f'...(/*{status_geometry_marker}*/"1"===process.env.WISPR_FLOW_TRANSIENT_STATUS_WINDOW&&'
        '"1"!==process.env.WISPR_FLOW_COMPACT_STATUS_WINDOW'
        '?{y:Math.round(u+m*parseFloat(process.env.WISPR_FLOW_STATUS_Y||"0.83")-s/2)}:{})}',
        'status geometry return',
    )

if old_flavour:
    hittest_anchor = 'O=(t,n)=>{v()&&A===n&&!e.isDestroyed()&&e.setIgnoreMouseEvents(t,{forward:!0})}'
    replace_once(
        hittest_anchor,
        'O=(t,n)=>{v()&&A===n&&!e.isDestroyed()&&'
        f'/*{status_hittest_marker}*/(!t||"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE)&&'
        'e.setIgnoreMouseEvents(t,{forward:!0})}',
        'alpha hit-test poller',
    )
else:
    hittest_anchor = (
        'M=(t,n)=>{v()&&f===n&&!e.isDestroyed()&&'
        '(t?e.setIgnoreMouseEvents(!0,{forward:!0}):e.setIgnoreMouseEvents(!1))}'
    )
    replace_once(
        hittest_anchor,
        'M=(t,n)=>{v()&&f===n&&!e.isDestroyed()&&'
        f'/*{status_hittest_marker}*/(!t||"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE)&&'
        '(t?e.setIgnoreMouseEvents(!0,{forward:!0}):e.setIgnoreMouseEvents(!1))}',
        'alpha hit-test poller',
    )

if old_flavour:
    tour_anchor = 'x.RA.statusWindow&&!x.RA.statusWindow.isDestroyed()&&x.RA.statusWindow.setIgnoreMouseEvents(!0,{forward:!0})'
    replace_once(
        tour_anchor,
        'x.RA.statusWindow&&!x.RA.statusWindow.isDestroyed()&&'
        f'/*{status_tour_marker}*/"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&'
        'x.RA.statusWindow.setIgnoreMouseEvents(!0,{forward:!0})',
        'feature-tour suspend',
    )
else:
    tour_anchor = (
        'y.H8?Y()?.setIgnoreMouseEvents(!0,{forward:!0}):'
        'P.RA.statusWindow&&!P.RA.statusWindow.isDestroyed()&&'
        'P.RA.statusWindow.setIgnoreMouseEvents(!0,{forward:!0})'
    )
    replace_once(
        tour_anchor,
        'y.H8?("1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&'
        'Y()?.setIgnoreMouseEvents(!0,{forward:!0})):'
        'P.RA.statusWindow&&!P.RA.statusWindow.isDestroyed()&&'
        f'/*{status_tour_marker}*/"1"!==process.env.WISPR_FLOW_STATUS_CLICKABLE&&'
        'P.RA.statusWindow.setIgnoreMouseEvents(!0,{forward:!0})',
        'feature-tour suspend',
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
