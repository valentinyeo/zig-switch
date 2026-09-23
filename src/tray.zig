const win32 = @import("win32.zig");

var hook_enabled: bool = false;
var hook_handle: ?win32.HHOOK = null;
var app_hinstance: ?win32.HINSTANCE = null;
var main_thread_id: win32.DWORD = 0;

var alt_held = false;
var shift_held = false;
var alttab_active = false; // true while Alt is held and overlay was opened via Alt+Tab

pub fn init(hInstance: ?win32.HINSTANCE) void {
    app_hinstance = hInstance;
    main_thread_id = win32.GetCurrentThreadId();

    // Enable Alt+Tab hook by default. ZigSwitch intentionally has no tray icon.
    enableHook();
}

pub fn deinit() void {
    disableHook();
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
    }
}

fn disableHook() void {
    if (hook_handle) |h| {
        _ = win32.UnhookWindowsHookEx(h);
        hook_handle = null;
    }
    hook_enabled = false;
}

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

        // Escape cancels Alt+Tab mode (safety valve)
        if (kb.vkCode == 0x1B and alttab_active) { // VK_ESCAPE
            alttab_active = false;
            alt_held = false;
        }

        // Any non-modifier key while alttab_active but NOT Alt+Tab → cancel alttab
        // This prevents the hook from getting stuck
        if (alttab_active and !alt_held) {
            alttab_active = false;
        }

        // Space while in Alt+Tab mode → switch to search
        if (kb.vkCode == win32.VK_SPACE_U32 and alttab_active) {
            if (wParam == win32.WM_KEYDOWN_HOOK or wParam == win32.WM_SYSKEYDOWN) {
                alttab_active = false;
                if (main_thread_id != 0) {
                    _ = win32.PostThreadMessageW(main_thread_id, win32.WM_APP_ALTTAB_SEARCH, 0, 0);
                }
            }
            return 1; // Consume so no space character is typed
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
