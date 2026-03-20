const std = @import("std");
const win32 = @import("win32.zig");
const ui = @import("ui.zig");
const config = @import("config.zig");

var kb_hook: ?win32.HHOOK = null;
var msg_hwnd: ?win32.HWND = null;

pub fn main() void {
    // DPI awareness
    _ = win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    // Load config
    const cfg = config.loadConfig();

    // Register global hotkey (Ctrl+Space as fallback/additional trigger)
    _ = win32.RegisterHotKey(null, 1, cfg.hotkey_modifiers, cfg.hotkey_vk);

    // Create overlay window
    const hInstance = win32.GetModuleHandleW(null);
    ui.init(hInstance, cfg);

    // Create a hidden message-only window to receive PostMessage from the hook
    const msg_class = comptime toWide("ZigSwitchMsg");
    const wc = win32.WNDCLASSEXW{
        .lpfnWndProc = msgWndProc,
        .hInstance = hInstance,
        .lpszClassName = msg_class,
    };
    _ = win32.RegisterClassExW(&wc);
    msg_hwnd = win32.CreateWindowExW(
        0, msg_class, msg_class, 0,
        0, 0, 0, 0,
        null, null, hInstance, null,
    );

    // Install low-level keyboard hook to intercept Alt+Tab
    kb_hook = win32.SetWindowsHookExW(win32.WH_KEYBOARD_LL, keyboardHookProc, hInstance, 0);
    if (kb_hook == null) {
        _ = win32.MessageBoxW(
            null,
            toWide("Failed to install keyboard hook for Alt+Tab replacement."),
            toWide("ZigSwitch Warning"),
            win32.MB_OK | win32.MB_ICONERROR,
        );
    }

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

    // Cleanup
    if (kb_hook) |hook| {
        _ = win32.UnhookWindowsHookEx(hook);
    }
    _ = win32.UnregisterHotKey(null, 1);
}

fn msgWndProc(hwnd: win32.HWND, msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    if (msg == win32.WM_APP_ALTTAB) {
        ui.toggle();
        return 0;
    }
    return win32.DefWindowProcW(hwnd, msg, wParam, lParam);
}

// Low-level keyboard hook callback
// Intercepts Alt+Tab and swallows it, posting a message to our window instead
fn keyboardHookProc(nCode: i32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    if (nCode == win32.HC_ACTION) {
        const kb: *const win32.KBDLLHOOKSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));

        // Detect Alt+Tab (key down only, not key up)
        if (wParam == win32.WM_SYSKEYDOWN or wParam == win32.WM_KEYDOWN_HOOK) {
            if (kb.vkCode == win32.VK_TAB_U32) {
                // Check if Alt is held (LLKHF_ALTDOWN flag)
                if (kb.flags & win32.LLKHF_ALTDOWN != 0) {
                    // Swallow Alt+Tab, trigger our switcher
                    if (msg_hwnd) |hwnd| {
                        _ = win32.PostMessageW(hwnd, win32.WM_APP_ALTTAB, 0, 0);
                    }
                    return 1; // Block the keystroke
                }
            }
        }

        // Also block the Alt key-up after we've intercepted Alt+Tab
        // to prevent the system menu from appearing
        if (wParam == win32.WM_KEYUP_HOOK or wParam == win32.WM_SYSKEYUP) {
            if (kb.vkCode == win32.VK_LMENU or kb.vkCode == win32.VK_RMENU) {
                // Only block if our overlay is visible (we just triggered it)
                if (ui.isVisible()) {
                    return 1;
                }
            }
        }
    }

    return win32.CallNextHookEx(kb_hook, nCode, wParam, lParam);
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
