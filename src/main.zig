const std = @import("std");
const win32 = @import("win32.zig");
const ui = @import("ui.zig");
const config = @import("config.zig");
const tray = @import("tray.zig");

pub fn main() void {
    // DPI awareness
    _ = win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    // Load config
    const cfg = config.loadConfig();

    // Register global hotkey (Ctrl+Space = switcher)
    if (win32.RegisterHotKey(null, 1, cfg.hotkey_modifiers, cfg.hotkey_vk) == 0) {
        _ = win32.MessageBoxW(null, toWide("Failed to register hotkey. It may be in use by another application."), toWide("ZigSwitch Error"), win32.MB_OK | win32.MB_ICONERROR);
        return;
    }


    // Create overlay window
    const hInstance = win32.GetModuleHandleW(null);
    ui.init(hInstance, cfg);

    // Create system tray icon (Alt+Tab hook is OFF by default)
    tray.init(hInstance, ui.getHwnd());

    // Message loop
    var msg: win32.MSG = undefined;
    while (true) {
        const ret = win32.GetMessageW(&msg, null, 0, 0);
        if (ret == 0 or ret == -1) break;

        if (msg.message == win32.WM_HOTKEY) {
            ui.toggle();
        } else {
            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
        }
    }

    tray.deinit();
    _ = win32.UnregisterHotKey(null, 1);
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
