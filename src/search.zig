const std = @import("std");
const window_enum = @import("window_enum.zig");

pub const MAX_CLUSTERS = 32;

pub const Cluster = struct {
    exe_name: [256]u16 = [_]u16{0} ** 256,
    exe_name_len: usize = 0,
    count: usize = 0,
};

/// Case-insensitive substring match on UTF-16 strings
pub fn matchesSearch(haystack: []const u16, query: []const u16) bool {
    if (query.len == 0) return true;
    if (haystack.len < query.len) return false;

    for (0..haystack.len - query.len + 1) |i| {
        var matched = true;
        for (0..query.len) |j| {
            if (toLowerW(haystack[i + j]) != toLowerW(query[j])) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

/// Compute clusters from window list
pub fn computeClusters(
    windows: []const window_enum.WindowInfo,
    count: usize,
    threshold: usize,
    out: *[MAX_CLUSTERS]Cluster,
) usize {
    var cluster_count: usize = 0;

    for (0..count) |i| {
        const w = &windows[i];
        if (w.exe_name_len == 0) continue;

        // Check if we already have this exe
        var found = false;
        for (0..cluster_count) |c| {
            if (eqlSlice(out[c].exe_name[0..out[c].exe_name_len], w.exe_name[0..w.exe_name_len])) {
                out[c].count += 1;
                found = true;
                break;
            }
        }
        if (!found and cluster_count < MAX_CLUSTERS) {
            @memcpy(out[cluster_count].exe_name[0..w.exe_name_len], w.exe_name[0..w.exe_name_len]);
            out[cluster_count].exe_name_len = w.exe_name_len;
            out[cluster_count].count = 1;
            cluster_count += 1;
        }
    }

    // Filter by threshold and sort by count descending (bubble sort, small N)
    var filtered_count: usize = 0;
    var filtered: [MAX_CLUSTERS]Cluster = undefined;
    for (0..cluster_count) |i| {
        if (out[i].count >= threshold) {
            filtered[filtered_count] = out[i];
            filtered_count += 1;
        }
    }

    // Sort descending by count
    for (0..filtered_count) |i| {
        for (i + 1..filtered_count) |j| {
            if (filtered[j].count > filtered[i].count) {
                const tmp = filtered[i];
                filtered[i] = filtered[j];
                filtered[j] = tmp;
            }
        }
    }

    for (0..filtered_count) |i| {
        out[i] = filtered[i];
    }

    return filtered_count;
}

/// Apply search filter and optional cluster filter
pub fn applyFilter(
    windows: []const window_enum.WindowInfo,
    count: usize,
    search: []const u16,
    cluster_exe: ?[]const u16,
    out_indices: []usize,
) usize {
    var out_count: usize = 0;

    for (0..count) |i| {
        const w = &windows[i];

        // Cluster filter
        if (cluster_exe) |exe| {
            if (!eqlSlice(w.exe_name[0..w.exe_name_len], exe)) continue;
        }

        // Search filter — match against title or exe name
        if (search.len > 0) {
            const title_match = matchesSearch(w.title[0..w.title_len], search);
            const exe_match = matchesSearch(w.exe_name[0..w.exe_name_len], search);
            if (!title_match and !exe_match) continue;
        }

        if (out_count >= out_indices.len) break;
        out_indices[out_count] = i;
        out_count += 1;
    }

    return out_count;
}

fn toLowerW(c: u16) u16 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn eqlSlice(a: []const u16, b: []const u16) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (toLowerW(x) != toLowerW(y)) return false;
    }
    return true;
}
