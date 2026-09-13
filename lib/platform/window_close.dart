import 'package:flutter/foundation.dart';
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

  /// Whether this channel is currently registered as a window listener,
  /// i.e. it actually took over the window close.
  @visibleForTesting
  bool get isListening => _listening;

  /// Marks the window close as interceptable and calls [handler] whenever
  /// the user asks the window to close (title bar X, Alt+F4, ...).
  ///
  /// Returns `false` when the plugin is unavailable, in which case the
  /// window keeps its default close behavior, [handler] never fires, and
  /// nothing is left registered on the plugin singleton.
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
      // The guard never took effect: stop holding this channel (and whatever
      // it captures) on the plugin's global listener list.
      detach();
      return false;
    }
  }

  /// Stops intercepting: unregisters from the plugin and drops the handler.
  ///
  /// Safe to call when never attached. Called when the guard install fails
  /// and when the owning widget state is disposed.
  void detach() {
    if (_listening) {
      windowManager.removeListener(this);
      _listening = false;
    }
    _onUserCloseRequested = null;
  }

  /// Performs the close the user confirmed: lifts the guard, then closes the
  /// window.
  ///
  /// `close()` and not `destroy()`: the native WM_CLOSE destroys the window
  /// and shuts the engine down while the message loop is still pumping, which
  /// exits in well under a second. `destroy()` only posts WM_QUIT, leaving
  /// the engine/window teardown to run without a message pump, which keeps
  /// the window visible and frozen for several seconds.
  Future<void> closeNow() async {
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
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
