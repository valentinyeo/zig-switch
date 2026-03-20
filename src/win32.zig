const std = @import("std");

// Types
pub const HWND = std.os.windows.HWND;
pub const HINSTANCE = std.os.windows.HINSTANCE;
pub const HICON = *opaque {};
pub const HBRUSH = *opaque {};
pub const HDC = *opaque {};
pub const HFONT = *opaque {};
pub const HBITMAP = *opaque {};
pub const HGDIOBJ = *opaque {};
pub const HMENU = *opaque {};
pub const HCURSOR = *opaque {};
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const BOOL = i32;
pub const DWORD = u32;
pub const UINT = u32;
pub const LONG = i32;
pub const ATOM = u16;
pub const COLORREF = DWORD;
pub const HANDLE = std.os.windows.HANDLE;

pub const RECT = extern struct {
    left: LONG = 0,
    top: LONG = 0,
    right: LONG = 0,
    bottom: LONG = 0,
};

pub const POINT = extern struct {
    x: LONG = 0,
    y: LONG = 0,
};

pub const MSG = extern struct {
    hwnd: ?HWND = null,
    message: UINT = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: DWORD = 0,
    pt: POINT = .{},
};

pub const PAINTSTRUCT = extern struct {
    hdc: ?HDC = null,
    fErase: BOOL = 0,
    rcPaint: RECT = .{},
    fRestore: BOOL = 0,
    fIncUpdate: BOOL = 0,
    rgbReserved: [32]u8 = [_]u8{0} ** 32,
};

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: ?WNDPROC = null,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: ?[*:0]const u16 = null,
    hIconSm: ?HICON = null,
};

pub const TEXTMETRICW = extern struct {
    tmHeight: LONG = 0,
    tmAscent: LONG = 0,
    tmDescent: LONG = 0,
    tmInternalLeading: LONG = 0,
    tmExternalLeading: LONG = 0,
    tmAveCharWidth: LONG = 0,
    tmMaxCharWidth: LONG = 0,
    tmWeight: LONG = 0,
    tmOverhang: LONG = 0,
    tmDigitizedAspectX: LONG = 0,
    tmDigitizedAspectY: LONG = 0,
    tmFirstChar: u16 = 0,
    tmLastChar: u16 = 0,
    tmDefaultChar: u16 = 0,
    tmBreakChar: u16 = 0,
    tmItalic: u8 = 0,
    tmUnderlined: u8 = 0,
    tmStruckOut: u8 = 0,
    tmPitchAndFamily: u8 = 0,
    tmCharSet: u8 = 0,
};

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

// Constants
pub const WS_POPUP: DWORD = 0x80000000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const WS_EX_TOPMOST: DWORD = 0x00000008;
pub const WS_EX_TOOLWINDOW: DWORD = 0x00000080;
pub const WS_EX_LAYERED: DWORD = 0x00080000;
pub const WS_EX_NOACTIVATE: DWORD = 0x08000000;

pub const WM_DESTROY: UINT = 0x0002;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_ERASEBKGND: UINT = 0x0014;
pub const WM_ACTIVATE: UINT = 0x0006;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_CHAR: UINT = 0x0102;
pub const WM_HOTKEY: UINT = 0x0312;
pub const WM_GETICON: UINT = 0x007F;

pub const WA_INACTIVE: WPARAM = 0;

pub const VK_RETURN: WPARAM = 0x0D;
pub const VK_ESCAPE: WPARAM = 0x1B;
pub const VK_BACK: WPARAM = 0x08;
pub const VK_TAB: WPARAM = 0x09;
pub const VK_UP: WPARAM = 0x26;
pub const VK_DOWN: WPARAM = 0x28;
pub const VK_SPACE: u32 = 0x20;

pub const MOD_ALT: u32 = 0x0001;
pub const MOD_CONTROL: u32 = 0x0002;
pub const MOD_SHIFT: u32 = 0x0004;
pub const MOD_WIN: u32 = 0x0008;

pub const SW_SHOW: i32 = 5;
pub const SW_HIDE: i32 = 0;

pub const SM_CXSCREEN: i32 = 0;
pub const SM_CYSCREEN: i32 = 1;

pub const CS_HREDRAW: UINT = 0x0002;
pub const CS_VREDRAW: UINT = 0x0001;

pub const MB_OK: UINT = 0x00000000;
pub const MB_ICONERROR: UINT = 0x00000010;

pub const ICON_SMALL: WPARAM = 0;
pub const ICON_SMALL2: WPARAM = 2;
pub const ICON_BIG: WPARAM = 1;

pub const GCLP_HICONSM: i32 = -34;

pub const GW_OWNER: UINT = 4;
pub const GWL_EXSTYLE: i32 = -20;

pub const SMTO_ABORTIFHUNG: UINT = 0x0002;

pub const PROCESS_QUERY_LIMITED_INFORMATION: DWORD = 0x1000;

pub const IDI_APPLICATION: usize = 32512;

pub const DI_NORMAL: UINT = 0x0003;

pub const SRCCOPY: DWORD = 0x00CC0020;

pub const TRANSPARENT: i32 = 1;

pub const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: isize = -4;

pub const CW_USEDEFAULT: i32 = @as(i32, @bitCast(@as(u32, 0x80000000)));

pub const FW_NORMAL: i32 = 400;
pub const DEFAULT_CHARSET: u32 = 1;
pub const OUT_DEFAULT_PRECIS: u32 = 0;
pub const CLIP_DEFAULT_PRECIS: u32 = 0;
pub const CLEARTYPE_QUALITY: u32 = 5;
pub const DEFAULT_PITCH: u32 = 0;
pub const FF_DONTCARE: u32 = 0;

pub const INFINITE: DWORD = 0xFFFFFFFF;

// User32 functions
pub extern "user32" fn RegisterHotKey(hWnd: ?HWND, id: i32, fsModifiers: u32, vk: u32) callconv(.winapi) BOOL;
pub extern "user32" fn UnregisterHotKey(hWnd: ?HWND, id: i32) callconv(.winapi) BOOL;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn MessageBoxW(hWnd: ?HWND, lpText: [*:0]const u16, lpCaption: [*:0]const u16, uType: UINT) callconv(.winapi) i32;
pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.winapi) void;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn CreateWindowExW(dwExStyle: DWORD, lpClassName: [*:0]const u16, lpWindowName: [*:0]const u16, dwStyle: DWORD, x: i32, y: i32, nWidth: i32, nHeight: i32, hWndParent: ?HWND, hMenu: ?HMENU, hInstance: ?HINSTANCE, lpParam: ?*anyopaque) callconv(.winapi) ?HWND;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.winapi) BOOL;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetSystemMetrics(nIndex: i32) callconv(.winapi) i32;
pub extern "user32" fn InvalidateRect(hWnd: ?HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.winapi) ?HDC;
pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "user32" fn FillRect(hDC: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.winapi) i32;
pub extern "user32" fn GetDC(hWnd: ?HWND) callconv(.winapi) ?HDC;
pub extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: HDC) callconv(.winapi) i32;
pub extern "user32" fn DrawIconEx(hdc: HDC, xLeft: i32, yTop: i32, hIcon: HICON, cxWidth: i32, cyWidth: i32, istepIfAniCur: UINT, hbrFlickerFreeDraw: ?HBRUSH, diFlags: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn LoadIconW(hInstance: ?HINSTANCE, lpIconName: usize) callconv(.winapi) ?HICON;
pub extern "user32" fn DestroyIcon(hIcon: HICON) callconv(.winapi) BOOL;
pub extern "user32" fn EnumWindows(lpEnumFunc: *const fn (HWND, LPARAM) callconv(.winapi) BOOL, lParam: LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*]u16, nMaxCount: i32) callconv(.winapi) i32;
pub extern "user32" fn GetWindowTextLengthW(hWnd: HWND) callconv(.winapi) i32;
pub extern "user32" fn IsWindowVisible(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindow(hWnd: HWND, uCmd: UINT) callconv(.winapi) ?HWND;
pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) callconv(.winapi) isize;
pub extern "user32" fn GetClassLongPtrW(hWnd: HWND, nIndex: i32) callconv(.winapi) usize;
pub extern "user32" fn GetWindowThreadProcessId(hWnd: HWND, lpdwProcessId: *DWORD) callconv(.winapi) DWORD;
pub extern "user32" fn SendMessageTimeoutW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM, fuFlags: UINT, uTimeout: UINT, lpdwResult: ?*usize) callconv(.winapi) usize;
pub extern "user32" fn SetLayeredWindowAttributes(hWnd: HWND, crKey: COLORREF, bAlpha: u8, dwFlags: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: usize) callconv(.winapi) ?HCURSOR;
pub extern "user32" fn SetTimer(hWnd: ?HWND, nIDEvent: usize, uElapse: UINT, lpTimerFunc: ?*anyopaque) callconv(.winapi) usize;
pub extern "user32" fn KillTimer(hWnd: ?HWND, uIDEvent: usize) callconv(.winapi) BOOL;
pub extern "user32" fn SetFocus(hWnd: ?HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn GetKeyState(nVirtKey: i32) callconv(.winapi) i16;

pub const VK_CONTROL: i32 = 0x11;
pub const VK_SHIFT: i32 = 0x10;

pub fn postClose(hwnd: HWND) void {
    var result: usize = 0;
    _ = SendMessageTimeoutW(hwnd, WM_CLOSE, 0, 0, SMTO_ABORTIFHUNG, 1000, &result);
}

pub const IDC_ARROW: usize = 32512;
pub const LWA_ALPHA: DWORD = 0x00000002;

pub const WM_TIMER: UINT = 0x0113;

// GDI32 functions
pub extern "gdi32" fn CreateCompatibleDC(hdc: ?HDC) callconv(.winapi) ?HDC;
pub extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, cx: i32, cy: i32) callconv(.winapi) ?HBITMAP;
pub extern "gdi32" fn SelectObject(hdc: HDC, h: *anyopaque) callconv(.winapi) ?HGDIOBJ;
pub extern "gdi32" fn BitBlt(hdc: HDC, x: i32, y: i32, cx: i32, cy: i32, hdcSrc: HDC, x1: i32, y1: i32, rop: DWORD) callconv(.winapi) BOOL;
pub extern "gdi32" fn DeleteDC(hdc: HDC) callconv(.winapi) BOOL;
pub extern "gdi32" fn DeleteObject(ho: *anyopaque) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(.winapi) ?HBRUSH;
pub extern "gdi32" fn CreateFontW(cHeight: i32, cWidth: i32, cEscapement: i32, cOrientation: i32, cWeight: i32, bItalic: DWORD, bUnderline: DWORD, bStrikeOut: DWORD, iCharSet: DWORD, iOutPrecision: DWORD, iClipPrecision: DWORD, iQuality: DWORD, iPitchAndFamily: DWORD, pszFaceName: [*:0]const u16) callconv(.winapi) ?HFONT;
pub extern "gdi32" fn TextOutW(hdc: HDC, x: i32, y: i32, lpString: [*]const u16, c: i32) callconv(.winapi) BOOL;
pub extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(.winapi) COLORREF;
pub extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.winapi) i32;
pub extern "gdi32" fn GetTextMetricsW(hdc: HDC, lptm: *TEXTMETRICW) callconv(.winapi) BOOL;

// Kernel32 functions
pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) ?HINSTANCE;
pub extern "kernel32" fn OpenProcess(dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwProcessId: DWORD) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn QueryFullProcessImageNameW(hProcess: HANDLE, dwFlags: DWORD, lpExeName: [*]u16, lpdwSize: *DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetModuleFileNameW(hModule: ?HINSTANCE, lpFilename: [*]u16, nSize: DWORD) callconv(.winapi) DWORD;

// Shell32 functions
pub extern "shell32" fn ExtractIconExW(lpszFile: [*:0]const u16, nIconIndex: i32, phiconLarge: ?*?HICON, phiconSmall: ?*?HICON, nIcons: UINT) callconv(.winapi) UINT;
pub extern "shell32" fn ShellExecuteW(hwnd: ?HWND, lpOperation: ?[*:0]const u16, lpFile: [*:0]const u16, lpParameters: ?[*:0]const u16, lpDirectory: ?[*:0]const u16, nShowCmd: i32) callconv(.winapi) isize;
pub extern "shell32" fn SHGetFileInfoW(pszPath: [*:0]const u16, dwFileAttributes: DWORD, psfi: *SHFILEINFOW, cbFileInfo: UINT, uFlags: UINT) callconv(.winapi) usize;

pub const SHFILEINFOW = extern struct {
    hIcon: ?HICON = null,
    iIcon: i32 = 0,
    dwAttributes: DWORD = 0,
    szDisplayName: [260]u16 = [_]u16{0} ** 260,
    szTypeName: [80]u16 = [_]u16{0} ** 80,
};

pub const SHGFI_ICON: UINT = 0x000000100;
pub const SHGFI_SMALLICON: UINT = 0x000000001;

// Kernel32 file search
pub const WIN32_FIND_DATAW = extern struct {
    dwFileAttributes: DWORD = 0,
    ftCreationTime: u64 = 0,
    ftLastAccessTime: u64 = 0,
    ftLastWriteTime: u64 = 0,
    nFileSizeHigh: DWORD = 0,
    nFileSizeLow: DWORD = 0,
    dwReserved0: DWORD = 0,
    dwReserved1: DWORD = 0,
    cFileName: [260]u16 = [_]u16{0} ** 260,
    cAlternateFileName: [14]u16 = [_]u16{0} ** 14,
};

pub const FILE_ATTRIBUTE_DIRECTORY: DWORD = 0x10;
pub const INVALID_HANDLE_VALUE_INT: usize = @as(usize, @bitCast(@as(isize, -1)));
pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(INVALID_HANDLE_VALUE_INT);

pub extern "kernel32" fn FindFirstFileW(lpFileName: [*:0]const u16, lpFindFileData: *WIN32_FIND_DATAW) callconv(.winapi) HANDLE;
pub extern "kernel32" fn FindNextFileW(hFindFile: HANDLE, lpFindFileData: *WIN32_FIND_DATAW) callconv(.winapi) BOOL;
pub extern "kernel32" fn FindClose(hFindFile: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn ExpandEnvironmentStringsW(lpSrc: [*:0]const u16, lpDst: *[512]u16, nSize: DWORD) callconv(.winapi) DWORD;

// Low-level keyboard hook
pub const HHOOK = *opaque {};
pub const WH_KEYBOARD_LL: i32 = 13;
pub const HC_ACTION: i32 = 0;
pub const WM_KEYDOWN_HOOK: DWORD = 0x0100;
pub const WM_SYSKEYDOWN: DWORD = 0x0104;
pub const WM_KEYUP_HOOK: DWORD = 0x0101;
pub const WM_SYSKEYUP: DWORD = 0x0105;
pub const VK_LMENU: DWORD = 0xA4; // Left Alt
pub const VK_RMENU: DWORD = 0xA5; // Right Alt
pub const VK_TAB_U32: DWORD = 0x09;
pub const LLKHF_ALTDOWN: DWORD = 0x20;

pub const KBDLLHOOKSTRUCT = extern struct {
    vkCode: DWORD = 0,
    scanCode: DWORD = 0,
    flags: DWORD = 0,
    time: DWORD = 0,
    dwExtraInfo: usize = 0,
};

pub const HOOKPROC_LL = *const fn (i32, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub extern "user32" fn SetWindowsHookExW(idHook: i32, lpfn: HOOKPROC_LL, hmod: ?HINSTANCE, dwThreadId: DWORD) callconv(.winapi) ?HHOOK;
pub extern "user32" fn CallNextHookEx(hhk: ?HHOOK, nCode: i32, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn UnhookWindowsHookEx(hhk: HHOOK) callconv(.winapi) BOOL;
pub extern "user32" fn PostMessageW(hWnd: ?HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;

pub const WM_APP_ALTTAB: UINT = 0x8001; // Custom message for alt-tab trigger
pub const WM_APP_TAB: UINT = 0x8002; // Custom message for tab while overlay visible
pub const WM_APP_CTRLTAB: UINT = 0x8003; // Custom message for ctrl+tab mode switch

// Tray icon
pub const NOTIFYICONDATAW = extern struct {
    cbSize: DWORD = @sizeOf(NOTIFYICONDATAW),
    hWnd: ?HWND = null,
    uID: UINT = 0,
    uFlags: UINT = 0,
    uCallbackMessage: UINT = 0,
    hIcon: ?HICON = null,
    szTip: [128]u16 = [_]u16{0} ** 128,
    dwState: DWORD = 0,
    dwStateMask: DWORD = 0,
    szInfo: [256]u16 = [_]u16{0} ** 256,
    uVersion: UINT = 0,
    szInfoTitle: [64]u16 = [_]u16{0} ** 64,
    dwInfoFlags: DWORD = 0,
    guidItem: [16]u8 = [_]u8{0} ** 16,
    hBalloonIcon: ?HICON = null,
};

pub const NIM_ADD: DWORD = 0x00000000;
pub const NIM_MODIFY: DWORD = 0x00000001;
pub const NIM_DELETE: DWORD = 0x00000002;
pub const NIF_MESSAGE: UINT = 0x00000001;
pub const NIF_ICON: UINT = 0x00000002;
pub const NIF_TIP: UINT = 0x00000004;

pub const WM_APP_TRAY: UINT = 0x8010;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_LBUTTONDBLCLK: UINT = 0x0203;
pub const WM_COMMAND: UINT = 0x0111;

pub extern "shell32" fn Shell_NotifyIconW(dwMessage: DWORD, lpData: *NOTIFYICONDATAW) callconv(.winapi) BOOL;

// Menu
pub extern "user32" fn CreatePopupMenu() callconv(.winapi) ?HMENU;
pub extern "user32" fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: usize, lpNewItem: ?[*:0]const u16) callconv(.winapi) BOOL;
pub extern "user32" fn TrackPopupMenu(hMenu: HMENU, uFlags: UINT, x: i32, y: i32, nReserved: i32, hWnd: HWND, prcRect: ?*const RECT) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyMenu(hMenu: HMENU) callconv(.winapi) BOOL;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.winapi) BOOL;

pub const MF_STRING: UINT = 0x00000000;
pub const MF_CHECKED: UINT = 0x00000008;
pub const MF_SEPARATOR: UINT = 0x00000800;
pub const TPM_BOTTOMALIGN: UINT = 0x0020;
pub const TPM_LEFTALIGN: UINT = 0x0000;

// DPI
pub extern "user32" fn SetProcessDpiAwarenessContext(value: isize) callconv(.winapi) BOOL;

// Helper: convert RGB to COLORREF (BGR)
pub fn rgb(r: u8, g: u8, b: u8) COLORREF {
    return @as(DWORD, r) | (@as(DWORD, g) << 8) | (@as(DWORD, b) << 16);
}
