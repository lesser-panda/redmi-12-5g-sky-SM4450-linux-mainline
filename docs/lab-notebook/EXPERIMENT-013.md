# EXPERIMENT-013 (E037): touch keyboard (2026-11-13, m25 RAM boot, Debian on sda22)

## Goal / user request
A mobile-like touch keyboard that is easy to use, preferably split; user tried GJS OSK ("couldn't customize it to my liking"). Answers: route "extend built-in OSK", orientation "both".

## Findings
- GNOME Shell 48.7 ships a mobile-like OSK (JSON layouts in `gnome-shell-osk-layouts.gresource`, grid via `KeyContainer`, `Keyboard` class exported from `ui/keyboard.js`). Squeekboard/wvkbd need input-method-v2/layer-shell (not in Mutter), Onboard is XWayland-only, GJS OSK (installed, disabled) is a full replacement without a split layout.
- The panel is 1080x2460; the phone currently runs landscape (transform 3) at scale 1.5 = 1640x720 logical. GNOME's default keyboard height is monitor/3 (landscape) or /4 (portrait) - keys only ~6 mm; we use 50 % / 30 %.
- GNOME's grid layout drops columns that no key occupies, so a wide gap via `leftOffset` collapsed to about one column (first screenshot); fixed with invisible spacer keys (zero-width-space commit string, hidden and made inert by the extension).
- The shell blocks the screenshot D-Bus API for scripts and `Eval`; a development-only extension (`desktop-debian/sky-osk-debug`, not in the release tree) polls `$XDG_RUNTIME_DIR/sky-osk-cmd` (open, close, level, shot, info) and uses `Shell.Screenshot` from inside the shell. Orientation changes for the portrait screenshots were done temporarily through `org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig` (method 1, not persisted) and reverted to transform 3 / scale 1.5.

## Result
- `desktop-debian/sky-osk/` (extension: layouts via `tools/gen-sky-osk-layouts.py`, gresource compiled on the phone with `glib-compile-resources` from libglib2.0-dev-bin (installed on the phone), `config.json` for heights, `stylesheet.css`), installed to the user's extensions directory, enabled; GDM restarted twice to load it. `screen-keyboard-enabled` was set true for testing and put back to false.
- Screenshots (via the debug hook): landscape split layout default level; portrait default, shift (requested, not inspected), symbols levels. Rootfs build integration (push-debian.sh/customize.sh stage, compile, enable by schema default) written and syntax-checked, **not run end to end**.
- **Not verified:** real touch typing, long-press popups (digits on the top row), emoji, hide/language keys, lock-screen use, behaviour with the dock keyboard attached (expected: OSK stays hidden unless the last input was touch).
- Phone state after the experiment: extension `sky-osk` enabled, debug extension disabled but installed (`~/.local/share/gnome-shell/extensions/sky-osk-debug@...`), GJS OSK disabled, display back to landscape 1.5.

## Revision 2 (same day): ortholinear + Planck-style split (user request)
User: "make it ortholinear and align to each sides. In split mode the gap in the middle should be click thru. Ortho should also mean that you can fit a tab and ESC key. In split mode make it similar to my Planck keyboard but, well, split."
- Portrait `sky`: 10 x 5 ortholinear grid, flush to both edges; top strip Esc Tab Ctrl Alt ← ↓ ↑ → Hm End; bottom row `?123` emoji `,` space `.` hide enter.
- Landscape `sky-split`: Planck rows (Tab/Esc/Shift/bottom row) as 6 + 6 keys, 19.5 columns wide (gap 7.5), halves flush to the screen edges; thumb keys Lower (digits/symbols) and Raise (F1-F12, nav, brackets, emoji, language). Explicit widths of 1 for shift/backspace/enter so every row is exactly 19.5 (generator `check()` prints row widths; before that rows were 19/19.5/20/20.5).
- Click-through gap: on Wayland GNOME ignores the chrome input region (`layout.js` `wantsInputRegion` needs !is_wayland_compositor), so the extension sets `reactive=false` on the keyboard and `keyboardBox` in split mode, hides the spacer keys, makes the `#keyboard.sky-split` background transparent and stretches the AspectContainer (`setRatio(1e6, 1)`). Check with the debug hook `pick X Y`: a point in the gap resolves to a plain Clutter_Actor (not the keyboard), a key resolves to St_Button.
- Screenshots after the change: landscape default and Raise, portrait default. The "Home" label was truncated in the portrait strip ("Ho…"), shortened to "Hm".
- **Still not verified:** real touch typing, long-press popups, Ctrl/Alt/Super latching (Super keyval untested), emoji/hide/language keys, lock screen, dock.

## Revision 3 (same day): keyboard quits on Fn/ABC; touches between keys
User: "when I click fn and then ABC (or ?123), or vice versa, the keyboard quits and I have to pull it up again"; then "those transparent gaps between keys are not necessary as well, just keep the middle gap click thru".
- Mechanism (source + logs): GNOME's keyboard closes when `notify::key-focus` moves to a non-text actor or the app drops its text-input focus; with the keyboard and its containers non-reactive, a touch that lands on key padding or between keys goes to the app below. Gap between keys is now covered: every non-spacer key container is `reactive` (`hideSpacers()` in `extension.js`); only the hidden spacers (middle gap) and the keyboard background stay non-reactive. `pick` at key boundaries now resolves to `Key` containers, in the middle gap to the background actor.
- Debug hook now has `keypos`, `click` (virtual pointer), `taps X,Y GAP X,Y ...` (virtual touchscreen), `state`, and logs a stack trace for every `Keyboard.close()` and key-focus change to `$XDG_RUNTIME_DIR/sky-osk-log`.
- Tests on the m25 RAM boot with injected touches in gnome-text-editor: Fn <-> ABC, ?123/Lower <-> Fn/Raise, quick sequences with 100-150 ms pauses: the keyboard stayed open and the level followed each tap. **The bug could not be reproduced here (neither before nor after the change, including with pointer clicks), so the fix is not proven; the debug hook stays enabled on the phone to capture the close() stack on the next occurrence.**
