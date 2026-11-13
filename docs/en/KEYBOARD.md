# Touch keyboard

The phone uses **GNOME Shell's own on-screen keyboard** (it already handles Wayland text input, long-press popups, emoji and the lock screen)
with two layouts of our own, delivered as a small GNOME Shell extension, `sky-osk` (`rootfs/sky-osk/`):

| Orientation | Layout | What it is |
|---|---|---|
| Portrait | `sky` | **Ortholinear** 10 x 5 grid, keys aligned in straight columns and flush to both screen edges. Top row is a utility strip: Esc, Tab, Ctrl, Alt, the four arrows, Hm (Home), End. Then `q-p`, `a-l` and `'`, shift + `z-m` + backspace, and a bottom row `?123`, emoji, `,`, space, `.`, hide, enter. Long-press a letter for accents. |
| Landscape | `sky-split` | A **Planck-style split**: 4 rows of 6 + 6 keys on one ortholinear grid. Left half `Tab q w e r t` / `Esc a s d f g` / `Shift z x c v b` / `Hide Ctrl Alt Super Lower Space`; right half `y u i o p Bksp` / `h j k l ; '` / `n m , . / Enter` / `Space Raise` + arrows. The halves are flush to the screen edges and the **gap between them is click-through** (the keyboard is transparent there, taps reach the app underneath). 50 % of the screen height. |

The split layout's thumb keys work like a Planck: **Lower** gives digits and symbols, **Raise** gives F1-F12, Home/End, PgUp/PgDn, Del, arrows, brackets, emoji and the language key.
Ctrl, Alt and Super latch for one key press (tap, then the letter).

GNOME's own keyboards stay in place for numbers, phone, e-mail, URL and terminal fields, and for every input source other than `us`.
The layout follows the monitor orientation (there are no sensors, rotate in Settings > Displays).

## When it appears
GNOME shows the keyboard when you touch a text field and the last input came from the touchscreen, and not when you type on a real (dock) keyboard.
To force it on, use the accessibility menu in the top bar > Screen Keyboard (the switch `org.gnome.desktop.a11y.applications screen-keyboard-enabled`).
A swipe up from the bottom edge also opens it.

## Install
The rootfs build (`tools/push-debian.sh`) installs and enables it. On a running phone:

```sh
tools/build-sky-osk.sh install      # generates the layouts, compiles them on the phone, copies the extension (adds libglib2.0-dev-bin there)
# log out and in once (Wayland loads new extensions only in a new session), then
gnome-extensions enable sky-osk@redmi-12-5g.local
```

## Customize
| What | Where | How to apply |
|---|---|---|
| Keys, widths, gaps, long-press alternates, the whole split geometry | `tools/gen-sky-osk-layouts.py` (plain Python, `portrait()` and `split()`) | `tools/build-sky-osk.sh install`, then `gnome-extensions disable` and `enable` the extension |
| Keyboard height (fraction of the screen) | `rootfs/sky-osk/config.json`: `portraitHeight`, `landscapeHeight` | same |
| Key size of text, spacing, corner radius | `rootfs/sky-osk/stylesheet.css` | same |
| Behaviour (which layout in which case) | `rootfs/sky-osk/extension.js` | install, then log out and in (JavaScript modules are cached) |

Layout format (GNOME Shell's own JSON, see `js/ui/keyboard.js` in GNOME Shell): `levels` (`default`, `shift`, `opt` = Lower/symbols, `opt+shift` = Raise), each with `rows` of keys on a grid.
A key has `strings` (the first is typed, the rest appear on long press), optional `width` (columns, default 1), `leftOffset`, or an `action`
(`levelSwitch`, `delete`, `emoji`, `languageMenu`, `hide`, `modifier`) with an `iconName` or `label`, or a `keyval` for keys such as Esc and the arrows.
The portrait layout is 10 columns wide; the split layout is 19.5 columns (left half 6 columns, a 7.5 column gap, right half 6 columns) and `check()` in the generator prints the width of every row so a mismatch is caught when you edit.
Wide gaps need an invisible spacer key because GNOME's grid drops columns no key touches (the generator does this: `spacers=True`).
The extension then hides the spacers, makes the split keyboard's background and grid non-reactive while every key's container (the key plus its padding) stays reactive. That is what makes only the middle gap click-through on Wayland, where GNOME does not use the chrome input region; a tap between two keys is swallowed by the keyboard instead of reaching the app, because a tap that reaches the app drops its text focus and GNOME then closes the keyboard and stretches the grid to the full width.

Ideas that fit this format: a number row above the letters (add a row), a one-handed layout shifted to one side (leading spacer), a bigger gap or a smaller height for
the split layout, other punctuation on the thumb layers, a language key in the portrait strip (`lang()`).

## Limits
- Only the `us` input source is replaced. Another source (for example a Chinese input method) keeps GNOME's layout for it, including its language key; the portrait layout has no language key, use the Raise layer of the split layout or add `lang()` to `portrait()`.
- No haptic feedback, no swipe typing, no word suggestions of our own (GNOME shows IBus suggestions when an engine provides them).
- Tested on GNOME Shell 48.7 (Debian trixie) with screenshots taken from inside the shell: landscape default and Raise layers, portrait default and symbols layers (an earlier version of the portrait layout; the 10 x 5 version was captured in the default layer). The click-through gap was checked by asking the shell which actor lies under a point in the gap (not the keyboard) and under a key (a button). The user typed with it on the phone and confirmed it works; a bug where the keyboard closed when switching between the Fn and ABC/?123 keys (touches between keys fell through to the app) is fixed. **Long-press popups, the modifier keys (Super in particular), emoji/hide/language keys, the lock screen and the dock were not individually checked.**

## Why not another keyboard
Squeekboard (Phosh) and wvkbd need the `input-method-v2` / layer-shell Wayland protocols that GNOME's compositor does not offer; Onboard works only through
XWayland; the GJS OSK extension replaces the whole keyboard with its own implementation (no true split layout, many settings). Extending the built-in keyboard keeps the
text-input integration and costs about 200 lines.
