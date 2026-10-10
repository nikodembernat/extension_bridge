import 'package:extension_bridge/extension_bridge.dart';
import 'package:extension_bridge_example/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Platforms backed by a native plugin with the example feature.
final isNative =
    !kIsWeb &&
    const [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ].contains(defaultTargetPlatform);

/// Platforms that can run Dart in the background.
final supportsBackground =
    !kIsWeb &&
    const [
      TargetPlatform.android,
      TargetPlatform.iOS,
    ].contains(defaultTargetPlatform);

const bridge = ExtensionBridge();
const otherGroup = ExtensionBridge(
  appGroup: 'extension_bridge.integration_test',
);
final example = bridge.feature('example');

Matcher throwsBridgeException(String code) => throwsA(
  isA<ExtensionBridgeException>().having((it) => it.code, 'code', code),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await bridge.storage.clear();
    await otherGroup.storage.clear();
  });

  group('storage', () {
    testWidgets('round trips every supported type', (_) async {
      final bytes = Uint8List.fromList([0, 1, 2, 254, 255]);
      await bridge.storage.set('string', 'Hello, extensions! 👋');
      await bridge.storage.set('int', 42);
      await bridge.storage.set('largeInt', 1 << 40);
      await bridge.storage.set('double', 3.25);
      await bridge.storage.set('bool', true);
      await bridge.storage.set('bytes', bytes);

      expect(
        await bridge.storage.get<String>('string'),
        'Hello, extensions! 👋',
      );
      expect(await bridge.storage.get<int>('int'), 42);
      expect(await bridge.storage.get<int>('largeInt'), 1 << 40);
      expect(await bridge.storage.get<double>('double'), 3.25);
      expect(await bridge.storage.get<bool>('bool'), isTrue);
      expect(await bridge.storage.get<Uint8List>('bytes'), bytes);
      expect(await bridge.storage.get<String>('missing'), isNull);
      expect(await bridge.storage.containsKey('int'), isTrue);
      expect(await bridge.storage.containsKey('missing'), isFalse);

      expect(await bridge.storage.getAll(), {
        'string': 'Hello, extensions! 👋',
        'int': 42,
        'largeInt': 1 << 40,
        'double': 3.25,
        'bool': true,
        'bytes': bytes,
      });
    });

    testWidgets('overwrites, removes and clears values', (_) async {
      await bridge.storage.set('key', 'first');
      await bridge.storage.set('key', 2);
      expect(await bridge.storage.get<int>('key'), 2);

      await bridge.storage.set('key', null);
      expect(await bridge.storage.get<int>('key'), isNull);

      await bridge.storage.set('a', 1);
      await bridge.storage.set('b', 2);
      await bridge.storage.remove('a');
      expect(await bridge.storage.getAll(), {'b': 2});

      await bridge.storage.clear();
      expect(await bridge.storage.getAll(), isEmpty);
    });

    testWidgets('stores JSON', (_) async {
      final json = {
        'title': 'Groceries',
        'items': ['milk', 'eggs'],
        'done': false,
        'note': null,
      };
      await bridge.storage.setJson('list', json);
      expect(await bridge.storage.getJson('list'), json);
    });

    testWidgets('rejects values of another type', (_) async {
      await bridge.storage.set('key', 'text');
      await expectLater(
        bridge.storage.get<int>('key'),
        throwsBridgeException(ExtensionBridgeException.typeMismatch),
      );
    });

    testWidgets('keeps app groups apart', (_) async {
      await bridge.storage.set('key', 'default');
      await otherGroup.storage.set('key', 'other');

      expect(await bridge.storage.get<String>('key'), 'default');
      expect(await otherGroup.storage.get<String>('key'), 'other');

      await otherGroup.storage.clear();
      expect(await bridge.storage.get<String>('key'), 'default');
    });

    testWidgets('native code reads values written in Dart', (_) async {
      await bridge.storage.set('string', 'from Dart');
      await bridge.storage.set('int', 7);
      await bridge.storage.set('double', 2.5);
      await bridge.storage.set('bool', true);
      await bridge.storage.set('bytes', Uint8List.fromList([4, 5, 6]));

      Future<Object?> read(String key) =>
          example.invoke<Object?>('readStorage', {'key': key});

      expect(await read('string'), 'from Dart');
      expect(await read('int'), 7);
      expect(await read('double'), 2.5);
      expect(await read('bool'), isTrue);
      expect(await read('bytes'), Uint8List.fromList([4, 5, 6]));
    }, skip: !isNative);

    testWidgets('Dart reads values written by native code', (_) async {
      await example.invoke<void>('writeStorage');

      expect(await bridge.storage.get<String>('native.string'), 'native');
      expect(await bridge.storage.get<int>('native.int'), 7);
      expect(await bridge.storage.get<double>('native.double'), 2.5);
      expect(await bridge.storage.get<bool>('native.bool'), isTrue);
      expect(
        await bridge.storage.get<Uint8List>('native.bytes'),
        Uint8List.fromList([1, 2, 3]),
      );
    }, skip: !isNative);
  });

  group('files', () {
    setUp(() async {
      if (!kIsWeb) {
        await bridge.files.clear();
      }
    });

    testWidgets('writes, reads, lists and deletes files', (_) async {
      final bytes = Uint8List.fromList(List.generate(1024, (it) => it % 256));

      final path = await bridge.files.write('images/avatar.png', bytes);
      expect(path, await bridge.files.pathOf('images/avatar.png'));
      expect(path, startsWith(await bridge.files.directory));

      expect(await bridge.files.read('images/avatar.png'), bytes);
      expect(await bridge.files.exists('images/avatar.png'), isTrue);
      expect(await bridge.files.read('missing.txt'), isNull);

      await bridge.files.write('notes.txt', Uint8List.fromList([1]));
      expect(await bridge.files.list(), ['images/avatar.png', 'notes.txt']);

      expect(await bridge.files.delete('notes.txt'), isTrue);
      expect(await bridge.files.delete('notes.txt'), isFalse);
      expect(await bridge.files.list(), ['images/avatar.png']);

      await bridge.files.clear();
      expect(await bridge.files.list(), isEmpty);
    }, skip: kIsWeb);

    testWidgets('native code reads files written in Dart', (_) async {
      await bridge.files.write('shared.bin', Uint8List.fromList([9, 8, 7]));
      expect(
        await example.invoke<Uint8List>('readFile', {'name': 'shared.bin'}),
        Uint8List.fromList([9, 8, 7]),
      );
    }, skip: !isNative);

    testWidgets('are not available on the web', (_) async {
      await expectLater(
        bridge.files.directory,
        throwsBridgeException(ExtensionBridgeException.unsupported),
      );
    }, skip: !kIsWeb);
  });

  group('features', () {
    testWidgets('invokes native methods', (_) async {
      expect(await example.invoke<String>('platform'), isNotEmpty);

      final arguments = {
        'string': 'text',
        'int': 1,
        'double': 1.5,
        'bool': false,
        'null': null,
        'list': [1, 'two'],
        'map': {'nested': true},
        'bytes': Uint8List.fromList([1, 2]),
      };
      expect(await example.invoke<Object?>('echo', arguments), arguments);
      expect(
        await example.invokeMap<String, Object?>('echo', arguments),
        arguments,
      );
      expect(await example.invokeList<int>('echo', [1, 2, 3]), [1, 2, 3]);
    }, skip: !isNative);

    testWidgets('reports native errors', (_) async {
      await expectLater(
        example.invoke<void>('fail'),
        throwsA(
          isA<ExtensionBridgeException>()
              .having((it) => it.code, 'code', 'example-error')
              .having(
                (it) => it.message,
                'message',
                'Failure requested from Dart.',
              )
              .having((it) => it.details, 'details', {'answer': 42}),
        ),
      );
      await expectLater(
        example.invoke<void>('missing'),
        throwsBridgeException(ExtensionBridgeException.notImplemented),
      );
      await expectLater(
        bridge.feature('missing').invoke<void>('anything'),
        throwsBridgeException(ExtensionBridgeException.featureNotFound),
      );
    }, skip: !isNative);

    testWidgets('streams native events', (_) async {
      expect(await example.events<int>('ticks', {'count': 3}).toList(), [
        0,
        1,
        2,
      ]);

      // Cancelling a subscription stops the native stream.
      expect(await example.events<int>('ticks', {'count': 1000}).first, 0);

      await expectLater(
        example.events<int>('missing').toList(),
        throwsBridgeException(ExtensionBridgeException.notImplemented),
      );
    }, skip: !isNative);

    testWidgets('are not available on Linux, Windows and the web', (_) async {
      await expectLater(
        example.invoke<void>('platform'),
        throwsBridgeException(ExtensionBridgeException.unsupported),
      );
      await expectLater(
        example.events<void>('ticks').toList(),
        throwsBridgeException(ExtensionBridgeException.unsupported),
      );
    }, skip: isNative);
  });

  group('background', () {
    testWidgets('runs the registered callback in a background isolate', (
      _,
    ) async {
      expect(await ExtensionBridge.isBackgroundExecutionSupported, isTrue);
      await ExtensionBridge.registerBackgroundCallback(app.onBackgroundEvent);

      expect(
        await example.invoke<Object?>('dispatchBackground', {
          'name': 'echo',
          'arguments': {'hello': 'background'},
        }),
        {'hello': 'background'},
      );

      await expectLater(
        example.invoke<Object?>('dispatchBackground', {'name': 'unknown'}),
        throwsA(isA<ExtensionBridgeException>()),
      );
    }, skip: !supportsBackground);

    testWidgets('is reported as unavailable elsewhere', (_) async {
      expect(await ExtensionBridge.isBackgroundExecutionSupported, isFalse);
      await expectLater(
        ExtensionBridge.registerBackgroundCallback(app.onBackgroundEvent),
        throwsBridgeException(ExtensionBridgeException.unsupported),
      );
    }, skip: supportsBackground);
  });

  group('links', () {
    testWidgets('delivers extension links opened natively', (_) async {
      final links = <ExtensionLink>[];
      final subscription = ExtensionBridge.links.listen(links.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await example.invoke<void>('openLink', {
        'uri': 'extensionbridge://counter?id=7',
        'source': 'integration_test',
      });

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (links.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(links, [
        ExtensionLink(
          uri: Uri.parse('extensionbridge://counter?id=7'),
          source: 'integration_test',
        ),
      ]);
    }, skip: !isNative);

    testWidgets('has no initial link when launched normally', (_) async {
      expect(await ExtensionBridge.initialLink, isNull);
    });
  });
}
