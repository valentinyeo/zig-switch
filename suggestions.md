# Suggestions: battery / idle power

Date: 2026-09-23
Status: proposal, nothing implemented

## Measured

Not measured in this pass (no baseline number was provided for
`zigswitch.exe`).

## Wake sources found

- No idle-loop timers exist. The message loop (`src/main.zig:32-52`)
  blocks on `GetMessageW` and only acts on hotkey/Alt-Tab messages or
  dispatches normal window messages — no `SetTimer`/`WM_TIMER` is
  actually used (declared in `src/win32.zig:239,257` but unreferenced
  elsewhere).
- `window_enum.enumerateWindows()` (`src/window_enum.zig:22`) is only
  called from `refreshCurrentMode()` (`src/ui.zig:418`), which runs
  when the switcher overlay opens — event-driven, not polled.
- All `InvalidateRect` calls (`src/ui.zig:306,339,351,374,398,558,...`)
  are inside input/toggle handlers, not an idle redraw loop — confirmed
  no redraw-while-hidden.
- `src/tray.zig:34-39` — `SetWindowsHookExW(WH_KEYBOARD_LL, ...)` is
  installed unconditionally in `tray.init()`, called from
  `main.zig:25`, and stays installed for the process lifetime. This
  hook's callback (`llKeyboardProc`, `tray.zig:53-132`) runs in-process
  on **every keystroke system-wide**, not just when the switcher is
  open. This is the one continuous background cost in the app, and it
  scales with the user's typing activity rather than with a timer.
  **Note:** both `zig-switch\CLAUDE.md`/`windows-stuff\CLAUDE.md` and
  this task's own instructions call out `WH_KEYBOARD_LL` as a hook that
  has crashed this machine before and say to use `RegisterHotKey`
  only. The app already uses `RegisterHotKey` for the main toggle
  (`main.zig:15`) but still needs the low-level hook to intercept
  native Alt+Tab, which Windows does not allow via `RegisterHotKey`.
  This is flagged here as a stability risk carried over from existing
  code, not a battery fix to add — do not extend its use.
- `build.zig:10` — `b.standardOptimizeOption(.{})` defaults to Debug
  when the build isn't invoked with `-Doptimize=...`. The installed
  `zig-out\bin\zigswitch.exe` is 1.9 MB (dated 2026-05-11), consistent
  with an unoptimized Debug build. Debug builds carry safety checks and
  no inlining, which directly inflates the cost of the per-keystroke
  hook callback above.

## Proposed fixes

1. **Build with `-Doptimize=ReleaseSmall` (or `ReleaseFast`) for the
   installed binary.** Since the keyboard hook runs on every keystroke
   system-wide, cutting per-call overhead here has a multiplier effect
   proportional to typing volume, not just idle draw. Concrete change:
   update the build script/instructions used to produce
   `zig-out\bin\zigswitch.exe` to pass `-Doptimize=ReleaseSmall`.
   Risk: low (verify hotkeys/overlay still behave the same).
   Effort: S.
2. **Re-audit the `WH_KEYBOARD_LL` hook's necessity/scope.** Confirm
   whether the hook can be scoped down (e.g., skip processing for key
   codes it never needs, which it already does reasonably well) or
   whether an alternative Alt-Tab interception exists. This is a
   stability item more than a battery item — no immediate reduction is
   proposed given the constraint against expanding hook usage.
   Risk: high if changed carelessly (this exact hook family has
   crashed the machine before). Effort: L.
3. No timer/polling fixes are needed — the architecture is already
   event-driven.

## How to verify

Measure core-sec/min for `zigswitch.exe` over 3 minutes idle (no
keystrokes, overlay closed), before/after the Release build swap:

```powershell
$p = Get-Process zigswitch
$c0 = $p.TotalProcessorTime
Start-Sleep -Seconds 180
$p.Refresh(); $c1 = $p.TotalProcessorTime
(($c1 - $c0).TotalSeconds) / 3   # core-sec/min
```

Since there's no idle timer, true-idle core-sec/min should already be
near zero; the more meaningful comparison is CPU time consumed per
1,000 keystrokes (Debug vs Release build) to see the hook-callback
delta, since that's the only continuous background cost identified.
