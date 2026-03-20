# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
zig build          # Output: zig-out/bin/zigswitch.exe
zig build run      # Build and run
```

Target: Windows x86_64 (GNU ABI). Links user32, gdi32, kernel32, shell32. No external dependencies — pure Zig + Win32 API.

**IMPORTANT: After every code change, you MUST kill the running zigswitch.exe process (by PID), rebuild, and relaunch.** The hotkey registration fails silently if an old instance is still running. Always verify with `tasklist | grep zigswitch` that the new PID is active. Bump `src/version.zig` with every change so the user can confirm the version from the tray menu.

## Architecture

ZigSwitch is a hotkey-driven window switcher overlay for Windows with three modes:

- **Switcher** (blue) — lists open windows, search by title/exe, Enter to focus, Ctrl+Q to close window
- **Launcher** (green) — scans Start Menu for .lnk shortcuts, Enter to launch
- **Bookmarks** (purple) — parses Edge bookmarks JSON, Enter to open in browser

**Activation**: Ctrl+Space (search mode), Alt+Tab (classic switcher with release-to-activate). Shift+Space cycles modes. Escape dismisses.

### Module Responsibilities

| Module | Role |
|--------|------|
| `main.zig` | Entry point: hotkey registration, Win32 message loop, Alt+Tab message dispatch |
| `tray.zig` | System tray icon, right-click menu, Alt+Tab low-level keyboard hook |
| `version.zig` | Version string and summary (bump with every change) |
| `ui.zig` | All rendering (GDI double-buffered), keyboard input, mode/state management |
| `win32.zig` | Win32 FFI bindings and type definitions |
| `window_enum.zig` | Enumerates visible windows (titles, exe names, icons) |
| `search.zig` | Case-insensitive UTF-16 substring matching, cluster filtering |
| `launcher.zig` | Recursively scans Start Menu directories for .lnk files (depth 3) |
| `bookmarks.zig` | Parses Edge bookmarks JSON from `%LOCALAPPDATA%` |
| `config.zig` | Configuration stub (hardcoded defaults, planned: config.ini) |

### Key Patterns

- **State**: Global mutable state lives in `ui.zig` (overlay_hwnd, mode, selection, search buffer, filtered indices)
- **Lazy loading**: Launcher and bookmarks data only load when their mode is first activated
- **Rendering**: Double-buffered GDI — create memory DC, draw everything, BitBlt to screen
- **Search**: Real-time incremental filter on title + exe name (OR), with cluster grouping (threshold: 3+ windows from same app)
- **DPI-aware**: Per-monitor DPI awareness v2

### Resources

- `zigswitch.ico` — app icon
- `zigswitch.rc` — resource file embedding the icon into the executable

## No Tests

No test infrastructure exists. The app is verified by running it manually.
