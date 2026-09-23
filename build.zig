const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .os_tag = .windows,
            .abi = .gnu,
        },
    });
    // Default to ReleaseSmall. In Zig 0.16, standardOptimizeOption's
    // preferred_optimize_mode only applies when `-Drelease`/`--release=`
    // is passed; without it, that helper always falls back to Debug. So we
    // read the `-Doptimize=` option ourselves and supply the real default,
    // while still allowing `-Doptimize=Debug` (etc.) to override it.
    //
    // ReleaseSmall over ReleaseFast: this is a small background hotkey
    // utility with no hot per-keystroke path (the WH_KEYBOARD_LL hook that
    // used to run on every keystroke system-wide is gone — see CLAUDE.md),
    // so there's nothing performance-sensitive enough to justify optimizing
    // for speed over binary size. Note both ReleaseSmall and ReleaseFast
    // disable Zig's runtime safety checks (bounds checks, etc.); if a crash
    // shows up after this change, rebuild with `-Doptimize=Debug` or
    // `-Doptimize=ReleaseSafe` to get a safety panic with a stack trace.
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size",
    ) orelse .ReleaseSmall;

    const exe = b.addExecutable(.{
        .name = "zigswitch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Run as a background Windows app, not a console app.
    exe.subsystem = .windows;

    // Embed application icon
    exe.root_module.addWin32ResourceFile(.{ .file = b.path("zigswitch.rc") });

    exe.root_module.linkSystemLibrary("user32", .{});
    exe.root_module.linkSystemLibrary("gdi32", .{});
    exe.root_module.linkSystemLibrary("kernel32", .{});
    exe.root_module.linkSystemLibrary("shell32", .{});
    exe.root_module.linkSystemLibrary("advapi32", .{});
    exe.root_module.linkSystemLibrary("dwmapi", .{});

    b.installArtifact(exe);
}
