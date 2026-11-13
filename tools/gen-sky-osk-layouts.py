#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generate the touch keyboard layouts for the sky-osk GNOME Shell extension (E037).

Output: rootfs/sky-osk/layouts/sky.json (portrait, 10 columns x 5 rows, ortholinear) and sky-split.json (landscape, Planck-style 6+6 split with a gap in the middle).
The JSON format is GNOME Shell's own (js/ui/keyboard.js, KeyContainer): rows of keys on a grid; per key "width", "leftOffset" (empty columns
before it), "strings" (first = what is typed, the rest = long-press alternates), "action"/"level"/"iconName"/"label".
Edit this file (e.g. KEYS, ROW_* below), run tools/build-sky-osk.sh, and the keyboard changes. The accent alternates on the letters follow the
layout that ships with GNOME Shell 48 (US layout, GPL-2.0-or-later, https://gitlab.gnome.org/GNOME/gnome-shell).
"""
import json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'rootfs/sky-osk/layouts'

ACCENTS = {
    'a': 'àáâäæãåā', 'c': 'çćč', 'e': 'èéêëē', 'i': 'îïíīì', 'l': 'ł', 'n': 'ñń', 'o': 'ôöòóœøōõ', 's': 'ßśš',
    'u': 'ûüùúū', 'y': 'ÿ', 'z': 'žźż',
}
DIGIT_OF = dict(zip('qwertyuiop', '1234567890'))


def letter(c, upper=False):
    alts = [DIGIT_OF[c]] if (c in DIGIT_OF and not upper) else []
    alts += list(ACCENTS.get(c, ''))
    if upper:
        alts = [a.upper() for a in alts]
    return {'strings': [c.upper() if upper else c] + alts}


def sym(c, *alts):
    return {'strings': [c, *alts]}


def space(w):
    return {'strings': [' '], 'width': w}


def shift(level, w=1.5):
    return {'action': 'levelSwitch', 'iconName': 'osk-shift-symbolic', 'level': level, 'width': w}


def switch(label, level, w=1.5):
    return {'action': 'levelSwitch', 'label': label, 'level': level, 'width': w}


def delete(w=1.5):
    return {'action': 'delete', 'iconName': 'osk-delete-symbolic', 'width': w}


def enter(w=1.5):
    return {'iconName': 'osk-enter-symbolic', 'keyval': '0xff0d', 'width': w}


def emoji(w=1):
    return {'action': 'emoji', 'iconName': 'osk-emoji-picker-symbolic', 'width': w}


def lang(w=1):
    return {'action': 'languageMenu', 'iconName': 'osk-layout-symbolic', 'width': w}


def hide(w=1):
    return {'action': 'hide', 'iconName': 'osk-hide-symbolic', 'width': w}


SPACER = '\u200b'   # the extension hides keys that commit this string and makes them inert


def place(*items, spacers=False):
    """items: key dicts, or a number = empty columns before the next key.
    GNOME's grid drops columns that no key touches, so wide gaps (the split layout) need an invisible spacer key (spacers=True);
    small offsets in the 10-column portrait layout are covered by keys of the other rows and use leftOffset."""
    row, gap = [], 0
    for it in items:
        if isinstance(it, (int, float)):
            gap += it
            continue
        k = dict(it)
        if gap and spacers:
            row.append({'strings': [SPACER], 'width': gap})
        elif gap:
            k['leftOffset'] = gap
        gap = 0
        row.append(k)
    return row


def keys(s, upper=False):
    return [letter(c, upper) for c in s]


PUNCT = [sym('.', ',', '?', '!', ':', ';', "'", '"', '…'), ]


KV = {'esc': 0xff1b, 'tab': 0xff09, 'home': 0xff50, 'left': 0xff51, 'up': 0xff52, 'right': 0xff53, 'down': 0xff54, 'pgup': 0xff55,
      'pgdn': 0xff56, 'end': 0xff57, 'ins': 0xff63, 'del': 0xffff, 'enter': 0xff0d, 'ctrl': 0xffe3, 'alt': 0xffe9, 'super': 0xffeb}
ARROWS = {'left': 'go-previous-symbolic', 'up': 'go-up-symbolic', 'right': 'go-next-symbolic', 'down': 'go-down-symbolic'}
LABELS = {'esc': 'Esc', 'tab': 'Tab', 'home': 'Home', 'end': 'End', 'pgup': 'PgUp', 'pgdn': 'PgDn', 'ins': 'Ins', 'del': 'Del',
          'ctrl': 'Ctrl', 'alt': 'Alt', 'super': 'Super'}


def kv(name, w=1):
    """A key that sends a keysym (Esc, Tab, arrows, F-keys ...); Ctrl/Alt/Super are latching modifiers."""
    if name.startswith('f') and name[1:].isdigit():
        k = {'keyval': hex(0xffbe + int(name[1:]) - 1), 'label': name.upper()}
    else:
        k = {'keyval': hex(KV[name])}
        if name in ARROWS:
            k['iconName'] = ARROWS[name]
        elif name == 'enter':
            k['iconName'] = 'osk-enter-symbolic'
        else:
            k['label'] = LABELS[name]
    if name in ('ctrl', 'alt', 'super'):
        k['action'] = 'modifier'
    if w != 1:
        k['width'] = w
    return k


def portrait():
    """10 columns x 5 rows, ortholinear (no stagger), both edges flush. Row 0 is an Esc/Tab/Ctrl/Alt/arrows strip."""
    strip = lambda: place(kv('esc'), kv('tab'), kv('ctrl'), kv('alt'), kv('left'), kv('down'), kv('up'), kv('right'), dict(kv('home'), label='Hm'), kv('end'))
    bottom = lambda first: place(first, emoji(), sym(',', '!', ';'), space(3), sym('.', '?', ':', "'", '"', '\u2026'), hide(), kv('enter', 1.5))

    def letters(up):
        return [
            strip(),
            place(*keys('qwertyuiop', up)),
            place(*keys('asdfghjkl', up), sym("'", '"') if not up else sym('"')),
            place(shift('default' if up else 'shift'), *keys('zxcvbnm', up), delete()),
            bottom(switch('?123', 'opt')),
        ]
    sets = {
        'opt': ('1234567890', '@#$%&-+()/', '*"\':;!?'),
        'opt+shift': ('~`|\u2022\u221a\u03c0\u00f7\u00d7\u00b6\u2206', '\u00a3\u00a2\u20ac\u00a5^\u00b0={}\\', '\u00a9\u00ae\u2122\u2105[]<'),
    }
    levels = [
        {'level': 'default', 'mode': 'default', 'rows': letters(False)},
        {'level': 'shift', 'mode': 'latched', 'rows': letters(True)},
    ]
    for name, (r1, r2, r3) in sets.items():
        other = 'opt+shift' if name == 'opt' else 'opt'
        levels.append({'level': name, 'mode': 'locked', 'rows': [
            strip(),
            place(*[sym(c) for c in r1]),
            place(*[sym(c) for c in r2]),
            place(switch('=/<' if name == 'opt' else '?123', other), *[sym(c) for c in r3], delete(1.5)),
            bottom(switch('ABC', 'default')),
        ]})
    return {'name': 'sky portrait', 'locale': 'us', 'levels': levels}


def split():
    """Planck style: 4 rows x (6 + 6) keys, ortholinear, each half flush to its screen edge, an empty gap between (spacer, see place()).
    Row 1  Tab Q W E R T | Y U I O P Bksp      Row 2  Esc A S D F G | H J K L ; '
    Row 3  Shift Z X C V B | N M , . / Enter   Row 4  Hide Ctrl Alt Super Lower Space | Space Raise Left Down Up Right
    Lower = digits and symbols (opt), Raise = F-keys, navigation and brackets (opt+shift). The gap is GAP columns wide (18 columns in total
    is about square keys on the 2460x1080 panel)."""
    GAP = 7.5

    def row(left, right):
        return place(*left, GAP, *right, spacers=True)

    def letters(up):
        s = shift('default' if up else 'shift', 1)
        punct = [sym(':', ';'), sym('"', "'")] if up else [sym(';', ':'), sym("'", '"')]
        lo = [sym('<', ','), sym('>', '.'), sym('?', '/')] if up else [sym(',', '!', '<'), sym('.', '?', '>'), sym('/', '?')]
        return [
            row([kv('tab'), *keys('qwert', up)], [*keys('yuiop', up), delete(1)]),
            row([kv('esc'), *keys('asdfg', up)], [*keys('hjkl', up), *punct]),
            row([s, *keys('zxcvb', up)], [*keys('nm', up), *lo, kv('enter')]),
            bottom('default'),
        ]

    def bottom(cur):
        lower = switch('ABC', 'default', 1) if cur == 'opt' else switch('?123', 'opt', 1)
        raise_ = switch('ABC', 'default', 1) if cur == 'opt+shift' else switch('Fn', 'opt+shift', 1)
        return row([hide(), kv('ctrl'), kv('alt'), kv('super'), lower, space(1)],
                   [space(1), raise_, kv('left'), kv('down'), kv('up'), kv('right')])

    def symbols(name):
        if name == 'opt':
            return [
                row([kv('tab'), *[sym(c) for c in '12345']], [*[sym(c) for c in '67890'], delete(1)]),
                row([kv('esc'), *[sym(c) for c in '!@#$%']], [*[sym(c) for c in '^&*()'], sym('_', '-')]),
                row([switch('=/<', 'opt+shift', 1), sym('`', '~'), sym('-', '_'), sym('=', '+'), sym('\\', '|'), sym("'", '"')],
                    [sym(';', ':'), sym('[', '{'), sym(']', '}'), sym(',', '<'), sym('.', '>'), kv('enter')]),
                bottom('opt'),
            ]
        return [
            row([kv('tab'), *[kv(f'f{i}') for i in range(1, 6)]], [*[kv(f'f{i}') for i in range(6, 11)], delete(1)]),
            row([kv('esc'), kv('f11'), kv('f12'), kv('pgup'), kv('pgdn'), kv('del')],
                [kv('home'), kv('left'), kv('down'), kv('up'), kv('right'), kv('end')]),
            row([switch('?123', 'opt', 1), emoji(), lang(), sym('('), sym(')'), sym('/')],
                [sym('{'), sym('}'), sym('['), sym(']'), sym('?'), kv('enter')]),
            bottom('opt+shift'),
        ]
    levels = [
        {'level': 'default', 'mode': 'default', 'rows': letters(False)},
        {'level': 'shift', 'mode': 'latched', 'rows': letters(True)},
        {'level': 'opt', 'mode': 'locked', 'rows': symbols('opt')},
        {'level': 'opt+shift', 'mode': 'locked', 'rows': symbols('opt+shift')},
    ]
    return {'name': 'sky split', 'locale': 'us', 'levels': levels}


def check(model):
    """Each row must fill the same number of columns (the grid is homogeneous) - report the widths."""
    widths = set()
    for lv in model['levels']:
        for r in lv['rows']:
            widths.add(round(sum(k.get('width', 1) + k.get('leftOffset', 0) for k in r), 3))
    return widths


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for name, model in (('sky', portrait()), ('sky-split', split())):
        w = check(model)
        print(name, 'row widths (columns):', sorted(w))
        (OUT / f'{name}.json').write_text(json.dumps(model, ensure_ascii=False, indent=1) + '\n')
