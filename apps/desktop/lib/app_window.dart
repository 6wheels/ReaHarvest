import 'package:window_manager/window_manager.dart';

/// The native window of the application, looked up on first use: by main(),
/// before the tray icon adds a window of its own to the process. Found while
/// still hidden (the runner shows it with its first frame). Null where there
/// is none, as in widget tests.
final Window? appWindow = _lookUp();

Window? _lookUp() {
  try {
    return WindowManager.instance.getCurrent();
  } on ArgumentError {
    // The native library is not loaded (a test process without it): its
    // symbols cannot be looked up. The test hosts used here load it.
    return null; // coverage:ignore-line
  }
}
