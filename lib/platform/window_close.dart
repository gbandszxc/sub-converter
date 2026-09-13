import 'package:window_manager/window_manager.dart';

/// Bridges to the `window_manager` plugin for the one thing this app needs
/// from the OS window: a chance to ask before the user closes it.
///
/// Like `SystemFonts`, this is the only Dart file allowed to talk to a window
/// plugin, and every call degrades instead of throwing: widget tests (no
/// plugin registered) and hosts without window support simply keep the
/// default close behavior.
class WindowCloseChannel with WindowListener {
  WindowCloseChannel();

  void Function()? _onUserCloseRequested;
  bool _listening = false;

  /// Marks the window close as interceptable and calls [handler] whenever
  /// the user asks the window to close (title bar X, Alt+F4, ...).
  ///
  /// Returns `false` when the plugin is unavailable, in which case the
  /// window keeps its default close behavior and [handler] never fires.
  Future<bool> interceptClose(void Function() handler) async {
    _onUserCloseRequested = handler;
    try {
      await windowManager.ensureInitialized();
      if (!_listening) {
        windowManager.addListener(this);
        _listening = true;
      }
      await windowManager.setPreventClose(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Performs the close the user confirmed: lifts the guard, then destroys
  /// the window.
  Future<void> closeNow() async {
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      // No plugin: nothing to close, and the host handles its own lifecycle.
    }
  }

  @override
  void onWindowClose() {
    final void Function()? handler = _onUserCloseRequested;
    if (handler != null) {
      handler();
    }
  }
}
