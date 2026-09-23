const std = @import("std");
const win32 = @import("win32.zig");
const window_enum = @import("window_enum.zig");
const search = @import("search.zig");
const config_mod = @import("config.zig");
const launcher = @import("launcher.zig");
const bookmarks = @import("bookmarks.zig");
const tray = @import("tray.zig");
const ver = @import("version.zig");

// Modes
const Mode = enum { switcher, launcher, bookmarks_ };

// Mode accent colors used for subtle selection markers.
const MODE_ACCENT = [3]win32.COLORREF{
    win32.rgb(0x60, 0x9d, 0xd8), // Switcher: blue
    win32.rgb(0x6c, 0xb7, 0x6d), // Launcher: green
    win32.rgb(0xc0, 0x7a, 0xd9), // Bookmarks: purple
};

// Windows 11 dark surface colors.
const BG_COLOR = win32.rgb(0x20, 0x20, 0x20);
const SURFACE_COLOR = win32.rgb(0x2b, 0x2b, 0x2b);
const SURFACE_BORDER = win32.rgb(0x3a, 0x3a, 0x3a);
const SELECTION_COLOR = win32.rgb(0x33, 0x3a, 0x42);
const TEXT_COLOR = win32.rgb(0xf3, 0xf3, 0xf3);
const DIM_COLOR = win32.rgb(0xa0, 0xa0, 0xa0);
const SUBTLE_COLOR = win32.rgb(0x72, 0x72, 0x72);

// Layout
const PADDING = 12;
const ICON_SIZE = 16;
const ROW_HEIGHT = 32;
const SEARCH_HEIGHT = 38;
const LIST_GAP = 8;
const CORNER_RADIUS = 10;
const SEARCH_RADIUS = 8;
const ROW_RADIUS = 7;
const VERSION_FOOTER_HEIGHT = 18;
const LIST_TOP = PADDING + SEARCH_HEIGHT + LIST_GAP;

// Compact Windows 11 shell-style typography.
const UI_FONT_SIZE = 12;
const VERSION_FONT_SIZE = 10;

// State
var overlay_hwnd: ?win32.HWND = null;
var visible = false;
var cfg: config_mod.Config = .{};
var current_mode: Mode = .switcher;
var alttab_mode = false; // true = opened via Alt+Tab (release Alt to activate)

// Switcher state
var windows: [window_enum.MAX_WINDOWS]window_enum.WindowInfo = undefined;
var window_count: usize = 0;

// Generic filtered list (indices into current mode's data)
var filtered_indices: [512]usize = undefined;
var filtered_count: usize = 0;

var clusters: [search.MAX_CLUSTERS]search.Cluster = undefined;
var cluster_count: usize = 0;
var cluster_index: usize = 0; // 0 = All

var selected: usize = 0;
var scroll_offset: usize = 0;

var search_buf: [128]u16 = [_]u16{0} ** 128;
var search_len: usize = 0;

var font: ?win32.HFONT = null;
var version_font: ?win32.HFONT = null;
var overlay_width: i32 = 0;

const CLASS_NAME = toWide("ZigSwitchOverlay");

pub fn init(hInstance: ?win32.HINSTANCE, c: config_mod.Config) void {
    cfg = c;

    const face = comptime toWide("Segoe UI Variable");
    font = win32.CreateFontW(
        -UI_FONT_SIZE,
        0,
        0,
        0,
        win32.FW_NORMAL,
        0,
        0,
        0,
        win32.DEFAULT_CHARSET,
        win32.OUT_DEFAULT_PRECIS,
        win32.CLIP_DEFAULT_PRECIS,
        win32.CLEARTYPE_QUALITY,
        win32.DEFAULT_PITCH | win32.FF_DONTCARE,
        face,
    );
    version_font = win32.CreateFontW(
        -VERSION_FONT_SIZE,
        0,
        0,
        0,
        win32.FW_NORMAL,
        0,
        0,
        0,
        win32.DEFAULT_CHARSET,
        win32.OUT_DEFAULT_PRECIS,
        win32.CLIP_DEFAULT_PRECIS,
        win32.CLEARTYPE_QUALITY,
        win32.DEFAULT_PITCH | win32.FF_DONTCARE,
        face,
    );

    const wc = win32.WNDCLASSEXW{
        .style = win32.CS_HREDRAW | win32.CS_VREDRAW | win32.CS_DROPSHADOW,
        .lpfnWndProc = wndProc,
        .hInstance = hInstance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .lpszClassName = CLASS_NAME,
    };
    _ = win32.RegisterClassExW(&wc);

    const screen_w = win32.GetSystemMetrics(win32.SM_CXSCREEN);
    const screen_h = win32.GetSystemMetrics(win32.SM_CYSCREEN);
    overlay_width = clampI32(@divTrunc(screen_w, 3), 560, 720);
    if (overlay_width > screen_w - 80) overlay_width = screen_w - 80;
    const width = overlay_width;
    const height = desiredOverlayHeight();
    const x = @divTrunc(screen_w - width, 2);
    const y = @divTrunc(screen_h - height, 3);

    overlay_hwnd = win32.CreateWindowExW(
        win32.WS_EX_TOPMOST | win32.WS_EX_TOOLWINDOW,
        CLASS_NAME,
        comptime toWide("ZigSwitch"),
        win32.WS_POPUP,
        x,
        y,
        width,
        height,
        null,
        null,
        hInstance,
        null,
    );

    if (overlay_hwnd) |hwnd| {
        applyRoundedCorners(hwnd, width, height);
    }

    // Pre-load launcher and bookmark data
    _ = launcher.getCount();
    _ = bookmarks.getCount();
}

pub fn deinit() void {
    window_enum.releaseOwnedIcons(&windows, window_count);
    window_count = 0;
    launcher.deinit();
    if (font) |f| {
        _ = win32.DeleteObject(@ptrCast(f));
        font = null;
    }
    if (version_font) |vf| {
        _ = win32.DeleteObject(@ptrCast(vf));
        version_font = null;
    }
}

fn clampI32(value: i32, min_value: i32, max_value: i32) i32 {
    if (value < min_value) return min_value;
    if (value > max_value) return max_value;
    return value;
}

fn visibleRowCount() i32 {
    const max_rows: i32 = @intCast(cfg.max_visible_rows);
    if (filtered_count == 0) return 1;
    const count: i32 = @intCast(@min(filtered_count, cfg.max_visible_rows));
    return @max(1, @min(count, max_rows));
}

fn desiredOverlayHeight() i32 {
    return LIST_TOP + visibleRowCount() * ROW_HEIGHT + PADDING + VERSION_FOOTER_HEIGHT;
}

fn updateOverlayLayout(hwnd: win32.HWND) void {
    const screen_w = win32.GetSystemMetrics(win32.SM_CXSCREEN);
    const screen_h = win32.GetSystemMetrics(win32.SM_CYSCREEN);
    if (overlay_width == 0) {
        overlay_width = clampI32(@divTrunc(screen_w, 3), 560, 720);
    }
    if (overlay_width > screen_w - 80) overlay_width = screen_w - 80;

    const width = overlay_width;
    const height = desiredOverlayHeight();
    const x = @divTrunc(screen_w - width, 2);
    const y = @divTrunc(screen_h - height, 3);
    _ = win32.SetWindowPos(hwnd, null, x, y, width, height, win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
    applyRoundedCorners(hwnd, width, height);
}

fn applyRoundedCorners(hwnd: win32.HWND, width: i32, height: i32) void {
    var corner_preference: win32.DWORD = win32.DWMWCP_ROUND;
    const hr = win32.DwmSetWindowAttribute(
        hwnd,
        win32.DWMWA_WINDOW_CORNER_PREFERENCE,
        @ptrCast(&corner_preference),
        @sizeOf(win32.DWORD),
    );
    if (hr == 0) return;

    // Fallback for systems where DWM corner preference is unavailable.
    const diameter = CORNER_RADIUS * 2;
    const region = win32.CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter, diameter) orelse return;
    if (win32.SetWindowRgn(hwnd, region, 1) == 0) {
        _ = win32.DeleteObject(@ptrCast(region));
    }
}

fn focusOverlay(hwnd: win32.HWND) void {
    updateOverlayLayout(hwnd);
    _ = win32.ShowWindow(hwnd, win32.SW_SHOW);

    const current_thread = win32.GetCurrentThreadId();
    var attached_thread: win32.DWORD = 0;

    if (win32.GetForegroundWindow()) |foreground| {
        var foreground_pid: win32.DWORD = 0;
        const foreground_thread = win32.GetWindowThreadProcessId(foreground, &foreground_pid);
        if (foreground_thread != 0 and foreground_thread != current_thread) {
            if (win32.AttachThreadInput(current_thread, foreground_thread, 1) != 0) {
                attached_thread = foreground_thread;
            }
        }
    }
    defer {
        if (attached_thread != 0) {
            _ = win32.AttachThreadInput(current_thread, attached_thread, 0);
        }
    }

    _ = win32.BringWindowToTop(hwnd);
    _ = win32.SetForegroundWindow(hwnd);
    _ = win32.SetActiveWindow(hwnd);
    _ = win32.SetFocus(hwnd);
}

fn activateWindow(target: win32.HWND) void {
    const current_thread = win32.GetCurrentThreadId();
    var target_pid: win32.DWORD = 0;
    const target_thread = win32.GetWindowThreadProcessId(target, &target_pid);
    var foreground_thread: win32.DWORD = 0;

    if (win32.GetForegroundWindow()) |foreground| {
        var foreground_pid: win32.DWORD = 0;
        foreground_thread = win32.GetWindowThreadProcessId(foreground, &foreground_pid);
    }

    var attached_target = false;
    var attached_foreground = false;
    if (target_thread != 0 and target_thread != current_thread) {
        attached_target = win32.AttachThreadInput(current_thread, target_thread, 1) != 0;
    }
    if (foreground_thread != 0 and foreground_thread != current_thread and foreground_thread != target_thread) {
        attached_foreground = win32.AttachThreadInput(current_thread, foreground_thread, 1) != 0;
    }
    defer {
        if (attached_foreground) {
            _ = win32.AttachThreadInput(current_thread, foreground_thread, 0);
        }
        if (attached_target) {
            _ = win32.AttachThreadInput(current_thread, target_thread, 0);
        }
    }

    if (win32.IsIconic(target) != 0) {
        _ = win32.ShowWindow(target, win32.SW_RESTORE);
    } else {
        _ = win32.ShowWindow(target, win32.SW_SHOW);
    }
    _ = win32.BringWindowToTop(target);
    _ = win32.SetForegroundWindow(target);
    _ = win32.SetActiveWindow(target);
}

pub fn toggle() void {
    toggleWithMode(.switcher);
}

pub fn toggleLauncher() void {
    toggleWithMode(.launcher);
}

fn toggleWithMode(mode: Mode) void {
    const hwnd = overlay_hwnd orelse return;

    if (visible) {
        hide();
    } else {
        current_mode = mode;
        refreshCurrentMode();

        focusOverlay(hwnd);
        visible = true;
        _ = win32.InvalidateRect(hwnd, null, 0);
    }
}

pub fn isVisible() bool {
    return visible;
}

pub fn altTabShow() void {
    const hwnd = overlay_hwnd orelse return;
    if (!visible) {
        alttab_mode = true;
        current_mode = .switcher;
        refreshCurrentMode();
        if (filtered_count > 1) selected = 1;
        showOverlay(hwnd);
    }
}

pub fn altTabPrev() void {
    const hwnd = overlay_hwnd orelse return;
    if (!visible) {
        alttab_mode = true;
        current_mode = .switcher;
        refreshCurrentMode();
        if (filtered_count > 1) selected = filtered_count - 1;
        showOverlay(hwnd);
    } else if (filtered_count > 0) {
        selected = if (selected == 0) filtered_count - 1 else selected - 1;
        if (selected < scroll_offset) scroll_offset = selected;
        if (selected >= scroll_offset + cfg.max_visible_rows) {
            scroll_offset = selected - cfg.max_visible_rows + 1;
        }
        _ = win32.InvalidateRect(hwnd, null, 0);
    }
}

pub fn altTabNext() void {
    const hwnd = overlay_hwnd orelse return;
    if (visible and filtered_count > 0) {
        selected = if (selected >= filtered_count - 1) 0 else selected + 1;
        if (selected < scroll_offset) scroll_offset = selected;
        if (selected >= scroll_offset + cfg.max_visible_rows) {
            scroll_offset = selected - cfg.max_visible_rows + 1;
        }
        _ = win32.InvalidateRect(hwnd, null, 0);
    }
}

pub fn altTabToSearch() void {
    const hwnd = overlay_hwnd orelse return;
    if (!visible) return;

    if (alttab_mode) {
        // Switch from Alt+Tab cycling to normal search input.
        alttab_mode = false;
        // Release Alt so typing works. Do not swallow the real Alt-up event;
        // Windows needs to see it or the modifier can get logically stuck.
        win32.keybd_event(win32.VK_MENU, 0, win32.KEYEVENTF_KEYUP, 0);
        search_len = 0;
        @memset(&search_buf, 0);
        selected = 0;
        refilter();
    }

    // Alt+Tab is driven from a global hook, so the previous foreground app can
    // still own keyboard focus. Explicitly claim focus now.
    focusOverlay(hwnd);
    _ = win32.InvalidateRect(hwnd, null, 0);
}

pub fn altTabActivate() void {
    if (visible and alttab_mode) {
        alttab_mode = false;
        if (filtered_count > 0) {
            const idx = filtered_indices[selected];
            const target = windows[idx].hwnd;
            hide();
            activateWindow(target);
            // The real Alt-up is consumed by the hook to avoid menu-bar focus.
            // Send a synthetic Alt-up only after the target is foreground so the
            // previous window does not steal focus back.
            win32.keybd_event(win32.VK_MENU, 0, win32.KEYEVENTF_KEYUP, 0);
        } else {
            hide();
        }
    }
}

fn showOverlay(hwnd: win32.HWND) void {
    focusOverlay(hwnd);
    visible = true;
    _ = win32.InvalidateRect(hwnd, null, 0);
}

fn hide() void {
    const hwnd = overlay_hwnd orelse return;
    _ = win32.ShowWindow(hwnd, win32.SW_HIDE);
    visible = false;
    alttab_mode = false;
    tray.cancelAltTab();
}

fn refreshCurrentMode() void {
    search_len = 0;
    @memset(&search_buf, 0);
    selected = 0;
    scroll_offset = 0;
    cluster_index = 0;

    switch (current_mode) {
        .switcher => {
            window_enum.enumerateWindows(&windows, &window_count, overlay_hwnd);
            cluster_count = search.computeClusters(&windows, window_count, cfg.cluster_threshold, &clusters);
        },
        .launcher => {
            cluster_count = 0;
        },
        .bookmarks_ => {
            cluster_count = 0;
        },
    }
    refilter();
}

fn getEffectiveMode() Mode {
    // "b:" prefix → bookmarks, "s:" prefix → start menu launcher
    if (search_len >= 2 and search_buf[1] == ':') {
        if (search_buf[0] == 'b' or search_buf[0] == 'B') return .bookmarks_;
        if (search_buf[0] == 's' or search_buf[0] == 'S') return .launcher;
    }
    return current_mode;
}

fn getSearchQuery() []const u16 {
    // Strip "b:" or "s:" prefix from search query
    if (search_len >= 2 and search_buf[1] == ':' and
        (search_buf[0] == 'b' or search_buf[0] == 'B' or
            search_buf[0] == 's' or search_buf[0] == 'S'))
    {
        return search_buf[2..search_len];
    }
    return search_buf[0..search_len];
}

fn refilter() void {
    const effective_mode = getEffectiveMode();
    const query = getSearchQuery();

    switch (effective_mode) {
        .switcher => {
            const cluster_exe: ?[]const u16 = if (cluster_index == 0)
                null
            else
                clusters[cluster_index - 1].exe_name[0..clusters[cluster_index - 1].exe_name_len];

            filtered_count = search.applyFilter(
                &windows,
                window_count,
                query,
                cluster_exe,
                &filtered_indices,
            );
        },
        .launcher => {
            filtered_count = 0;
            const items = launcher.getItems();
            for (items, 0..) |*item, i| {
                if (query.len == 0 or search.matchesSearch(item.name[0..item.name_len], query)) {
                    if (filtered_count < filtered_indices.len) {
                        filtered_indices[filtered_count] = i;
                        filtered_count += 1;
                    }
                }
            }
        },
        .bookmarks_ => {
            filtered_count = 0;
            const items = bookmarks.getItems();
            for (items, 0..) |*bm, i| {
                if (query.len == 0 or
                    search.matchesSearch(bm.name[0..bm.name_len], query) or
                    matchesSearchU8(bm.url[0..bm.url_len], query))
                {
                    if (filtered_count < filtered_indices.len) {
                        filtered_indices[filtered_count] = i;
                        filtered_count += 1;
                    }
                }
            }
        },
    }

    if (selected >= filtered_count and filtered_count > 0) {
        selected = filtered_count - 1;
    }
    if (filtered_count == 0) {
        selected = 0;
    }
    scroll_offset = 0;

    if (visible) {
        if (overlay_hwnd) |hwnd| {
            updateOverlayLayout(hwnd);
        }
    }
}

fn matchesSearchU8(haystack: []const u8, query: []const u16) bool {
    if (query.len == 0) return true;
    if (haystack.len < query.len) return false;
    for (0..haystack.len - query.len + 1) |i| {
        var matched = true;
        for (0..query.len) |j| {
            const h: u16 = if (haystack[i + j] >= 'A' and haystack[i + j] <= 'Z')
                haystack[i + j] + 32
            else
                haystack[i + j];
            const q: u16 = if (query[j] >= 'A' and query[j] <= 'Z') query[j] + 32 else query[j];
            if (h != q) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

fn closeSelected(hwnd: win32.HWND) void {
    if (current_mode != .switcher) return;
    if (filtered_count == 0) return;

    const idx = filtered_indices[selected];
    const target_hwnd = windows[idx].hwnd;
    win32.postClose(target_hwnd);

    window_count -= 1;
    if (idx < window_count) {
        var i = idx;
        while (i < window_count) : (i += 1) {
            windows[i] = windows[i + 1];
        }
    }

    cluster_count = search.computeClusters(&windows, window_count, cfg.cluster_threshold, &clusters);
    if (cluster_index > cluster_count) cluster_index = 0;
    refilter();

    if (selected >= filtered_count and filtered_count > 0) {
        selected = filtered_count - 1;
    }
    _ = win32.InvalidateRect(hwnd, null, 0);
}

fn activateSelected() void {
    if (filtered_count == 0) return;

    const idx = filtered_indices[selected];

    switch (getEffectiveMode()) {
        .switcher => {
            const target_hwnd = windows[idx].hwnd;
            hide();
            activateWindow(target_hwnd);
        },
        .launcher => {
            const items = launcher.getItems();
            hide();
            launcher.launch(&items[idx]);
        },
        .bookmarks_ => {
            const items = bookmarks.getItems();
            hide();
            bookmarks.openBookmark(&items[idx]);
        },
    }
}

pub fn getHwnd() ?win32.HWND {
    return overlay_hwnd;
}

fn wndProc(hwnd: win32.HWND, msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    switch (msg) {
        win32.WM_PAINT => {
            paint(hwnd);
            return 0;
        },
        win32.WM_ERASEBKGND => return 1,
        win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN_MSG => {
            handleKeyDown(hwnd, wParam);
            return 0;
        },
        win32.WM_CHAR => {
            handleChar(hwnd, wParam);
            return 0;
        },
        win32.WM_LBUTTONDOWN => {
            handleClick(hwnd, lParam);
            return 0;
        },
        win32.WM_ACTIVATE => {
            if (wParam == win32.WA_INACTIVE and visible) hide();
            return 0;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        else => return win32.DefWindowProcW(hwnd, msg, wParam, lParam),
    }
}

fn handleClick(hwnd: win32.HWND, lParam: win32.LPARAM) void {
    const mouse_y: i32 = @intCast((lParam >> 16) & 0xFFFF);

    if (mouse_y < LIST_TOP) return; // Clicked in search area

    const row_offset = @divTrunc(mouse_y - LIST_TOP, ROW_HEIGHT);
    if (row_offset < 0 or row_offset >= visibleRowCount()) return;

    const clicked_idx = scroll_offset + @as(usize, @intCast(row_offset));
    if (clicked_idx < filtered_count) {
        selected = clicked_idx;
        _ = win32.InvalidateRect(hwnd, null, 0);
        activateSelected();
    }
}

fn handleKeyDown(hwnd: win32.HWND, key: win32.WPARAM) void {
    switch (key) {
        win32.VK_ESCAPE => hide(),
        win32.VK_RETURN => {
            activateSelected();
        },
        win32.VK_UP => {
            if (selected > 0) {
                selected -= 1;
                if (selected < scroll_offset) scroll_offset = selected;
                _ = win32.InvalidateRect(hwnd, null, 0);
            }
        },
        win32.VK_DOWN => {
            if (filtered_count > 0 and selected < filtered_count - 1) {
                selected += 1;
                if (selected >= scroll_offset + cfg.max_visible_rows) {
                    scroll_offset = selected - cfg.max_visible_rows + 1;
                }
                _ = win32.InvalidateRect(hwnd, null, 0);
            }
        },
        win32.VK_TAB => {
            // Tab = next item, Shift+Tab = previous item
            const shift_down = (win32.GetKeyState(win32.VK_SHIFT) < 0);
            if (filtered_count > 0) {
                if (shift_down) {
                    selected = if (selected == 0) filtered_count - 1 else selected - 1;
                } else {
                    selected = if (selected >= filtered_count - 1) 0 else selected + 1;
                }
                if (selected < scroll_offset) scroll_offset = selected;
                if (selected >= scroll_offset + cfg.max_visible_rows) {
                    scroll_offset = selected - cfg.max_visible_rows + 1;
                }
            }
            _ = win32.InvalidateRect(hwnd, null, 0);
        },
        0x51 => { // VK_Q
            const ctrl_down = (win32.GetKeyState(win32.VK_CONTROL) < 0);
            if (ctrl_down) {
                closeSelected(hwnd);
                return; // Don't let 'q' go to WM_CHAR
            }
        },
        win32.VK_SPACE => {
            if (alttab_mode) {
                // Space in Alt+Tab mode → switch to search mode
                alttab_mode = false;
                tray.cancelAltTab(); // Tell hook Alt release shouldn't activate
                focusOverlay(hwnd);
                win32.keybd_event(win32.VK_MENU, 0, win32.KEYEVENTF_KEYUP, 0);
                search_len = 0;
                @memset(&search_buf, 0);
                selected = 0;
                refilter();
                _ = win32.InvalidateRect(hwnd, null, 0);
                return; // Don't let space go to WM_CHAR
            }
            const shift_down = (win32.GetKeyState(win32.VK_SHIFT) < 0);
            if (shift_down) {
                current_mode = switch (current_mode) {
                    .switcher => .launcher,
                    .launcher => .bookmarks_,
                    .bookmarks_ => .switcher,
                };
                refreshCurrentMode();
                _ = win32.InvalidateRect(hwnd, null, 0);
            }
            // Regular space falls through to WM_CHAR
        },
        win32.VK_BACK => {
            if (search_len > 0) {
                search_len -= 1;
                search_buf[search_len] = 0;
                selected = 0;
                refilter();
                _ = win32.InvalidateRect(hwnd, null, 0);
            }
        },
        else => {},
    }
}

fn handleChar(hwnd: win32.HWND, char: win32.WPARAM) void {
    if (char < 0x20) return; // Control characters (includes Ctrl+Q = 0x11)
    if (char == 0x7F) return;
    // Shift+Space = mode switch, don't type a space
    if (char == 0x20 and win32.GetKeyState(win32.VK_SHIFT) < 0) return;

    if (search_len < search_buf.len - 1) {
        search_buf[search_len] = @intCast(char);
        search_len += 1;
        selected = 0;
        refilter();
        _ = win32.InvalidateRect(hwnd, null, 0);
    }
}

fn paint(hwnd: win32.HWND) void {
    var ps: win32.PAINTSTRUCT = .{};
    const hdc_screen = win32.BeginPaint(hwnd, &ps) orelse return;
    defer _ = win32.EndPaint(hwnd, &ps);

    var client: win32.RECT = .{};
    if (win32.GetClientRect(hwnd, &client) == 0) return;
    const width = client.right - client.left;
    const height = client.bottom - client.top;
    if (width <= 0 or height <= 0) return;

    const mem_dc = win32.CreateCompatibleDC(hdc_screen) orelse return;
    const bmp = win32.CreateCompatibleBitmap(hdc_screen, width, height) orelse {
        _ = win32.DeleteDC(mem_dc);
        return;
    };
    const old_bmp = win32.SelectObject(mem_dc, @ptrCast(bmp));
    defer {
        _ = win32.BitBlt(hdc_screen, 0, 0, width, height, mem_dc, 0, 0, win32.SRCCOPY);
        if (old_bmp) |old| {
            _ = win32.SelectObject(mem_dc, @ptrCast(old));
        }
        _ = win32.DeleteObject(@ptrCast(bmp));
        _ = win32.DeleteDC(mem_dc);
    }

    if (font) |f| _ = win32.SelectObject(mem_dc, @ptrCast(f));
    _ = win32.SetBkMode(mem_dc, win32.TRANSPARENT);

    fillRect(mem_dc, 0, 0, width, height, BG_COLOR);

    // Rounded search/input surface.
    const search_top = PADDING;
    const search_bottom = search_top + SEARCH_HEIGHT;
    drawRoundedRect(mem_dc, PADDING, search_top, width - PADDING, search_bottom, SEARCH_RADIUS, SURFACE_BORDER);
    drawRoundedRect(mem_dc, PADDING + 1, search_top + 1, width - PADDING - 1, search_bottom - 1, SEARCH_RADIUS - 1, SURFACE_COLOR);

    const count_width: i32 = 52;
    const search_text_rect = win32.RECT{
        .left = PADDING + 12,
        .top = search_top,
        .right = width - PADDING - count_width - 8,
        .bottom = search_bottom,
    };
    if (search_len > 0) {
        drawTextLine(mem_dc, search_text_rect, &search_buf, search_len, TEXT_COLOR, win32.DT_LEFT);
    } else {
        const placeholder = comptime toWide("Search windows, apps, bookmarks...");
        drawTextLine(mem_dc, search_text_rect, placeholder, ("Search windows, apps, bookmarks...").len, DIM_COLOR, win32.DT_LEFT);
    }

    var count_buf: [64]u16 = [_]u16{0} ** 64;
    const count_len = formatCountLabel(&count_buf);
    const count_rect = win32.RECT{
        .left = width - PADDING - count_width,
        .top = search_top,
        .right = width - PADDING - 12,
        .bottom = search_bottom,
    };
    drawTextLine(mem_dc, count_rect, &count_buf, count_len, SUBTLE_COLOR, win32.DT_RIGHT);

    const mode_idx = @intFromEnum(getEffectiveMode());
    const rows_to_paint = visibleRowCount();

    if (filtered_count == 0) {
        const eff = getEffectiveMode();
        const no_match = switch (eff) {
            .switcher => comptime toWide("No matching windows"),
            .launcher => comptime toWide("No matching programs"),
            .bookmarks_ => comptime toWide("No matching bookmarks"),
        };
        const nm_len: usize = switch (eff) {
            .switcher => 19,
            .launcher => 20,
            .bookmarks_ => 21,
        };
        const empty_rect = win32.RECT{
            .left = PADDING + 14,
            .top = LIST_TOP,
            .right = width - PADDING - 14,
            .bottom = LIST_TOP + ROW_HEIGHT,
        };
        drawTextLine(mem_dc, empty_rect, no_match, nm_len, DIM_COLOR, win32.DT_LEFT);
    } else {
        const end = @min(scroll_offset + @as(usize, @intCast(rows_to_paint)), filtered_count);
        for (scroll_offset..end) |vi| {
            const row: i32 = @intCast(vi - scroll_offset);
            const y = LIST_TOP + row * ROW_HEIGHT;
            const data_idx = filtered_indices[vi];

            if (vi == selected) {
                drawRoundedRect(mem_dc, PADDING, y + 2, width - PADDING, y + ROW_HEIGHT - 2, ROW_RADIUS, SELECTION_COLOR);
                drawRoundedRect(mem_dc, PADDING + 5, y + 9, PADDING + 8, y + ROW_HEIGHT - 9, 2, MODE_ACCENT[mode_idx]);
            }

            switch (getEffectiveMode()) {
                .switcher => paintWindowRow(mem_dc, data_idx, y, width),
                .launcher => paintLauncherRow(mem_dc, data_idx, y, width),
                .bookmarks_ => paintBookmarkRow(mem_dc, data_idx, y, width),
            }
        }
    }

    if (version_font) |vf| {
        _ = win32.SelectObject(mem_dc, @ptrCast(vf));
    }
    const version_label = comptime toWide("v" ++ ver.version);
    const version_len: usize = ("v" ++ ver.version).len;
    const version_rect = win32.RECT{
        .left = PADDING,
        .top = height - VERSION_FOOTER_HEIGHT,
        .right = width - PADDING,
        .bottom = height - 4,
    };
    drawTextLine(mem_dc, version_rect, version_label, version_len, SUBTLE_COLOR, win32.DT_RIGHT);

    if (font) |f| {
        _ = win32.SelectObject(mem_dc, @ptrCast(f));
    }
}

fn fillRect(mem_dc: win32.HDC, left: i32, top: i32, right: i32, bottom: i32, color: win32.COLORREF) void {
    if (right <= left or bottom <= top) return;
    const brush = win32.CreateSolidBrush(color) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(brush));
    var rect = win32.RECT{ .left = left, .top = top, .right = right, .bottom = bottom };
    _ = win32.FillRect(mem_dc, &rect, brush);
}

fn drawRoundedRect(mem_dc: win32.HDC, left: i32, top: i32, right: i32, bottom: i32, radius: i32, color: win32.COLORREF) void {
    if (right <= left or bottom <= top) return;
    const brush = win32.CreateSolidBrush(color) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(brush));

    const diameter = @max(1, radius * 2);
    const region = win32.CreateRoundRectRgn(left, top, right, bottom, diameter, diameter) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(region));

    _ = win32.FillRgn(mem_dc, region, brush);
}

fn drawTextLine(mem_dc: win32.HDC, rect: win32.RECT, text: [*]const u16, len: usize, color: win32.COLORREF, text_align: win32.UINT) void {
    if (len == 0) return;
    var r = rect;
    _ = win32.SetTextColor(mem_dc, color);
    _ = win32.DrawTextW(
        mem_dc,
        text,
        @intCast(len),
        &r,
        text_align | win32.DT_SINGLELINE | win32.DT_VCENTER | win32.DT_NOPREFIX | win32.DT_END_ELLIPSIS,
    );
}

fn formatCountLabel(buf: *[64]u16) usize {
    var len: usize = 0;
    if (current_mode == .switcher and cluster_index > 0) {
        const c = &clusters[cluster_index - 1];
        const name_len = @min(c.exe_name_len, 32);
        @memcpy(buf[0..name_len], c.exe_name[0..name_len]);
        len = name_len;
        buf[len] = ' ';
        len += 1;
    }
    len += formatNum(filtered_count, buf[len..]);
    return len;
}

fn paintWindowRow(mem_dc: win32.HDC, idx: usize, row_y: i32, width: win32.LONG) void {
    const w = &windows[idx];
    const icon_x = PADDING + 14;
    const icon_y = row_y + @divTrunc(ROW_HEIGHT - ICON_SIZE, 2);

    if (w.icon) |icon| {
        _ = win32.DrawIconEx(mem_dc, icon_x, icon_y, icon, ICON_SIZE, ICON_SIZE, 0, null, win32.DI_NORMAL);
    }

    const text_x = icon_x + ICON_SIZE + 12;
    const meta_width: i32 = 112;
    const title_rect = win32.RECT{
        .left = text_x,
        .top = row_y,
        .right = width - PADDING - meta_width - 12,
        .bottom = row_y + ROW_HEIGHT,
    };
    const app_rect = win32.RECT{
        .left = width - PADDING - meta_width,
        .top = row_y,
        .right = width - PADDING - 12,
        .bottom = row_y + ROW_HEIGHT,
    };

    drawTextLine(mem_dc, title_rect, &w.title, w.title_len, TEXT_COLOR, win32.DT_LEFT);
    drawTextLine(mem_dc, app_rect, &w.exe_name, w.exe_name_len, DIM_COLOR, win32.DT_RIGHT);
}

fn paintLauncherRow(mem_dc: win32.HDC, idx: usize, row_y: i32, width: win32.LONG) void {
    const items = launcher.getItems();
    const item = &items[idx];
    const icon_x = PADDING + 14;
    const icon_y = row_y + @divTrunc(ROW_HEIGHT - ICON_SIZE, 2);

    if (item.icon) |icon| {
        _ = win32.DrawIconEx(mem_dc, icon_x, icon_y, icon, ICON_SIZE, ICON_SIZE, 0, null, win32.DI_NORMAL);
    }

    const name_rect = win32.RECT{
        .left = icon_x + ICON_SIZE + 12,
        .top = row_y,
        .right = width - PADDING - 12,
        .bottom = row_y + ROW_HEIGHT,
    };
    drawTextLine(mem_dc, name_rect, &item.name, item.name_len, TEXT_COLOR, win32.DT_LEFT);
}

fn paintBookmarkRow(mem_dc: win32.HDC, idx: usize, row_y: i32, width: win32.LONG) void {
    const items = bookmarks.getItems();
    const bm = &items[idx];

    const url_width: i32 = 220;
    const name_rect = win32.RECT{
        .left = PADDING + 14,
        .top = row_y,
        .right = width - PADDING - url_width - 12,
        .bottom = row_y + ROW_HEIGHT,
    };
    const url_rect = win32.RECT{
        .left = width - PADDING - url_width,
        .top = row_y,
        .right = width - PADDING - 12,
        .bottom = row_y + ROW_HEIGHT,
    };

    drawTextLine(mem_dc, name_rect, &bm.name, bm.name_len, TEXT_COLOR, win32.DT_LEFT);
    drawTextLine(mem_dc, url_rect, &bm.url_w, bm.url_w_len, DIM_COLOR, win32.DT_RIGHT);
}

fn formatNum(n: usize, buf: []u16) usize {
    if (n == 0) {
        buf[0] = '0';
        return 1;
    }
    var val = n;
    var digits: [20]u16 = undefined;
    var len: usize = 0;
    while (val > 0) {
        digits[len] = @intCast('0' + val % 10);
        val /= 10;
        len += 1;
    }
    for (0..len) |i| {
        buf[i] = digits[len - 1 - i];
    }
    return len;
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
