const std = @import("std");
const win32 = @import("win32.zig");
const ver = @import("version.zig");

const TRAY_CLASS = toWide("ZigSwitchTray");
const ID_TOGGLE_HOOK: usize = 1001;
const ID_QUIT: usize = 1002;

var tray_hwnd: ?win32.HWND = null;
var nid: win32.NOTIFYICONDATAW = .{};
var hook_enabled: bool = false;
var hook_handle: ?win32.HHOOK = null;
var app_hinstance: ?win32.HINSTANCE = null;

var main_thread_id: win32.DWORD = 0;

pub fn init(hInstance: ?win32.HINSTANCE) void {
    app_hinstance = hInstance;
    main_thread_id = win32.GetCurrentThreadId();

    const wc = win32.WNDCLASSEXW{
        .lpfnWndProc = trayWndProc,
        .hInstance = hInstance,
        .lpszClassName = TRAY_CLASS,
    };
    _ = win32.RegisterClassExW(&wc);

    tray_hwnd = win32.CreateWindowExW(
        0,
        TRAY_CLASS,
        comptime toWide("ZigSwitchTray"),
        0,
        0, 0, 0, 0,
        null, null, hInstance, null,
    );

    const hwnd = tray_hwnd orelse return;

    // Set up tray icon
    nid.hWnd = hwnd;
    nid.uID = 1;
    nid.uFlags = win32.NIF_MESSAGE | win32.NIF_ICON | win32.NIF_TIP;
    nid.uCallbackMessage = win32.WM_APP_TRAY;
    nid.hIcon = win32.LoadIconW(hInstance, 1);

    const tip = "ZigSwitch - Alt+Tab: OFF";
    for (tip, 0..) |c, i| {
        nid.szTip[i] = c;
    }

    _ = win32.Shell_NotifyIconW(win32.NIM_ADD, &nid);

    // Enable Alt+Tab hook by default
    enableHook();
}

pub fn deinit() void {
    disableHook();
    _ = win32.Shell_NotifyIconW(win32.NIM_DELETE, &nid);
}

pub fn isHookEnabled() bool {
    return hook_enabled;
}

pub fn cancelAltTab() void {
    alttab_active = false;
}

fn enableHook() void {
    if (hook_handle != null) return;
    hook_handle = win32.SetWindowsHookExW(
        win32.WH_KEYBOARD_LL,
        &llKeyboardProc,
        app_hinstance,
        0,
    );
    if (hook_handle != null) {
        hook_enabled = true;
        updateTip("ZigSwitch - Alt+Tab: ON");
    }
}

fn disableHook() void {
    if (hook_handle) |h| {
        _ = win32.UnhookWindowsHookEx(h);
        hook_handle = null;
    }
    hook_enabled = false;
    updateTip("ZigSwitch - Alt+Tab: OFF");
}

fn updateTip(tip: []const u8) void {
    @memset(&nid.szTip, 0);
    for (tip, 0..) |c, i| {
        nid.szTip[i] = c;
    }
    nid.uFlags = win32.NIF_TIP;
    _ = win32.Shell_NotifyIconW(win32.NIM_MODIFY, &nid);
}

fn showMenu(hwnd: win32.HWND) void {
    const menu = win32.CreatePopupMenu() orelse return;
    defer _ = win32.DestroyMenu(menu);

    const label = if (hook_enabled)
        comptime toWide("Disable Alt+Tab Hook")
    else
        comptime toWide("Enable Alt+Tab Hook");
    const label_flags: win32.UINT = win32.MF_STRING | (if (hook_enabled) win32.MF_CHECKED else 0);

    // Version header (grayed out, just info)
    _ = win32.AppendMenuW(menu, win32.MF_GRAYED, 0, comptime toWide("ZigSwitch v" ++ ver.version));
    _ = win32.AppendMenuW(menu, win32.MF_GRAYED, 0, comptime toWide(ver.summary));
    _ = win32.AppendMenuW(menu, win32.MF_SEPARATOR, 0, null);
    _ = win32.AppendMenuW(menu, label_flags, ID_TOGGLE_HOOK, label);
    _ = win32.AppendMenuW(menu, win32.MF_SEPARATOR, 0, null);
    _ = win32.AppendMenuW(menu, win32.MF_STRING, ID_QUIT, comptime toWide("Quit ZigSwitch"));

    var pt: win32.POINT = .{};
    _ = win32.GetCursorPos(&pt);

    // Required to make menu disappear when clicking elsewhere
    _ = win32.SetForegroundWindow(hwnd);
    _ = win32.TrackPopupMenu(menu, win32.TPM_BOTTOMALIGN | win32.TPM_LEFTALIGN, pt.x, pt.y, 0, hwnd, null);
}

fn trayWndProc(hwnd: win32.HWND, msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    switch (msg) {
        win32.WM_APP_TRAY => {
            const event: u32 = @intCast(lParam & 0xFFFF);
            if (event == win32.WM_RBUTTONUP) {
                showMenu(hwnd);
            }
            return 0;
        },
        win32.WM_COMMAND => {
            const cmd = wParam & 0xFFFF;
            if (cmd == ID_TOGGLE_HOOK) {
                if (hook_enabled) disableHook() else enableHook();
            } else if (cmd == ID_QUIT) {
                deinit();
                win32.PostQuitMessage(0);
            }
            return 0;
        },
        else => return win32.DefWindowProcW(hwnd, msg, wParam, lParam),
    }
}

var alt_held = false;
var shift_held = false;
var alttab_active = false; // true while Alt is held and overlay was opened via Alt+Tab

fn llKeyboardProc(nCode: i32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    if (nCode == win32.HC_ACTION) {
        const kb: *const win32.KBDLLHOOKSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));

        // Track Shift key state
        if (kb.vkCode == win32.VK_LSHIFT or kb.vkCode == win32.VK_RSHIFT) {
            if (wParam == win32.WM_KEYDOWN_HOOK or wParam == win32.WM_SYSKEYDOWN) {
                shift_held = true;
            } else if (wParam == win32.WM_KEYUP_HOOK or wParam == win32.WM_SYSKEYUP) {
                shift_held = false;
            }
        }

        // Track Alt key state
        if (kb.vkCode == win32.VK_LMENU or kb.vkCode == win32.VK_RMENU) {
            if (wParam == win32.WM_KEYDOWN_HOOK or wParam == win32.WM_SYSKEYDOWN) {
                alt_held = true;
            } else if (wParam == win32.WM_KEYUP_HOOK or wParam == win32.WM_SYSKEYUP) {
                alt_held = false;
                // Alt released while in Alt+Tab mode → activate selected
                if (alttab_active) {
                    alttab_active = false;
                    if (main_thread_id != 0) {
                        _ = win32.PostThreadMessageW(main_thread_id, win32.WM_APP_ALTTAB_ACTIVATE, 0, 0);
                    }
                    // Consume Alt-up so Windows doesn't open the menu bar
                    return 1;
                }
            }
        }

        // Space while in Alt+Tab mode → switch to search
        if (kb.vkCode == win32.VK_SPACE and alttab_active) {
            if (wParam == win32.WM_KEYDOWN_HOOK or wParam == win32.WM_SYSKEYDOWN) {
                alttab_active = false;
                if (main_thread_id != 0) {
                    _ = win32.PostThreadMessageW(main_thread_id, win32.WM_APP_ALTTAB_SEARCH, 0, 0);
                }
            }
            return 1;
        }

        // Intercept Alt+Tab
        if (kb.vkCode == win32.VK_TAB_U32 and alt_held) {
            if (wParam == win32.WM_KEYDOWN_HOOK or wParam == win32.WM_SYSKEYDOWN) {
                if (main_thread_id != 0) {
                    const shift = shift_held;
                    if (!alttab_active) {
                        alttab_active = true;
                        if (shift) {
                            _ = win32.PostThreadMessageW(main_thread_id, win32.WM_APP_ALTTAB_PREV, 0, 0);
                        } else {
                            _ = win32.PostThreadMessageW(main_thread_id, win32.WM_APP_ALTTAB, 0, 0);
                        }
                    } else {
                        if (shift) {
                            _ = win32.PostThreadMessageW(main_thread_id, win32.WM_APP_ALTTAB_PREV, 0, 0);
                        } else {
                            _ = win32.PostThreadMessageW(main_thread_id, win32.WM_APP_ALTTAB_NEXT, 0, 0);
                        }
                    }
                }
            }
            return 1;
        }
    }
    return win32.CallNextHookEx(null, nCode, wParam, lParam);
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
