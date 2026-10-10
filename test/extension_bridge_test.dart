import 'package:extension_bridge/extension_bridge.dart';
import 'package:extension_bridge/extension_bridge_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

@pragma('vm:entry-point')
Object? backgroundCallback(BackgroundEvent event) => event.arguments;

void main() {
  late FakeExtensionBridgePlatform platform;
  const bridge = ExtensionBridge(appGroup: 'group.test');

  setUp(() {
    platform = FakeExtensionBridgePlatform();
    ExtensionBridgePlatform.instance = platform;
  });

  test('instances with the same app group are equal', () {
    expect(bridge, const ExtensionBridge(appGroup: 'group.test'));
    expect(bridge, isNot(const ExtensionBridge()));
    expect(bridge.storage.appGroup, 'group.test');
    expect(bridge.files.appGroup, 'group.test');
    expect(bridge.feature('widgets').name, 'widgets');
  });

  group('storage', () {
    test('stores supported values per app group', () async {
      await bridge.storage.set('string', 'text');
      await bridge.storage.set('bytes', Uint8List(2));
      await const ExtensionBridge().storage.set('string', 'other');

      expect(await bridge.storage.get<String>('string'), 'text');
      expect(await bridge.storage.get<Uint8List>('bytes'), Uint8List(2));
      expect(platform.values[null], {'string': 'other'});
    });

    test('rejects unsupported values and empty keys', () {
      expect(() => bridge.storage.set('list', [1]), throwsArgumentError);
      expect(() => bridge.storage.set('', 1), throwsArgumentError);
    });

    test('removes keys set to null', () async {
      await bridge.storage.set('key', 1);
      await bridge.storage.set('key', null);
      expect(await bridge.storage.containsKey('key'), isFalse);
    });

    test('reports type mismatches', () async {
      await bridge.storage.set('key', 'text');
      await expectLater(
        bridge.storage.get<int>('key'),
        throwsA(
          isA<ExtensionBridgeException>().having(
            (it) => it.code,
            'code',
            ExtensionBridgeException.typeMismatch,
          ),
        ),
      );
    });

    test('widens integers read as doubles', () async {
      await bridge.storage.set('key', 2);
      expect(await bridge.storage.get<double>('key'), 2.0);
    });

    test('encodes JSON', () async {
      await bridge.storage.setJson('json', {
        'a': [1, null],
      });
      expect(platform.values['group.test']!['json'], '{"a":[1,null]}');
      expect(await bridge.storage.getJson('json'), {
        'a': [1, null],
      });
      await bridge.storage.setJson('json', null);
      expect(await bridge.storage.getJson('json'), isNull);
    });
  });

  group('files', () {
    test('reports unsupported platforms', () async {
      await expectLater(
        bridge.files.directory,
        throwsA(isA<ExtensionBridgeException>()),
      );
    });

    test('validates names', () async {
      platform.filesDirectory = '/shared';
      expect(await bridge.files.pathOf('a/b.png'), '/shared/a/b.png');
      expect(await bridge.files.pathOf(r'a\b.png'), '/shared/a/b.png');
      for (final name in ['', '/etc/passwd', '../escape', 'a//b', 'a/./b']) {
        await expectLater(
          bridge.files.pathOf(name),
          throwsArgumentError,
          reason: name,
        );
      }
    });
  });

  group('features', () {
    test('forwards calls and events', () async {
      final feature = bridge.feature('widgets');
      expect(await feature.invoke<List<Object?>>('reload', 1), [
        'widgets',
        'reload',
        1,
      ]);
      expect(await feature.invokeList<Object?>('reload'), [
        'widgets',
        'reload',
        null,
      ]);
      expect(await feature.events<Object?>('changes', 2).toList(), [
        'widgets',
        'changes',
        2,
      ]);
    });
  });

  group('links', () {
    test('parses the initial link', () async {
      expect(await ExtensionBridge.initialLink, isNull);
      platform.initialLink = 'myapp://a?extension_bridge=widget';
      expect(
        await ExtensionBridge.initialLink,
        ExtensionLink(uri: Uri.parse('myapp://a'), source: 'widget'),
      );
    });

    test('parses incoming links', () async {
      final links = ExtensionBridge.links.first;
      platform.linkController.add('myapp://b?extension_bridge=');
      expect(await links, ExtensionLink(uri: Uri.parse('myapp://b')));
    });
  });

  group('background', skip: kIsWeb, () {
    test('registers callback handles', () async {
      expect(await ExtensionBridge.isBackgroundExecutionSupported, isTrue);
      await ExtensionBridge.registerBackgroundCallback(backgroundCallback);
      expect(platform.backgroundHandles, isNotNull);
    });

    test('rejects closures', () async {
      await expectLater(
        ExtensionBridge.registerBackgroundCallback((event) => null),
        throwsArgumentError,
      );
    });
  });

  test(
    'background execution is unsupported on the web',
    testOn: 'browser',
    () async {
      await expectLater(
        ExtensionBridge.registerBackgroundCallback(backgroundCallback),
        throwsA(isA<ExtensionBridgeException>()),
      );
    },
  );
}
