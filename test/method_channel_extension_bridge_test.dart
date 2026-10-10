@TestOn('vm')
library;

import 'dart:async';

import 'package:extension_bridge/extension_bridge.dart';
import 'package:extension_bridge/extension_bridge_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MethodChannelExtensionBridge.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelExtensionBridge platform;
  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall call)> responses;

  /// Sends [method] from "native code" to Dart.
  Future<void> sendFromNative(String method, Object? arguments) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
  }

  setUp(() {
    platform = MethodChannelExtensionBridge();
    calls = [];
    responses = {};
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return responses[call.method]?.call(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends storage calls with the app group', () async {
    responses['storage.get'] = (_) => 42;
    responses['storage.getAll'] = (_) => {'a': 1, 'nullValue': null};

    expect(await platform.getValue('group', 'key'), 42);
    expect(await platform.getAllValues(null), {'a': 1});
    await platform.setValue('group', 'key', 'value');
    await platform.removeValue('group', 'key');
    await platform.clearValues('group');

    expect(calls.map((it) => [it.method, it.arguments]), [
      [
        'storage.get',
        {'appGroup': 'group', 'key': 'key'},
      ],
      [
        'storage.getAll',
        {'appGroup': null},
      ],
      [
        'storage.set',
        {'appGroup': 'group', 'key': 'key', 'value': 'value'},
      ],
      [
        'storage.remove',
        {'appGroup': 'group', 'key': 'key'},
      ],
      [
        'storage.clear',
        {'appGroup': 'group'},
      ],
    ]);
  });

  test('converts native errors', () async {
    responses['feature.invoke'] = (_) =>
        throw PlatformException(code: 'boom', message: 'Boom', details: 1);

    await expectLater(
      platform.invokeFeature('a', 'b', null),
      throwsA(
        isA<ExtensionBridgeException>()
            .having((it) => it.code, 'code', 'boom')
            .having((it) => it.message, 'message', 'Boom')
            .having((it) => it.details, 'details', 1),
      ),
    );
  });

  test('reports a missing plugin as unsupported', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      platform.getValue(null, 'key'),
      throwsA(
        isA<ExtensionBridgeException>().having(
          (it) => it.code,
          'code',
          ExtensionBridgeException.unsupported,
        ),
      ),
    );
  });

  test('multiplexes feature event streams', () async {
    final first = <Object?>[];
    final second = <Object?>[];
    final firstDone = Completer<void>();
    final errors = <Object>[];

    platform
        .featureEvents('widgets', 'changes', {'a': 1})
        .listen(first.add, onDone: firstDone.complete);
    final secondSubscription = platform
        .featureEvents('widgets', 'other', null)
        .listen(second.add, onError: errors.add);
    await pumpEventQueue();

    expect(calls.map((it) => it.method), [
      'reset',
      'feature.listen',
      'feature.listen',
    ]);
    final firstId = (calls[1].arguments as Map)['id'];
    final secondId = (calls[2].arguments as Map)['id'];
    expect(calls[1].arguments, {
      'id': firstId,
      'feature': 'widgets',
      'stream': 'changes',
      'arguments': {'a': 1},
    });

    await sendFromNative('feature.onEvent', {'id': firstId, 'event': 'x'});
    await sendFromNative('feature.onEvent', {'id': secondId, 'event': 'y'});
    await sendFromNative('feature.onError', {
      'id': secondId,
      'code': 'oops',
      'message': null,
      'details': null,
    });
    await sendFromNative('feature.onDone', {'id': firstId});
    await firstDone.future;

    expect(first, ['x']);
    expect(second, ['y']);
    expect(errors.single, isA<ExtensionBridgeException>());

    await secondSubscription.cancel();
    expect(calls.last.method, 'feature.cancel');
    expect(calls.last.arguments, {'id': secondId});
  });

  test('fails a stream the native side refuses', () async {
    responses['feature.listen'] = (_) =>
        throw PlatformException(code: 'not-implemented');
    await expectLater(
      platform.featureEvents('widgets', 'missing', null).toList(),
      throwsA(isA<ExtensionBridgeException>()),
    );
  });

  test('delivers links once listened to', () async {
    responses['links.initial'] = (_) => 'myapp://initial';
    expect(await platform.getInitialLink(), 'myapp://initial');

    final links = <String>[];
    final subscription = platform.links.listen(links.add);
    await pumpEventQueue();
    expect(calls.map((it) => it.method), contains('links.listen'));

    await sendFromNative('links.onLink', 'myapp://next');
    expect(links, ['myapp://next']);

    await subscription.cancel();
    expect(calls.last.method, 'links.cancel');
  });

  test('registers background handles', () async {
    responses['background.isSupported'] = (_) => true;
    expect(await platform.isBackgroundExecutionSupported(), isTrue);

    await platform.registerBackgroundCallback(
      dispatcherHandle: 1,
      callbackHandle: 2,
    );
    expect(calls.last.arguments, {'dispatcher': 1, 'callback': 2});
  });

  test('returns the files directory', () async {
    responses['files.directory'] = (_) => '/shared';
    expect(await platform.getFilesDirectory('group'), '/shared');
  });
}
