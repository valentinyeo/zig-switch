const std = @import("std");
const win32 = @import("win32.zig");
const window_enum = @import("window_enum.zig");
const search = @import("search.zig");
const config_mod = @import("config.zig");
const launcher = @import("launcher.zig");
const bookmarks = @import("bookmarks.zig");

// Modes
const Mode = enum { switcher, launcher, bookmarks_ };

// Mode colors (selection highlight)
const MODE_COLORS = [3]win32.COLORREF{
    win32.rgb(0x26, 0x4f, 0x78), // Switcher: blue
    win32.rgb(0x2d, 0x5a, 0x1e), // Launcher: green
    win32.rgb(0x5a, 0x2d, 0x6a), // Bookmarks: purple
};

// Mode border accent colors (top border)
const MODE_ACCENT = [3]win32.COLORREF{
    win32.rgb(0x3a, 0x7a, 0xc4), // Switcher: blue
    win32.rgb(0x4a, 0x9a, 0x2e), // Launcher: green
    win32.rgb(0x9a, 0x4a, 0xb4), // Bookmarks: purple
};


// Colors
const BG_COLOR = win32.rgb(0x1e, 0x1e, 0x1e);
const TEXT_COLOR = win32.rgb(0xff, 0xff, 0xff);
const DIM_COLOR = win32.rgb(0x88, 0x88, 0x88);
const SEARCH_BG = win32.rgb(0x2d, 0x2d, 0x2d);
const BORDER_COLOR = win32.rgb(0x3e, 0x3e, 0x3e);

// Layout
const PADDING = 8;
const ICON_SIZE = 16;
const ROW_HEIGHT = 24;
const SEARCH_HEIGHT = 32;

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

const CLASS_NAME = toWide("ZigSwitchOverlay");

pub fn init(hInstance: ?win32.HINSTANCE, c: config_mod.Config) void {
    cfg = c;

    const face = comptime toWide("Consolas");
    font = win32.CreateFontW(
        -16, 0, 0, 0, win32.FW_NORMAL, 0, 0, 0,
        win32.DEFAULT_CHARSET, win32.OUT_DEFAULT_PRECIS,
        win32.CLIP_DEFAULT_PRECIS, win32.CLEARTYPE_QUALITY,
        win32.DEFAULT_PITCH | win32.FF_DONTCARE, face,
    );

    const wc = win32.WNDCLASSEXW{
        .style = win32.CS_HREDRAW | win32.CS_VREDRAW,
        .lpfnWndProc = wndProc,
        .hInstance = hInstance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .lpszClassName = CLASS_NAME,
    };
    _ = win32.RegisterClassExW(&wc);

    const screen_w = win32.GetSystemMetrics(win32.SM_CXSCREEN);
    const screen_h = win32.GetSystemMetrics(win32.SM_CYSCREEN);
    const width: i32 = @divTrunc(screen_w * 3, 10);
    const max_rows: i32 = @intCast(cfg.max_visible_rows);
    const height: i32 = 2 + SEARCH_HEIGHT + PADDING + max_rows * ROW_HEIGHT + PADDING;
    const x = @divTrunc(screen_w - width, 2);
    const y = @divTrunc(screen_h - height, 3);

    overlay_hwnd = win32.CreateWindowExW(
        win32.WS_EX_TOPMOST | win32.WS_EX_TOOLWINDOW,
        CLASS_NAME,
        comptime toWide("ZigSwitch"),
        win32.WS_POPUP,
        x, y, width, height,
        null, null, hInstance, null,
    );

    // Pre-load launcher and bookmark data
    _ = launcher.getCount();
    _ = bookmarks.getCount();
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

        _ = win32.ShowWindow(hwnd, win32.SW_SHOW);
        _ = win32.SetForegroundWindow(hwnd);
        _ = win32.SetFocus(hwnd);
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

pub fn altTabActivate() void {
    if (visible and alttab_mode) {
        alttab_mode = false;
        if (filtered_count > 0) {
            const idx = filtered_indices[selected];
            const target = windows[idx].hwnd;
            hide();
            win32.keybd_event(win32.VK_MENU, 0, win32.KEYEVENTF_KEYUP, 0);
            _ = win32.SetForegroundWindow(target);
        } else {
            hide();
        }
    }
}

fn showOverlay(hwnd: win32.HWND) void {
    _ = win32.ShowWindow(hwnd, win32.SW_SHOW);
    _ = win32.SetForegroundWindow(hwnd);
    _ = win32.SetFocus(hwnd);
    visible = true;
    alttab_pending = false;
    _ = win32.InvalidateRect(hwnd, null, 0);
}

fn hide() void {
    const hwnd = overlay_hwnd orelse return;
    _ = win32.ShowWindow(hwnd, win32.SW_HIDE);
    visible = false;
    alttab_mode = false;
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

fn refilter() void {
    switch (current_mode) {
        .switcher => {
            const cluster_exe: ?[]const u16 = if (cluster_index == 0)
                null
            else
                clusters[cluster_index - 1].exe_name[0..clusters[cluster_index - 1].exe_name_len];

            filtered_count = search.applyFilter(
                &windows,
                window_count,
                search_buf[0..search_len],
                cluster_exe,
                &filtered_indices,
            );
        },
        .launcher => {
            filtered_count = 0;
            const items = launcher.getItems();
            for (items, 0..) |*item, i| {
                if (search_len == 0 or search.matchesSearch(item.name[0..item.name_len], search_buf[0..search_len])) {
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
                if (search_len == 0 or
                    search.matchesSearch(bm.name[0..bm.name_len], search_buf[0..search_len]) or
                    matchesSearchU8(bm.url[0..bm.url_len], search_buf[0..search_len]))
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

    switch (current_mode) {
        .switcher => {
            const target_hwnd = windows[idx].hwnd;
            _ = win32.SetForegroundWindow(target_hwnd);
            hide();
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
        win32.WM_KEYDOWN => {
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
    const list_top: i32 = 2 + SEARCH_HEIGHT + PADDING;

    if (mouse_y < list_top) return; // Clicked in search area

    const row_offset = @divTrunc(mouse_y - list_top, ROW_HEIGHT);
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

    const width = ps.rcPaint.right - ps.rcPaint.left;
    const height = ps.rcPaint.bottom - ps.rcPaint.top;
    if (width <= 0 or height <= 0) return;

    const mem_dc = win32.CreateCompatibleDC(hdc_screen) orelse return;
    const bmp = win32.CreateCompatibleBitmap(hdc_screen, width, height) orelse {
        _ = win32.DeleteDC(mem_dc);
        return;
    };
    _ = win32.SelectObject(mem_dc, @ptrCast(bmp));
    defer {
        _ = win32.BitBlt(hdc_screen, 0, 0, width, height, mem_dc, 0, 0, win32.SRCCOPY);
        _ = win32.DeleteObject(@ptrCast(bmp));
        _ = win32.DeleteDC(mem_dc);
    }

    if (font) |f| _ = win32.SelectObject(mem_dc, @ptrCast(f));
    _ = win32.SetBkMode(mem_dc, win32.TRANSPARENT);

    // Background
    const bg_brush = win32.CreateSolidBrush(BG_COLOR) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(bg_brush));
    var full_rect = win32.RECT{ .left = 0, .top = 0, .right = width, .bottom = height };
    _ = win32.FillRect(mem_dc, &full_rect, bg_brush);

    // Mode accent top border (2px colored line)
    const mode_idx = @intFromEnum(current_mode);
    const accent_brush = win32.CreateSolidBrush(MODE_ACCENT[mode_idx]) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(accent_brush));
    var accent_rect = win32.RECT{ .left = 0, .top = 0, .right = width, .bottom = 2 };
    _ = win32.FillRect(mem_dc, &accent_rect, accent_brush);

    const border_brush = win32.CreateSolidBrush(BORDER_COLOR) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(border_brush));

    // Search box (starts right after accent border)
    const search_y: i32 = 2;
    const search_brush = win32.CreateSolidBrush(SEARCH_BG) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(search_brush));
    var search_rect = win32.RECT{
        .left = PADDING,
        .top = search_y + 2,
        .right = width - PADDING,
        .bottom = search_y + SEARCH_HEIGHT,
    };
    _ = win32.FillRect(mem_dc, &search_rect, search_brush);

    // Search text
    _ = win32.SetTextColor(mem_dc, TEXT_COLOR);
    if (search_len > 0) {
        _ = win32.TextOutW(mem_dc, PADDING + 4, search_y + 6, &search_buf, @intCast(search_len));
    } else {
        _ = win32.SetTextColor(mem_dc, DIM_COLOR);
        const placeholder = switch (current_mode) {
            .switcher => comptime toWide("Type to search windows..."),
            .launcher => comptime toWide("Type to search programs..."),
            .bookmarks_ => comptime toWide("Type to search bookmarks..."),
        };
        const ph_len: i32 = switch (current_mode) {
            .switcher => 25,
            .launcher => 26,
            .bookmarks_ => 27,
        };
        _ = win32.TextOutW(mem_dc, PADDING + 4, search_y + 6, placeholder, ph_len);
    }

    // Right-side indicator
    {
        _ = win32.SetTextColor(mem_dc, DIM_COLOR);
        var label_buf: [64]u16 = [_]u16{0} ** 64;
        var label_len: usize = 0;

        if (current_mode == .switcher and cluster_index > 0) {
            const c = &clusters[cluster_index - 1];
            const name_len = @min(c.exe_name_len, 40);
            @memcpy(label_buf[0..name_len], c.exe_name[0..name_len]);
            label_len = name_len;
        }
        // Add count
        if (label_len > 0) {
            label_buf[label_len] = ' ';
            label_len += 1;
        }
        label_buf[label_len] = '(';
        label_len += 1;
        label_len += formatNum(filtered_count, label_buf[label_len..]);
        label_buf[label_len] = ')';
        label_len += 1;

        const label_x = width - PADDING - @as(i32, @intCast(label_len)) * 8;
        _ = win32.TextOutW(mem_dc, label_x, search_y + 6, &label_buf, @intCast(label_len));
    }

    // Separator
    var sep_rect = win32.RECT{
        .left = 0,
        .top = search_y + SEARCH_HEIGHT + 2,
        .right = width,
        .bottom = search_y + SEARCH_HEIGHT + 3,
    };
    _ = win32.FillRect(mem_dc, &sep_rect, border_brush);

    // Item list
    const list_top = search_y + SEARCH_HEIGHT + PADDING;
    const max_rows = cfg.max_visible_rows;

    if (filtered_count == 0) {
        _ = win32.SetTextColor(mem_dc, DIM_COLOR);
        const no_match = switch (current_mode) {
            .switcher => comptime toWide("No matching windows"),
            .launcher => comptime toWide("No matching programs"),
            .bookmarks_ => comptime toWide("No matching bookmarks"),
        };
        const nm_len: i32 = switch (current_mode) {
            .switcher => 19,
            .launcher => 20,
            .bookmarks_ => 21,
        };
        _ = win32.TextOutW(mem_dc, @divTrunc(width, 2) - 80, list_top + 20, no_match, nm_len);
    } else {
        const sel_brush = win32.CreateSolidBrush(MODE_COLORS[mode_idx]) orelse return;
        defer _ = win32.DeleteObject(@ptrCast(sel_brush));

        const end = @min(scroll_offset + max_rows, filtered_count);
        for (scroll_offset..end) |vi| {
            const row: i32 = @intCast(vi - scroll_offset);
            const y = list_top + row * ROW_HEIGHT;
            const data_idx = filtered_indices[vi];

            // Selection highlight
            if (vi == selected) {
                var sel_rect = win32.RECT{
                    .left = 1,
                    .top = y,
                    .right = width - 1,
                    .bottom = y + ROW_HEIGHT,
                };
                _ = win32.FillRect(mem_dc, &sel_rect, sel_brush);
            }

            const text_y = y + (ROW_HEIGHT - 16) / 2;

            switch (current_mode) {
                .switcher => paintWindowRow(mem_dc, data_idx, text_y, width),
                .launcher => paintLauncherRow(mem_dc, data_idx, text_y, width),
                .bookmarks_ => paintBookmarkRow(mem_dc, data_idx, text_y, width),
            }
        }
    }
}

fn paintWindowRow(mem_dc: win32.HDC, idx: usize, text_y: i32, width: win32.LONG) void {
    const w = &windows[idx];
    const max_chars: usize = @intCast(@divTrunc(width - PADDING * 2 - ICON_SIZE - 6, 8));

    if (w.icon) |icon| {
        _ = win32.DrawIconEx(mem_dc, PADDING, text_y, icon, ICON_SIZE, ICON_SIZE, 0, null, win32.DI_NORMAL);
    }

    const text_x = PADDING + ICON_SIZE + 6;
    _ = win32.SetTextColor(mem_dc, DIM_COLOR);
    const exe_show = @min(w.exe_name_len, max_chars);
    if (exe_show > 0) {
        _ = win32.TextOutW(mem_dc, text_x, text_y, &w.exe_name, @intCast(exe_show));
    }

    const used = exe_show + 3; // exe + separator
    if (used >= max_chars) return;

    const sep = comptime toWide(" \u{2014} ");
    const sep_x = text_x + @as(i32, @intCast(exe_show)) * 8;
    _ = win32.TextOutW(mem_dc, sep_x, text_y, sep, 3);

    const title_x = sep_x + 3 * 8;
    const title_max = max_chars - used;
    const title_show = @min(w.title_len, title_max);
    _ = win32.SetTextColor(mem_dc, TEXT_COLOR);
    if (title_show > 0) {
        _ = win32.TextOutW(mem_dc, title_x, text_y, &w.title, @intCast(title_show));
    }
}

fn paintLauncherRow(mem_dc: win32.HDC, idx: usize, text_y: i32, width: win32.LONG) void {
    const items = launcher.getItems();
    const item = &items[idx];
    const max_chars: usize = @intCast(@divTrunc(width - PADDING * 2 - ICON_SIZE - 6, 8));

    if (item.icon) |icon| {
        _ = win32.DrawIconEx(mem_dc, PADDING, text_y, icon, ICON_SIZE, ICON_SIZE, 0, null, win32.DI_NORMAL);
    }

    const text_x = PADDING + ICON_SIZE + 6;
    _ = win32.SetTextColor(mem_dc, TEXT_COLOR);
    const show_len = @min(item.name_len, max_chars);
    if (show_len > 0) {
        _ = win32.TextOutW(mem_dc, text_x, text_y, &item.name, @intCast(show_len));
    }
}

fn paintBookmarkRow(mem_dc: win32.HDC, idx: usize, text_y: i32, width: win32.LONG) void {
    const items = bookmarks.getItems();
    const bm = &items[idx];

    const text_x = PADDING + 4;

    // Bookmark name
    _ = win32.SetTextColor(mem_dc, TEXT_COLOR);
    if (bm.name_len > 0) {
        _ = win32.TextOutW(mem_dc, text_x, text_y, &bm.name, @intCast(bm.name_len));
    }

    // URL (dimmed, right side)
    _ = win32.SetTextColor(mem_dc, DIM_COLOR);
    if (bm.url_w_len > 0) {
        const max_url_chars: usize = @intCast(@divTrunc(width - 200, 8));
        const show_len = @min(bm.url_w_len, max_url_chars);
        const url_x = width - PADDING - @as(i32, @intCast(show_len)) * 8;
        _ = win32.TextOutW(mem_dc, url_x, text_y, &bm.url_w, @intCast(show_len));
    }
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
