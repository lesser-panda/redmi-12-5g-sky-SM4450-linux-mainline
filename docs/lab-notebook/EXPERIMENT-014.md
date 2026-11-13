# EXPERIMENT-014 (E038): screen rotation menu (2026-11-13, m25 RAM/recovery_b boot, Debian on sda22)

## Request
User: "make an extension that lives in the top bar to select screen rotation. Drop down select portrait, landscape left, landscape right."

## Design
- `desktop-debian/sky-rotate/` (GNOME Shell 48 extension, PanelMenu.Button + PopupMenu with a dot on the current item). It calls `org.gnome.Mutter.DisplayConfig` `GetCurrentState` / `ApplyMonitorsConfig`, changes only the transform of the logical monitor that holds the built-in panel (`is-builtin`), keeps scale, mode, position and all other logical monitors. Transform 0 = portrait, 3 = landscape left (the phone's previous default; top of the phone towards the left, camera hole at the left in the user's photo), 1 = landscape right.
- First version used the persistent method (2): Mutter shows "Keep these display settings?" with a 15 s revert countdown (seen on the screen, it reverted by itself because the test tap missed the button). Now method 1 (temporary, no dialog) and the choice is stored in `~/.config/sky-rotate/orientation` and re-applied 2 s after the extension loads.
- A new extension is only found by a new Wayland session; GDM was restarted for this (and twice more for code changes).

## Result
- On the m25 boot (virtual touch taps through the debug hook): the top bar icon appears, the menu lists the three entries with the current one marked; Portrait gave a 1080x2460 portrait screen, Landscape right and Landscape left landscape; the saved file holds 0 / 1 / 3 after each choice; the dot follows the real transform; no JS errors from the extension in the journal. Restore at login: saved choice set to 1, GDM restarted, the session came back with transform 1 (scale 1.5); then set back to 3.
- **Not verified:** that "left"/"right" match the user's idea physically (the screenshots cannot show the direction; the choice follows the previous default, which had the camera on the left), behaviour with the DisplayLink dock attached (positions of other monitors are kept as they are; Mutter may refuse an overlapping layout, the extension then shows an error notification).
