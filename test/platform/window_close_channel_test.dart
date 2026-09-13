import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/platform/window_close.dart';
import 'package:window_manager/window_manager.dart' show WindowListener;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel pluginChannel = MethodChannel('window_manager');

  tearDown(() {
    // Drop the mock so later tests see the real (pluginless) environment.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, null);
  });

  test('without the plugin, the guard degrades and registers nothing', () async {
    final WindowCloseChannel channel = WindowCloseChannel();
    var handlerCalls = 0;

    final bool installed = await channel.interceptClose(() {
      handlerCalls++;
    });

    expect(installed, isFalse);
    expect(channel.isListening, isFalse);
    // Nothing is wired: firing the callback directly must stay inert.
    channel.onWindowClose();
    expect(handlerCalls, isZero);
  });

  test('with the plugin, the guard attaches and forwards close requests', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, (MethodCall call) async {
          return true;
        });
    final WindowCloseChannel channel = WindowCloseChannel();
    var handlerCalls = 0;

    final bool installed = await channel.interceptClose(() {
      handlerCalls++;
    });

    expect(installed, isTrue);
    expect(channel.isListening, isTrue);
    channel.onWindowClose();
    expect(handlerCalls, 1);
  });

  test('detach unregisters and drops the handler', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, (MethodCall call) async {
          return true;
        });
    final WindowCloseChannel channel = WindowCloseChannel();
    var handlerCalls = 0;
    await channel.interceptClose(() {
      handlerCalls++;
    });

    channel.detach();

    expect(channel.isListening, isFalse);
    channel.onWindowClose();
    expect(handlerCalls, isZero);
  });

  test('listener contract stays compatible with WindowListener', () {
    // Guards against the window_manager API drifting away from the mixin
    // this channel relies on.
    expect(WindowCloseChannel(), isA<WindowListener>());
  });
}
