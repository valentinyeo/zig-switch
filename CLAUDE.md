# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
zig build          # Output: zig-out/bin/zigswitch.exe
zig build run      # Build and run
```

Target: Windows x86_64 (GNU ABI). Links user32, gdi32, kernel32, shell32, advapi32. No external dependencies — pure Zig + Win32 API.

**IMPORTANT: After every code change:**
1. `taskkill //F //IM zigswitch.exe` — kill the running process
2. `sleep 2` — wait for hotkey registration to release
3. `zig build 2>&1` — rebuild and **check for errors** (a failed build keeps the old binary!)
4. Launch the new exe and verify with `tasklist | grep zigswitch` that a new PID is active
5. Bump `src/version.zig` version + summary so user can confirm from tray right-click menu

## Architecture

ZigSwitch is a hotkey-driven window switcher overlay for Windows.

**Two activation modes:**
- **Alt+Tab** — classic behavior: hold Alt, Tab cycles, release Alt switches. Space drops into search mode.
- **Ctrl+Space** — opens directly in search mode with typing.

**Search prefixes** (typed in search bar):
- No prefix — search open windows (default)
- `b:` — search Edge bookmarks, Enter opens in Edge
- `s:` — search Start Menu programs, Enter launches

**Keys:** Tab/Shift+Tab navigate, Enter activates, Ctrl+Q closes window, Escape dismisses.

### Module Responsibilities

| Module | Role |
|--------|------|
| `main.zig` | Entry point: hotkey registration, Win32 message loop, Alt+Tab message dispatch, auto-start registry |
| `tray.zig` | System tray icon, right-click menu, Alt+Tab low-level keyboard hook |
| `version.zig` | Version string and summary (bump with every change) |
| `ui.zig` | All rendering (GDI double-buffered), keyboard input, mode/state management |
| `win32.zig` | Win32 FFI bindings and type definitions |
| `window_enum.zig` | Enumerates visible windows (titles, exe names, icons) via EnumWindows (Z-order) |
| `search.zig` | Case-insensitive UTF-16 substring matching |
| `launcher.zig` | Recursively scans Start Menu directories for .lnk files, deduplicates by name |
| `bookmarks.zig` | Parses Edge bookmarks JSON from `%LOCALAPPDATA%` |
| `config.zig` | Configuration stub (hardcoded defaults) |

### Key Patterns

- **State**: Global mutable state lives in `ui.zig` (overlay_hwnd, mode, selection, search buffer, filtered indices)
- **Rendering**: Double-buffered GDI — create memory DC, draw everything, BitBlt to screen
- **Search**: `getEffectiveMode()` checks for `b:`/`s:` prefix, `getSearchQuery()` strips it. Refilter uses effective mode.
- **Alt+Tab hook**: LL keyboard hook in `tray.zig`. Track Alt/Shift state manually (GetKeyState unreliable in LL hooks). Posts thread messages to main loop, NOT window messages. Hook must consume Alt key-up when alttab_active to prevent menu bar activation.
- **DPI-aware**: Per-monitor DPI awareness v2
- **Auto-start**: Registers in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` on every launch

## Gotchas

- `toWide()` converts byte-by-byte — only works for ASCII. Do NOT use Unicode chars like em dash.
- VK constants: use `WPARAM` type for switch cases in handleKeyDown, use `u32`/`DWORD` for hook vkCode comparisons.
- When Alt is held, Windows sends `WM_SYSKEYDOWN` not `WM_KEYDOWN` — wndProc must handle both.
- The overlay may not have keyboard focus during Alt+Tab mode — intercept keys in the LL hook instead.
- `hide()` must call `tray.cancelAltTab()` to reset hook state and prevent stuck hooks blocking system-wide typing.
- `SetForegroundWindow` alone won't restore minimized windows — always check `IsIconic()` and call `ShowWindow(SW_RESTORE)` first.

## No Tests

No test infrastructure exists. The app is verified by running it manually.
