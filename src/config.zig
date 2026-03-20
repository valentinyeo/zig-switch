const std = @import("std");
const win32 = @import("win32.zig");

pub const Config = struct {
    hotkey_modifiers: u32 = win32.MOD_CONTROL,
    hotkey_vk: u32 = win32.VK_SPACE,
    cluster_threshold: usize = 3,
    max_visible_rows: usize = 15,
};

pub fn loadConfig() Config {
    // For v1: just return defaults
    // TODO: parse config.ini from exe directory or %APPDATA%\zigswitch\config.ini
    return Config{};
}
