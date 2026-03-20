const std = @import("std");
const win32 = @import("win32.zig");

pub const MAX_BOOKMARKS = 512;

pub const Bookmark = struct {
    name: [256]u16 = [_]u16{0} ** 256,
    name_len: usize = 0,
    url: [512]u8 = [_]u8{0} ** 512,
    url_len: usize = 0,
    // For display: url as u16
    url_w: [512]u16 = [_]u16{0} ** 512,
    url_w_len: usize = 0,
};

var bmarks: [MAX_BOOKMARKS]Bookmark = undefined;
var bmark_count: usize = 0;
var loaded = false;

pub fn getItems() []Bookmark {
    if (!loaded) {
        loadBookmarks();
        loaded = true;
    }
    return bmarks[0..bmark_count];
}

pub fn getCount() usize {
    if (!loaded) {
        loadBookmarks();
        loaded = true;
    }
    return bmark_count;
}

pub fn reload() void {
    loaded = false;
    bmark_count = 0;
}

pub fn openBookmark(bm: *const Bookmark) void {
    if (bm.url_len == 0) return;
    // Convert URL to wide for ShellExecuteW
    var url_z: [513]u16 = [_]u16{0} ** 513;
    for (0..bm.url_len) |i| {
        url_z[i] = bm.url[i];
    }
    const open = comptime blk: {
        const s = "open";
        var buf: [s.len + 1]u16 = undefined;
        for (s, 0..) |c, i| buf[i] = c;
        buf[s.len] = 0;
        break :blk buf;
    };
    _ = win32.ShellExecuteW(null, @ptrCast(&open), @ptrCast(&url_z), null, null, win32.SW_SHOW);
}

fn loadBookmarks() void {
    bmark_count = 0;

    // Build path: %LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Bookmarks
    var path_buf: [512]u16 = [_]u16{0} ** 512;
    const env = "%LOCALAPPDATA%\\Microsoft\\Edge\\User Data\\Default\\Bookmarks";
    var src: [env.len + 1]u16 = undefined;
    for (env, 0..) |c, i| {
        src[i] = c;
    }
    src[env.len] = 0;
    const path_len = win32.ExpandEnvironmentStringsW(@ptrCast(&src), &path_buf, 512);
    if (path_len == 0 or path_len > 512) return;

    // Convert to u8 path for std.fs
    var path_u8: [512]u8 = undefined;
    const u8_len = path_len - 1; // exclude null
    for (0..u8_len) |i| {
        path_u8[i] = @intCast(path_buf[i] & 0xFF);
    }

    // Read the file
    const file = std.fs.openFileAbsolute(path_u8[0..u8_len], .{}) catch return;
    defer file.close();

    // Read up to 2MB
    var buf: [2 * 1024 * 1024]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return;
    const content = buf[0..bytes_read];

    // Simple JSON parser: find all "name" + "url" pairs for type "url"
    // We look for patterns: "type": "url" near "name": "..." and "url": "..."
    parseBookmarkNodes(content);
}

fn parseBookmarkNodes(content: []const u8) void {
    var i: usize = 0;
    while (i < content.len and bmark_count < MAX_BOOKMARKS) {
        // Find "type": "url"
        const type_marker = findStr(content[i..], "\"type\": \"url\"") orelse
            findStr(content[i..], "\"type\":\"url\"") orelse break;

        const block_start = if (type_marker > 200) type_marker - 200 else 0;
        const block_end = @min(type_marker + 600, content.len - i);
        const block = content[i + block_start .. i + block_end];

        // Find name in this block
        if (findJsonString(block, "\"name\"")) |name_val| {
            if (findJsonString(block, "\"url\"")) |url_val| {
                var bm = Bookmark{};

                // Copy name as UTF-16
                const name_len = @min(name_val.len, 255);
                for (0..name_len) |j| {
                    bm.name[j] = name_val[j];
                }
                bm.name_len = name_len;

                // Copy URL as u8
                const url_len = @min(url_val.len, 511);
                @memcpy(bm.url[0..url_len], url_val[0..url_len]);
                bm.url_len = url_len;

                // Also as u16 for display
                const disp_len = @min(url_len, 511);
                for (0..disp_len) |j| {
                    bm.url_w[j] = url_val[j];
                }
                bm.url_w_len = disp_len;

                bmarks[bmark_count] = bm;
                bmark_count += 1;
            }
        }

        i += type_marker + 10;
    }
}

fn findStr(haystack: []const u8, needle: []const u8) ?usize {
    if (haystack.len < needle.len) return null;
    for (0..haystack.len - needle.len + 1) |i| {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

fn findJsonString(block: []const u8, key: []const u8) ?[]const u8 {
    const key_pos = findStr(block, key) orelse return null;
    // Find the colon after key, then the opening quote of value
    var pos = key_pos + key.len;
    while (pos < block.len and block[pos] != '"') : (pos += 1) {}
    if (pos >= block.len) return null;
    pos += 1; // skip opening quote

    const start = pos;
    while (pos < block.len and block[pos] != '"') {
        if (block[pos] == '\\') pos += 1; // skip escaped chars
        pos += 1;
    }
    if (pos >= block.len) return null;
    return block[start..pos];
}
