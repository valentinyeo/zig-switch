const std = @import("std");
const win32 = @import("win32.zig");
const ui = @import("ui.zig");
const config = @import("config.zig");

// Hotkey IDs passed to RegisterHotKey/UnregisterHotKey.
const HOTKEY_TOGGLE: i32 = 1;
const HOTKEY_ALTTAB_NEXT: i32 = 2;
const HOTKEY_ALTTAB_PREV: i32 = 3;

pub fn main() void {
    // DPI awareness
    _ = win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    // Load config
    const cfg = config.loadConfig();

    // Register global hotkey (Ctrl+Space = switcher)
    if (win32.RegisterHotKey(null, HOTKEY_TOGGLE, cfg.hotkey_modifiers | win32.MOD_NOREPEAT, cfg.hotkey_vk) == 0) {
        _ = win32.MessageBoxW(null, toWide("Failed to register hotkey. It may be in use by another application."), toWide("ZigSwitch Error"), win32.MB_OK | win32.MB_ICONERROR);
        return;
    }

    // Alt+Tab replacement hotkeys. Windows reserves the literal Alt+Tab
    // chord for its own task switcher (RegisterHotKey can't claim it), and
    // WH_KEYBOARD_LL hooks are banned on this machine, so this app uses its
    // own chord instead: hold Ctrl+Alt, tap Down/Up to cycle. Best-effort —
    // if another app already owns these, the main toggle still works.
    _ = win32.RegisterHotKey(null, HOTKEY_ALTTAB_NEXT, cfg.alttab_next_modifiers | win32.MOD_NOREPEAT, cfg.alttab_next_vk);
    _ = win32.RegisterHotKey(null, HOTKEY_ALTTAB_PREV, cfg.alttab_prev_modifiers | win32.MOD_NOREPEAT, cfg.alttab_prev_vk);

    // Create overlay window
    const hInstance = win32.GetModuleHandleW(null);
    ui.init(hInstance, cfg);

    // Register to start with Windows only after the required hotkey is available.
    registerAutoStart();

    // Message loop
    var msg: win32.MSG = undefined;
    while (true) {
        const ret = win32.GetMessageW(&msg, null, 0, 0);
        if (ret == 0 or ret == -1) break;

        if (msg.message == win32.WM_HOTKEY) {
            switch (@as(i32, @intCast(msg.wParam))) {
                HOTKEY_TOGGLE => ui.toggle(),
                HOTKEY_ALTTAB_NEXT => if (ui.isAltTabActive()) ui.altTabNext() else ui.altTabShow(),
                HOTKEY_ALTTAB_PREV => ui.altTabPrev(),
                else => {},
            }
        } else {
            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
        }
    }

    ui.deinit();
    _ = win32.UnregisterHotKey(null, HOTKEY_TOGGLE);
    _ = win32.UnregisterHotKey(null, HOTKEY_ALTTAB_NEXT);
    _ = win32.UnregisterHotKey(null, HOTKEY_ALTTAB_PREV);
}

fn registerAutoStart() void {
    // Get our exe path
    var path_buf: [512]u16 = [_]u16{0} ** 512;
    const path_len = win32.GetModuleFileNameW(null, &path_buf, 512);
    if (path_len == 0 or path_len >= 512) return;

    // Open Run key
    const sub_key = comptime toWide("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
    var hkey: win32.HKEY = undefined;
    if (win32.RegOpenKeyExW(win32.HKEY_CURRENT_USER, sub_key, 0, win32.KEY_SET_VALUE, &hkey) != 0) return;
    defer _ = win32.RegCloseKey(hkey);

    // Set value (path as null-terminated wide string)
    const value_name = comptime toWide("ZigSwitch");
    const byte_len: win32.DWORD = @intCast((path_len + 1) * 2); // include null, in bytes
    _ = win32.RegSetValueExW(hkey, value_name, 0, win32.REG_SZ, @ptrCast(&path_buf), byte_len);
}

fn toWide(comptime s: []const u8) [*:0]const u16 {
    const result = comptime blk: {
        var buf: [s.len + 1]u16 = undefined;
        for (s, 0..) |c, i| {
            buf[i] = c;
        }
        buf[s.len] = 0;
        break :blk buf;
    };
    return @ptrCast(&result);
}
