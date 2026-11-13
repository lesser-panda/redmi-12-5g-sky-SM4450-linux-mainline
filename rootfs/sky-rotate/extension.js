// SPDX-License-Identifier: MIT
// Top bar menu for the built-in screen's orientation (the phone has no accelerometer that Linux can use).
// Uses Mutter's DisplayConfig D-Bus API, the same one GNOME Settings uses: the built-in panel's logical monitor gets the new transform, its scale,
// mode and every other monitor (for example a dock's HDMI screen) stay as they are. It is applied as a temporary configuration (method 1: Mutter's
// "keep these settings?" countdown only comes with the persistent method), so the choice is remembered here, in
// ~/.config/sky-rotate/orientation, and applied again when the extension loads at login.
//   transform 0 = portrait (panel's native orientation), 1 = landscape right (phone top towards the right), 3 = landscape left (top towards the left)
import GObject from 'gi://GObject';
import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const BUS = 'org.gnome.Mutter.DisplayConfig';
const PATH = '/org/gnome/Mutter/DisplayConfig';
const ORIENTATIONS = [
    {label: 'Portrait', transform: 0},
    {label: 'Landscape left', transform: 3},
    {label: 'Landscape right', transform: 1},
];

function getState() {
    return new Promise((resolve, reject) => {
        Gio.DBus.session.call(BUS, PATH, BUS, 'GetCurrentState', null, null, Gio.DBusCallFlags.NONE, -1, null, (conn, res) => {
            try {
                const [serial, monitors, logical] = conn.call_finish(res).recursiveUnpack();
                resolve({serial, monitors, logical});
            } catch (e) {
                reject(e);
            }
        });
    });
}

// the logical monitor that shows the built-in panel (falls back to the primary one)
function builtinLogical(state) {
    const builtin = state.monitors.filter(m => m[2]['is-builtin']).map(m => m[0][0]);
    return state.logical.find(l => l[5].some(mm => builtin.includes(mm[0]))) ?? state.logical.find(l => l[4]) ?? state.logical[0];
}

const SAVE_FILE = GLib.build_filenamev([GLib.get_user_config_dir(), 'sky-rotate', 'orientation']);

function loadSaved() {
    try {
        const [, bytes] = Gio.File.new_for_path(SAVE_FILE).load_contents(null);
        const t = parseInt(new TextDecoder().decode(bytes).trim());
        return ORIENTATIONS.some(o => o.transform === t) ? t : null;
    } catch (e) {
        return null;
    }
}

function save(transform) {
    try {
        GLib.mkdir_with_parents(GLib.path_get_dirname(SAVE_FILE), 0o755);
        Gio.File.new_for_path(SAVE_FILE).replace_contents(new TextEncoder().encode(`${transform}\n`), null, false, Gio.FileCreateFlags.NONE, null);
    } catch (e) {
        console.error(`sky-rotate: cannot save the choice: ${e}`);
    }
}

async function setTransform(transform) {
    const state = await getState();
    const target = builtinLogical(state);
    if (!target)
        throw new Error('no monitor');
    if (target[3] === transform)
        return;
    const config = state.logical.map(l => {
        const [x, y, scale, tr, primary, mons] = l;
        const entries = mons.map(mm => {
            const mon = state.monitors.find(m => m[0][0] === mm[0]);
            const mode = mon[1].find(md => md[6]['is-current']) ?? mon[1][0];
            return [mm[0], mode[0], {}];
        });
        return [x, y, scale, l === target ? transform : tr, primary, entries];
    });
    await new Promise((resolve, reject) => {
        Gio.DBus.session.call(BUS, PATH, BUS, 'ApplyMonitorsConfig',
            new GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})', [state.serial, 1, config, {}]),
            null, Gio.DBusCallFlags.NONE, -1, null, (conn, res) => {
                try {
                    conn.call_finish(res);
                    resolve();
                } catch (e) {
                    reject(e);
                }
            });
    });
}

const Indicator = GObject.registerClass(class SkyRotateIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Screen rotation');
        this.add_child(new St.Icon({icon_name: 'object-rotate-right-symbolic', style_class: 'system-status-icon'}));
        this._items = ORIENTATIONS.map(o => {
            const item = new PopupMenu.PopupMenuItem(o.label);
            item.connect('activate', () => this._apply(o.transform));
            this.menu.addMenuItem(item);
            return {item, transform: o.transform};
        });
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._refresh();
        });
        this._monitorsId = Main.layoutManager.connect('monitors-changed', () => this._refresh());
        this._refresh();
    }

    async _refresh() {
        try {
            const current = builtinLogical(await getState())[3];
            for (const {item, transform} of this._items)
                item.setOrnament(transform === current ? PopupMenu.Ornament.DOT : PopupMenu.Ornament.NONE);
        } catch (e) {
            console.error(`sky-rotate: ${e}`);
        }
    }

    async _apply(transform) {
        try {
            await setTransform(transform);
            save(transform);
        } catch (e) {
            Main.notifyError('Screen rotation failed', `${e.message ?? e}`);
        }
    }

    destroy() {
        if (this._monitorsId) {
            Main.layoutManager.disconnect(this._monitorsId);
            this._monitorsId = 0;
        }
        super.destroy();
    }
});

export default class SkyRotate extends Extension {
    enable() {
        this._indicator = new Indicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator);
        // login: restore the remembered orientation once the monitors are up
        const saved = loadSaved();
        if (saved !== null) {
            this._restoreId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
                this._restoreId = 0;
                setTransform(saved).catch(e => console.error(`sky-rotate: restore failed: ${e}`));
                return GLib.SOURCE_REMOVE;
            });
        }
    }

    disable() {
        if (this._restoreId) {
            GLib.source_remove(this._restoreId);
            this._restoreId = 0;
        }
        this._indicator?.destroy();
        this._indicator = null;
    }
}
