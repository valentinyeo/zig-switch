# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
zig build          # Output: zig-out/bin/zigswitch.exe (defaults to -Doptimize=ReleaseSmall since v0.6.0)
zig build run      # Build and run
zig build -Doptimize=Debug   # override the default for a debuggable build with safety checks
```

Target: Windows x86_64 (GNU ABI). Links user32, gdi32, kernel32, shell32, advapi32. No external dependencies — pure Zig + Win32 API.

**IMPORTANT: After every code change:**
1. `taskkill //F //IM zigswitch.exe` — kill the running process
2. `sleep 2` — wait for hotkey registration to release
3. `zig build 2>&1` — rebuild and **check for errors** (a failed build keeps the old binary!)
4. Launch the new exe and verify with `tasklist | grep zigswitch` that a new PID is active
5. Bump `src/version.zig` version + summary so user can confirm from tray right-click menu

## Never use WH_KEYBOARD_LL on this machine

**Never use `SetWindowsHookExW(WH_KEYBOARD_LL, ...)`** — low-level keyboard hooks crash this machine (hard rule, see the parent `windows-stuff` repo's CLAUDE.md). All hotkeys use `RegisterHotKey` instead (since v0.6.0). See "Alt+Tab replacement" below for how the hold-to-cycle behavior that used to need a hook is now done without one.

## Architecture

ZigSwitch is a hotkey-driven window switcher overlay for Windows.

**Two activation modes:**
- **Alt+Tab replacement (Ctrl+Alt+Down / Ctrl+Alt+Up)** — hold Ctrl+Alt, tap Down to cycle forward / Up to cycle backward, release Ctrl or Alt to activate the highlighted window. Space (while cycling) drops into search mode. **Behavior change from pre-v0.6.0**: this used to be the literal Alt+Tab chord, intercepted via a `WH_KEYBOARD_LL` hook. Windows reserves Alt+Tab for its own task switcher — `RegisterHotKey` cannot claim it — so the hook is gone and the trigger chord changed to Ctrl+Alt+Down/Up instead. Configurable via `config.zig`'s `alttab_next_*`/`alttab_prev_*` fields.
- **Ctrl+Space** — opens directly in search mode with typing.

**Search prefixes** (typed in search bar):
- No prefix — search open windows (default)
- `b:` — search Edge bookmarks, Enter opens in Edge
- `s:` — search Start Menu programs, Enter launches

**Keys:** Tab/Shift+Tab navigate, Enter activates, Ctrl+Q closes window, Escape dismisses.

### Module Responsibilities

| Module | Role |
|--------|------|
| `main.zig` | Entry point: hotkey registration (incl. Alt+Tab replacement), Win32 message loop, WM_HOTKEY dispatch, auto-start registry |
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
- **Alt+Tab replacement**: Ctrl+Alt+Down/Up are ordinary `RegisterHotKey` hotkeys (MOD_NOREPEAT), handled in `main.zig`'s WM_HOTKEY dispatch. RegisterHotKey has no key-up event, so "release modifier to activate" is done by polling `GetAsyncKeyState(VK_CONTROL/VK_MENU)` on a `SetTimer` that `ui.zig` starts only while the overlay is visible in alt-tab mode (`startModifierWatch`/`stopModifierWatch`) — never an always-on timer.
- **DPI-aware**: Per-monitor DPI awareness v2
- **Auto-start**: Registers in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` on every launch

## Gotchas

- `toWide()` converts byte-by-byte — only works for ASCII. Do NOT use Unicode chars like em dash.
- VK constants: use `WPARAM` type for switch cases in handleKeyDown, use `u32`/`DWORD`/`i32` for RegisterHotKey/GetAsyncKeyState calls (see `VK_*_U32` constants in `win32.zig`).
- When Alt is held, Windows sends `WM_SYSKEYDOWN` not `WM_KEYDOWN` — wndProc must handle both.
- `hide()` must call `stopModifierWatch()` (in `ui.zig`) whenever alt-tab mode ends, or the polling timer keeps running against a hidden window.
- `SetForegroundWindow` alone won't restore minimized windows — always check `IsIconic()` and call `ShowWindow(SW_RESTORE)` first.

## No Tests

No test infrastructure exists. The app is verified by running it manually.
