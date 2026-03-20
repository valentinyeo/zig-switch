const std = @import("std");
const win32 = @import("win32.zig");

pub const MAX_WINDOWS = 256;

pub const WindowInfo = struct {
    hwnd: win32.HWND,
    title: [256]u16 = [_]u16{0} ** 256,
    title_len: usize = 0,
    exe_name: [256]u16 = [_]u16{0} ** 256,
    exe_name_len: usize = 0,
    exe_path: [512]u16 = [_]u16{0} ** 512,
    exe_path_len: usize = 0,
    icon: ?win32.HICON = null,
};

var enum_buf: *[MAX_WINDOWS]WindowInfo = undefined;
var enum_count: *usize = undefined;
var skip_hwnd: ?win32.HWND = null;

pub fn enumerateWindows(buf: *[MAX_WINDOWS]WindowInfo, count: *usize, skip: ?win32.HWND) void {
    enum_buf = buf;
    enum_count = count;
    count.* = 0;
    skip_hwnd = skip;

    _ = win32.EnumWindows(&enumCallback, 0);
}

fn enumCallback(hwnd: win32.HWND, _: win32.LPARAM) callconv(.winapi) win32.BOOL {
    // Skip our own window
    if (skip_hwnd) |s| {
        if (hwnd == s) return 1;
    }

    // Must be visible
    if (win32.IsWindowVisible(hwnd) == 0) return 1;

    // Must have a title
    const title_len = win32.GetWindowTextLengthW(hwnd);
    if (title_len <= 0) return 1;

    // Must not be owned (skip child/popup windows)
    if (win32.GetWindow(hwnd, win32.GW_OWNER) != null) return 1;

    // Skip tool windows
    const ex_style = win32.GetWindowLongPtrW(hwnd, win32.GWL_EXSTYLE);
    if (ex_style & @as(isize, win32.WS_EX_TOOLWINDOW) != 0) return 1;

    if (enum_count.* >= MAX_WINDOWS) return 0;

    var info = WindowInfo{ .hwnd = hwnd };

    // Get title
    const len: usize = @intCast(win32.GetWindowTextW(hwnd, &info.title, 256));
    info.title_len = len;

    // Get process name
    var pid: win32.DWORD = 0;
    _ = win32.GetWindowThreadProcessId(hwnd, &pid);

    const process = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
    if (process) |proc| {
        defer _ = win32.CloseHandle(proc);
        var path_buf: [512]u16 = [_]u16{0} ** 512;
        var path_size: win32.DWORD = 512;
        if (win32.QueryFullProcessImageNameW(proc, 0, &path_buf, &path_size) != 0) {
            const path_len: usize = @intCast(path_size);
            // Copy full path for icon extraction
            @memcpy(info.exe_path[0..path_len], path_buf[0..path_len]);
            info.exe_path_len = path_len;

            // Extract just the filename
            var last_slash: usize = 0;
            for (0..path_len) |i| {
                if (path_buf[i] == '\\' or path_buf[i] == '/') last_slash = i + 1;
            }
            const name_len = path_len - last_slash;
            @memcpy(info.exe_name[0..name_len], path_buf[last_slash..path_len]);
            info.exe_name_len = name_len;
        }
    }

    // Get icon
    info.icon = getWindowIcon(hwnd, &info);

    enum_buf[enum_count.*] = info;
    enum_count.* += 1;

    return 1;
}

fn getWindowIcon(hwnd: win32.HWND, info: *const WindowInfo) ?win32.HICON {
    var result: usize = 0;

    // Try WM_GETICON ICON_SMALL2
    const ret1 = win32.SendMessageTimeoutW(hwnd, win32.WM_GETICON, win32.ICON_SMALL2, 0, win32.SMTO_ABORTIFHUNG, 100, &result);
    if (ret1 != 0 and result != 0) {
        return @ptrFromInt(result);
    }

    // Try WM_GETICON ICON_SMALL
    const ret2 = win32.SendMessageTimeoutW(hwnd, win32.WM_GETICON, win32.ICON_SMALL, 0, win32.SMTO_ABORTIFHUNG, 100, &result);
    if (ret2 != 0 and result != 0) {
        return @ptrFromInt(result);
    }

    // Try class icon
    const class_icon = win32.GetClassLongPtrW(hwnd, win32.GCLP_HICONSM);
    if (class_icon != 0) {
        return @ptrFromInt(class_icon);
    }

    // Try extracting from exe
    if (info.exe_path_len > 0) {
        var path_z: [513]u16 = [_]u16{0} ** 513;
        @memcpy(path_z[0..info.exe_path_len], info.exe_path[0..info.exe_path_len]);
        var small_icon: ?win32.HICON = null;
        const extracted = win32.ExtractIconExW(@ptrCast(&path_z), 0, null, &small_icon, 1);
        if (extracted > 0 and small_icon != null) {
            return small_icon;
        }
    }

    // Default icon
    return win32.LoadIconW(null, win32.IDI_APPLICATION);
}
