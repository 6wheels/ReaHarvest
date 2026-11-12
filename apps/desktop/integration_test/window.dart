import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

// Win32 functions, found among the modules of the app process.

@Native<IntPtr Function(IntPtr, IntPtr, Pointer<Uint16>, Pointer<Uint16>)>(
  symbol: 'FindWindowExW',
  isLeaf: true,
)
external int _findWindowEx(
  int parent,
  int after,
  Pointer<Uint16> className,
  Pointer<Uint16> title,
);

@Native<Uint32 Function(IntPtr, Pointer<Uint32>)>(
  symbol: 'GetWindowThreadProcessId',
  isLeaf: true,
)
external int _windowProcess(int hwnd, Pointer<Uint32> process);

@Native<Uint32 Function()>(symbol: 'GetCurrentProcessId', isLeaf: true)
external int _currentProcess();

@Native<Int32 Function(IntPtr, Pointer<Int32>)>(
  symbol: 'GetWindowRect',
  isLeaf: true,
)
external int _windowRect(int hwnd, Pointer<Int32> rect);

@Native<Int32 Function(IntPtr, Pointer<Int32>)>(
  symbol: 'GetClientRect',
  isLeaf: true,
)
external int _clientRect(int hwnd, Pointer<Int32> rect);

// Not a leaf call: the window procedure runs during the resize.
@Native<Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32)>(
  symbol: 'SetWindowPos',
)
external int _setWindowPos(
  int hwnd,
  int after,
  int x,
  int y,
  int width,
  int height,
  int flags,
);

const _noMove = 0x0002;
const _noZOrder = 0x0004;
const _noActivate = 0x0010;

/// Main window of this process, created by the Windows runner; 0 if none.
int _appWindow() {
  final name = Uint16List.fromList([
    ...'FLUTTER_RUNNER_WIN32_WINDOW'.codeUnits,
    0,
  ]);
  final process = Uint32List(1);
  final me = _currentProcess();
  var hwnd = 0;
  while (true) {
    hwnd = _findWindowEx(0, hwnd, name.address, nullptr);
    if (hwnd == 0) return 0;
    _windowProcess(hwnd, process.address);
    if (process[0] == me) return hwnd;
  }
}

/// Resizes the native window of the app so that its client area is
/// [size] physical pixels, frame kept. Returns false when there is no such
/// window (not on Windows) or the resize was refused.
bool resizeAppWindow(Size size) {
  if (!Platform.isWindows) return false;
  final hwnd = _appWindow();
  if (hwnd == 0) return false;
  // RECT: left, top, right, bottom.
  final outer = Int32List(4);
  final client = Int32List(4);
  if (_windowRect(hwnd, outer.address) == 0 ||
      _clientRect(hwnd, client.address) == 0) {
    return false;
  }
  final frameWidth = (outer[2] - outer[0]) - (client[2] - client[0]);
  final frameHeight = (outer[3] - outer[1]) - (client[3] - client[1]);
  return _setWindowPos(
        hwnd,
        0,
        0,
        0,
        size.width.round() + frameWidth,
        size.height.round() + frameHeight,
        _noMove | _noZOrder | _noActivate,
      ) !=
      0;
}
