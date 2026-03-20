const std = @import("std");
const win32 = @import("win32.zig");

pub const MAX_ITEMS = 512;

pub const LaunchItem = struct {
    name: [256]u16 = [_]u16{0} ** 256,
    name_len: usize = 0,
    path: [512]u16 = [_]u16{0} ** 512,
    path_len: usize = 0,
    icon: ?win32.HICON = null,
};

var items: [MAX_ITEMS]LaunchItem = undefined;
var item_count: usize = 0;
var loaded = false;

pub fn getItems() []LaunchItem {
    if (!loaded) {
        loadStartMenuItems();
        loaded = true;
    }
    return items[0..item_count];
}

pub fn getCount() usize {
    if (!loaded) {
        loadStartMenuItems();
        loaded = true;
    }
    return item_count;
}

pub fn reload() void {
    loaded = false;
    item_count = 0;
}

pub fn launch(item: *const LaunchItem) void {
    if (item.path_len == 0) return;
    var path_z: [513]u16 = [_]u16{0} ** 513;
    @memcpy(path_z[0..item.path_len], item.path[0..item.path_len]);
    _ = win32.ShellExecuteW(null, null, @ptrCast(&path_z), null, null, win32.SW_SHOW);
}

fn loadStartMenuItems() void {
    item_count = 0;

    // User Start Menu
    var user_path: [512]u16 = [_]u16{0} ** 512;
    const user_len = expandEnvW("%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs", &user_path);
    if (user_len > 0) {
        scanDirectory(user_path[0..user_len], 0);
    }

    // System Start Menu
    var sys_path: [512]u16 = [_]u16{0} ** 512;
    const sys_len = expandEnvW("%ProgramData%\\Microsoft\\Windows\\Start Menu\\Programs", &sys_path);
    if (sys_len > 0) {
        scanDirectory(sys_path[0..sys_len], 0);
    }
}

fn scanDirectory(dir: []const u16, depth: usize) void {
    if (depth > 3) return; // Don't recurse too deep
    if (item_count >= MAX_ITEMS) return;

    // Build search pattern: dir\*
    var pattern: [600]u16 = [_]u16{0} ** 600;
    @memcpy(pattern[0..dir.len], dir);
    pattern[dir.len] = '\\';
    pattern[dir.len + 1] = '*';
    pattern[dir.len + 2] = 0;

    var find_data: win32.WIN32_FIND_DATAW = std.mem.zeroes(win32.WIN32_FIND_DATAW);
    const handle = win32.FindFirstFileW(@ptrCast(&pattern), &find_data);
    if (handle == win32.INVALID_HANDLE_VALUE) return;
    defer _ = win32.FindClose(handle);

    while (true) {
        const name_slice = nameSlice(&find_data.cFileName);

        // Skip . and ..
        if (name_slice.len == 1 and name_slice[0] == '.') {
            if (win32.FindNextFileW(handle, &find_data) == 0) break;
            continue;
        }
        if (name_slice.len == 2 and name_slice[0] == '.' and name_slice[1] == '.') {
            if (win32.FindNextFileW(handle, &find_data) == 0) break;
            continue;
        }

        if (find_data.dwFileAttributes & win32.FILE_ATTRIBUTE_DIRECTORY != 0) {
            // Recurse into subdirectory
            var subdir: [600]u16 = [_]u16{0} ** 600;
            @memcpy(subdir[0..dir.len], dir);
            subdir[dir.len] = '\\';
            @memcpy(subdir[dir.len + 1 .. dir.len + 1 + name_slice.len], name_slice);
            scanDirectory(subdir[0 .. dir.len + 1 + name_slice.len], depth + 1);
        } else {
            // Check if it's a .lnk file
            if (endsWithLnk(name_slice)) {
                if (item_count < MAX_ITEMS) {
                    var item = LaunchItem{};

                    // Display name = filename without .lnk
                    const display_len = name_slice.len - 4; // Remove ".lnk"
                    @memcpy(item.name[0..display_len], name_slice[0..display_len]);
                    item.name_len = display_len;

                    // Full path
                    const full_len = dir.len + 1 + name_slice.len;
                    @memcpy(item.path[0..dir.len], dir);
                    item.path[dir.len] = '\\';
                    @memcpy(item.path[dir.len + 1 .. full_len], name_slice);
                    item.path_len = full_len;

                    // Extract icon from .lnk
                    var path_z: [513]u16 = [_]u16{0} ** 513;
                    @memcpy(path_z[0..item.path_len], item.path[0..item.path_len]);
                    var small_icon: ?win32.HICON = null;
                    const extracted = win32.ExtractIconExW(@ptrCast(&path_z), 0, null, &small_icon, 1);
                    if (extracted > 0) {
                        item.icon = small_icon;
                    }

                    items[item_count] = item;
                    item_count += 1;
                }
            }
        }

        if (win32.FindNextFileW(handle, &find_data) == 0) break;
    }
}

fn endsWithLnk(name: []const u16) bool {
    if (name.len < 4) return false;
    const suffix = name[name.len - 4 ..];
    return (suffix[0] == '.' and
        (suffix[1] == 'l' or suffix[1] == 'L') and
        (suffix[2] == 'n' or suffix[2] == 'N') and
        (suffix[3] == 'k' or suffix[3] == 'K'));
}

fn nameSlice(name: *const [260]u16) []const u16 {
    var len: usize = 0;
    while (len < 260 and name[len] != 0) : (len += 1) {}
    return name[0..len];
}

fn expandEnvW(comptime env: []const u8, out: *[512]u16) usize {
    var src: [env.len + 1]u16 = undefined;
    for (env, 0..) |c, i| {
        src[i] = c;
    }
    src[env.len] = 0;
    const len = win32.ExpandEnvironmentStringsW(@ptrCast(&src), out, 512);
    if (len == 0 or len > 512) return 0;
    return @intCast(len - 1); // Exclude null terminator
}
