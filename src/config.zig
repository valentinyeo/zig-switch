const std = @import("std");
const win32 = @import("win32.zig");

pub const Config = struct {
    hotkey_modifiers: u32 = win32.MOD_CONTROL,
    hotkey_vk: u32 = win32.VK_SPACE_U32,
    // Alt+Tab replacement (see CLAUDE.md: WH_KEYBOARD_LL is banned on this
    // machine, and Windows reserves the literal Alt+Tab chord for its own
    // switcher, so RegisterHotKey can't claim it). Hold Ctrl+Alt, tap
    // Down/Up to cycle, release Ctrl or Alt to activate the selection.
    alttab_next_modifiers: u32 = win32.MOD_CONTROL | win32.MOD_ALT,
    alttab_next_vk: u32 = win32.VK_DOWN_U32,
    alttab_prev_modifiers: u32 = win32.MOD_CONTROL | win32.MOD_ALT,
    alttab_prev_vk: u32 = win32.VK_UP_U32,
    cluster_threshold: usize = 3,
    max_visible_rows: usize = 15,
};

pub fn loadConfig() Config {
    // For v1: just return defaults
    // TODO: parse config.ini from exe directory or %APPDATA%\zigswitch\config.ini
    return Config{};
}
