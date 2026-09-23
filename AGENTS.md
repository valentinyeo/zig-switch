# Repository Guidelines

## Project Structure & Module Organization

ZigSwitch is a small Windows desktop utility written in Zig with direct Win32 API calls. The entry point is `src/main.zig`; supporting modules live beside it in `src/`.

- `src/ui.zig`: overlay rendering, keyboard input, mode and search state.
- `src/tray.zig`: tray icon and Alt+Tab low-level keyboard hook.
- `src/window_enum.zig`, `src/search.zig`, `src/launcher.zig`, `src/bookmarks.zig`: window, program, and bookmark discovery/search behavior.
- `src/win32.zig`: Win32 bindings and constants.
- `src/version.zig`: version string and summary shown from the tray menu.
- `zigswitch.rc` and `zigswitch.ico`: Windows resource metadata and icon.

Generated outputs belong in `.zig-cache/` and `zig-out/`; do not commit them.

## Build, Test, and Development Commands

- `zig build`: builds `zig-out/bin/zigswitch.exe` for Windows using the GNU ABI.
- `zig build -Doptimize=ReleaseFast`: creates an optimized local build.
- `.\zig-out\bin\zigswitch.exe`: runs the built app manually.
- `taskkill /F /IM zigswitch.exe`: stops a running copy before rebuilding or retesting hotkeys.
- `zig fmt build.zig src/*.zig`: formats Zig source files.

After code changes, stop the existing process, wait briefly for hotkey hooks to release, rebuild, then launch the new executable.

## Coding Style & Naming Conventions

Follow idiomatic Zig formatting with 4-space indentation and `zig fmt`. Use `snake_case` for functions, variables, and filenames. Keep modules narrowly scoped to their existing responsibility; prefer extending the current Win32 wrapper in `src/win32.zig` over scattering ad hoc FFI declarations. Avoid non-ASCII UI strings because local wide-string helpers only handle ASCII safely.

## Testing Guidelines

There is no automated test suite yet. Treat `zig build` as the required compile check. Manually smoke test both activation paths: Alt+Tab cycling and Ctrl+Space search. Also verify `b:` bookmark search, `s:` Start Menu search, minimized-window restore, Escape dismissal, and tray right-click version display when relevant.

## Commit & Pull Request Guidelines

Recent commits use concise, imperative summaries, often prefixed with a version, for example `v0.5.3: Restore minimized windows when activating from switcher`. Keep commits focused and update `src/version.zig` when behavior changes. Pull requests should describe the user-visible change, list manual verification steps, mention hotkey or tray behavior touched, and include screenshots only for UI rendering changes.

## Agent-Specific Notes

Be careful with global hooks and foreground-window behavior. Do not leave a stale `zigswitch.exe` running after verification. Preserve the existing pure Zig plus Win32 approach unless a change explicitly requires new dependencies.


<claude-mem-context>
# Memory Context

# [zig-switch] recent context, 2026-05-09 1:16am GMT+2

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 1 obs (328t read) | 14,747t work | 98% savings

### May 9, 2026
S19 Generate AGENTS.md contributor guide for zig-switch Windows desktop utility repository (May 9, 12:18 AM)
16 12:19a 🔴 Fixed build.zig API compatibility with Zig 0.16.0
S24 Fix Zig 0.16 compilation errors in zig-switch project and verify the build works (May 9, 12:24 AM)
**Investigated**: Examined the compilation error showing `std.fs.openFileAbsolute` is not available in Zig 0.16. Searched the Zig stdlib to understand what API replacements exist in the new version. Found that `std.Io.Dir.openFileAbsolute` exists but requires an `Io` context parameter which the legacy `std.fs` module no longer provides.

**Learned**: Zig 0.16 has completed a major refactor moving from `std.fs` to `std.Io` for file operations. The old `std.fs.openFileAbsolute` and file.readAll() patterns are deprecated. The build system API changed: `exe.addWin32ResourceFile()` and `exe.linkSystemLibrary()` moved to `exe.root_module.addWin32ResourceFile()` and `exe.root_module.linkSystemLibrary()` with updated method signatures.

**Completed**: Modified four files to resolve Zig 0.16 compatibility:
  - build.zig: Updated resource embedding and system library linking to use exe.root_module API
  - src/bookmarks.zig: Replaced std.fs.openFileAbsolute + file.readAll with Win32 API calls (CreateFileW + ReadFile) 
  - src/win32.zig: Added Win32 bindings for CreateFileW and ReadFile, plus associated constants (GENERIC_READ, FILE_SHARE_*, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL)
  - src/version.zig: Bumped version from 0.5.3 to 0.5.4 with summary "Build with Zig 0.16"
  
Build now passes successfully with `zig build` and the resulting zigswitch.exe is running (verified PID 20352).

**Next Steps**: No active work in progress. Build and runtime verification complete. Project is ready for testing or further feature development.


Access 15k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>