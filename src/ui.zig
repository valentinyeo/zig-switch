const std = @import("std");
const win32 = @import("win32.zig");
const window_enum = @import("window_enum.zig");
const search = @import("search.zig");
const config_mod = @import("config.zig");

// Colors
const BG_COLOR = win32.rgb(0x1e, 0x1e, 0x1e);
const TEXT_COLOR = win32.rgb(0xff, 0xff, 0xff);
const DIM_COLOR = win32.rgb(0x88, 0x88, 0x88);
const SEL_COLOR = win32.rgb(0x26, 0x4f, 0x78);
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

var windows: [window_enum.MAX_WINDOWS]window_enum.WindowInfo = undefined;
var window_count: usize = 0;

var filtered_indices: [window_enum.MAX_WINDOWS]usize = undefined;
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

    // Create font
    const face = comptime toWide("Consolas");
    font = win32.CreateFontW(
        -16, 0, 0, 0, win32.FW_NORMAL, 0, 0, 0,
        win32.DEFAULT_CHARSET, win32.OUT_DEFAULT_PRECIS,
        win32.CLIP_DEFAULT_PRECIS, win32.CLEARTYPE_QUALITY,
        win32.DEFAULT_PITCH | win32.FF_DONTCARE, face,
    );

    // Register class
    const wc = win32.WNDCLASSEXW{
        .style = win32.CS_HREDRAW | win32.CS_VREDRAW,
        .lpfnWndProc = wndProc,
        .hInstance = hInstance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .lpszClassName = CLASS_NAME,
    };

    _ = win32.RegisterClassExW(&wc);

    // Calculate size
    const screen_w = win32.GetSystemMetrics(win32.SM_CXSCREEN);
    const screen_h = win32.GetSystemMetrics(win32.SM_CYSCREEN);
    const width: i32 = @divTrunc(screen_w * 6, 10);
    const max_rows: i32 = @intCast(cfg.max_visible_rows);
    const height: i32 = SEARCH_HEIGHT + PADDING + max_rows * ROW_HEIGHT + PADDING;
    const x = @divTrunc(screen_w - width, 2);
    const y = @divTrunc(screen_h - height, 3); // slightly above center

    overlay_hwnd = win32.CreateWindowExW(
        win32.WS_EX_TOPMOST | win32.WS_EX_TOOLWINDOW,
        CLASS_NAME,
        comptime toWide("ZigSwitch"),
        win32.WS_POPUP,
        x, y, width, height,
        null, null, hInstance, null,
    );
}

pub fn toggle() void {
    const hwnd = overlay_hwnd orelse return;

    if (visible) {
        hide();
    } else {
        // Re-enumerate windows
        window_enum.enumerateWindows(&windows, &window_count, overlay_hwnd);

        // Compute clusters
        cluster_count = search.computeClusters(&windows, window_count, cfg.cluster_threshold, &clusters);
        cluster_index = 0;

        // Reset search
        search_len = 0;
        @memset(&search_buf, 0);
        selected = 0;
        scroll_offset = 0;

        // Apply filter
        refilter();

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

fn hide() void {
    const hwnd = overlay_hwnd orelse return;
    _ = win32.ShowWindow(hwnd, win32.SW_HIDE);
    visible = false;
}

fn refilter() void {
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

    if (selected >= filtered_count and filtered_count > 0) {
        selected = filtered_count - 1;
    }
    if (filtered_count == 0) {
        selected = 0;
    }
    scroll_offset = 0;
}

fn activateSelected() void {
    if (filtered_count == 0) return;

    const idx = filtered_indices[selected];
    const target_hwnd = windows[idx].hwnd;

    // Critical: set foreground WHILE we still have focus
    _ = win32.SetForegroundWindow(target_hwnd);
    hide();
}

fn wndProc(hwnd: win32.HWND, msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    switch (msg) {
        win32.WM_PAINT => {
            paint(hwnd);
            return 0;
        },
        win32.WM_ERASEBKGND => {
            return 1; // We handle background in WM_PAINT
        },
        win32.WM_KEYDOWN => {
            handleKeyDown(hwnd, wParam);
            return 0;
        },
        win32.WM_CHAR => {
            handleChar(hwnd, wParam);
            return 0;
        },
        win32.WM_ACTIVATE => {
            if (wParam == win32.WA_INACTIVE and visible) {
                hide();
            }
            return 0;
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        else => return win32.DefWindowProcW(hwnd, msg, wParam, lParam),
    }
}

fn handleKeyDown(hwnd: win32.HWND, key: win32.WPARAM) void {
    switch (key) {
        win32.VK_ESCAPE => {
            hide();
        },
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
            // Cycle clusters: All -> cluster1 -> cluster2 -> ... -> All
            if (cluster_count > 0) {
                cluster_index = (cluster_index + 1) % (cluster_count + 1);
            }
            selected = 0;
            refilter();
            _ = win32.InvalidateRect(hwnd, null, 0);
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
    // Ignore control characters (already handled in WM_KEYDOWN)
    if (char < 0x20) return;
    if (char == 0x7F) return; // DEL

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

    // Get client rect
    const width = ps.rcPaint.right - ps.rcPaint.left;
    const height = ps.rcPaint.bottom - ps.rcPaint.top;
    if (width <= 0 or height <= 0) return;

    // Double buffer
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

    // Select font
    if (font) |f| {
        _ = win32.SelectObject(mem_dc, @ptrCast(f));
    }
    _ = win32.SetBkMode(mem_dc, win32.TRANSPARENT);

    // Background
    const bg_brush = win32.CreateSolidBrush(BG_COLOR) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(bg_brush));
    var full_rect = win32.RECT{ .left = 0, .top = 0, .right = width, .bottom = height };
    _ = win32.FillRect(mem_dc, &full_rect, bg_brush);

    // Border
    const border_brush = win32.CreateSolidBrush(BORDER_COLOR) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(border_brush));
    // Top
    var border_rect = win32.RECT{ .left = 0, .top = 0, .right = width, .bottom = 1 };
    _ = win32.FillRect(mem_dc, &border_rect, border_brush);
    // Bottom
    border_rect = win32.RECT{ .left = 0, .top = height - 1, .right = width, .bottom = height };
    _ = win32.FillRect(mem_dc, &border_rect, border_brush);
    // Left
    border_rect = win32.RECT{ .left = 0, .top = 0, .right = 1, .bottom = height };
    _ = win32.FillRect(mem_dc, &border_rect, border_brush);
    // Right
    border_rect = win32.RECT{ .left = width - 1, .top = 0, .right = width, .bottom = height };
    _ = win32.FillRect(mem_dc, &border_rect, border_brush);

    // Search box background
    const search_brush = win32.CreateSolidBrush(SEARCH_BG) orelse return;
    defer _ = win32.DeleteObject(@ptrCast(search_brush));
    var search_rect = win32.RECT{
        .left = PADDING,
        .top = PADDING,
        .right = width - PADDING,
        .bottom = SEARCH_HEIGHT,
    };
    _ = win32.FillRect(mem_dc, &search_rect, search_brush);

    // Search text
    _ = win32.SetTextColor(mem_dc, TEXT_COLOR);
    if (search_len > 0) {
        _ = win32.TextOutW(mem_dc, PADDING + 4, PADDING + 4, &search_buf, @intCast(search_len));
    } else {
        // Placeholder
        _ = win32.SetTextColor(mem_dc, DIM_COLOR);
        const placeholder = comptime toWide("Type to search...");
        _ = win32.TextOutW(mem_dc, PADDING + 4, PADDING + 4, placeholder, comptime @intCast(std.unicode.utf8CountCodepoints("Type to search...") catch 17));
    }

    // Cluster indicator (top right)
    {
        _ = win32.SetTextColor(mem_dc, DIM_COLOR);
        var label_buf: [64]u16 = [_]u16{0} ** 64;
        var label_len: usize = 0;

        if (cluster_index == 0) {
            // "All (N)"
            const prefix = comptime toWide("All (");
            @memcpy(label_buf[0..5], prefix[0..5]);
            label_len = 5;
            label_len += formatNum(filtered_count, label_buf[label_len..]);
            label_buf[label_len] = ')';
            label_len += 1;
        } else {
            const c = &clusters[cluster_index - 1];
            const name_len = @min(c.exe_name_len, 40);
            @memcpy(label_buf[0..name_len], c.exe_name[0..name_len]);
            label_len = name_len;
            label_buf[label_len] = ' ';
            label_len += 1;
            label_buf[label_len] = '(';
            label_len += 1;
            label_len += formatNum(filtered_count, label_buf[label_len..]);
            label_buf[label_len] = ')';
            label_len += 1;
        }

        // Right-align: approximate position
        const label_x = width - PADDING - @as(i32, @intCast(label_len)) * 8;
        _ = win32.TextOutW(mem_dc, label_x, PADDING + 4, &label_buf, @intCast(label_len));
    }

    // Separator
    var sep_rect = win32.RECT{
        .left = 0,
        .top = SEARCH_HEIGHT + 2,
        .right = width,
        .bottom = SEARCH_HEIGHT + 3,
    };
    _ = win32.FillRect(mem_dc, &sep_rect, border_brush);

    // Window list
    const list_top = SEARCH_HEIGHT + PADDING;
    const max_rows = cfg.max_visible_rows;

    if (filtered_count == 0) {
        // No matching windows
        _ = win32.SetTextColor(mem_dc, DIM_COLOR);
        const no_match = comptime toWide("No matching windows");
        _ = win32.TextOutW(mem_dc, @divTrunc(width, 2) - 80, list_top + 20, no_match, 19);
    } else {
        const sel_brush = win32.CreateSolidBrush(SEL_COLOR) orelse return;
        defer _ = win32.DeleteObject(@ptrCast(sel_brush));

        const end = @min(scroll_offset + max_rows, filtered_count);
        for (scroll_offset..end) |vi| {
            const row: i32 = @intCast(vi - scroll_offset);
            const y = list_top + row * ROW_HEIGHT;
            const win_idx = filtered_indices[vi];
            const w = &windows[win_idx];

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

            // Icon
            if (w.icon) |icon| {
                _ = win32.DrawIconEx(mem_dc, PADDING, text_y, icon, ICON_SIZE, ICON_SIZE, 0, null, win32.DI_NORMAL);
            }

            // Process name (dimmed)
            const text_x = PADDING + ICON_SIZE + 6;
            _ = win32.SetTextColor(mem_dc, DIM_COLOR);
            if (w.exe_name_len > 0) {
                _ = win32.TextOutW(mem_dc, text_x, text_y, &w.exe_name, @intCast(w.exe_name_len));
            }

            // Separator " — "
            const sep = comptime toWide(" \u{2014} ");
            const sep_x = text_x + @as(i32, @intCast(w.exe_name_len)) * 8;
            _ = win32.SetTextColor(mem_dc, DIM_COLOR);
            _ = win32.TextOutW(mem_dc, sep_x, text_y, sep, 3);

            // Window title (bright)
            const title_x = sep_x + 3 * 8;
            _ = win32.SetTextColor(mem_dc, TEXT_COLOR);
            if (w.title_len > 0) {
                _ = win32.TextOutW(mem_dc, title_x, text_y, &w.title, @intCast(w.title_len));
            }
        }
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
    // Reverse
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
