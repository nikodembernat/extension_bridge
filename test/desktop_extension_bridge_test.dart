@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:extension_bridge/extension_bridge.dart';
import 'package:extension_bridge/src/platform/desktop_extension_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ExtensionBridgeDesktop platform;

  setUp(() {
    root = Directory.systemTemp.createTempSync('extension_bridge_test');
    platform = ExtensionBridgeDesktop(rootDirectory: () async => root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('round trips values per app group', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    await platform.setValue(null, 'string', 'text');
    await platform.setValue(null, 'int', 1);
    await platform.setValue(null, 'double', 1.0);
    await platform.setValue(null, 'nan', double.nan);
    await platform.setValue(null, 'bool', false);
    await platform.setValue(null, 'bytes', bytes);
    await platform.setValue('group', 'string', 'grouped');

    final reloaded = ExtensionBridgeDesktop(rootDirectory: () async => root);
    final values = await reloaded.getAllValues(null);
    expect(values['string'], 'text');
    expect(values['int'], isA<int>());
    expect(values['double'], isA<double>().having((it) => it, 'value', 1.0));
    expect(values['nan'], isNaN);
    expect(values['bool'], isFalse);
    expect(values['bytes'], bytes);
    expect(await reloaded.getValue('group', 'string'), 'grouped');
  });

  test('serializes concurrent writes', () async {
    await Future.wait([
      for (var index = 0; index < 50; index++)
        platform.setValue(null, 'key$index', index),
    ]);
    expect(await platform.getAllValues(null), hasLength(50));

    await platform.removeValue(null, 'key0');
    expect(await platform.getValue(null, 'key0'), isNull);

    await platform.clearValues(null);
    expect(await platform.getAllValues(null), isEmpty);
  });

  test('ignores a corrupted storage file', () async {
    await platform.setValue(null, 'key', 1);
    File('${root.path}/default/storage.json').writeAsStringSync('{oops');
    expect(await platform.getAllValues(null), isEmpty);
  });

  test('creates a files directory per app group', () async {
    final directory = await platform.getFilesDirectory('group');
    expect(directory, '${root.path}/group/files');
    expect(Directory(directory!).existsSync(), isTrue);
  });

  test('reports native only features as unsupported', () async {
    final unsupported = throwsA(
      isA<ExtensionBridgeException>().having(
        (it) => it.code,
        'code',
        ExtensionBridgeException.unsupported,
      ),
    );
    await expectLater(platform.invokeFeature('a', 'b', null), unsupported);
    await expectLater(
      platform.featureEvents('a', 'b', null).first,
      unsupported,
    );
    await expectLater(
      platform.registerBackgroundCallback(
        dispatcherHandle: 1,
        callbackHandle: 2,
      ),
      unsupported,
    );
    expect(await platform.isBackgroundExecutionSupported(), isFalse);
    expect(await platform.getInitialLink(), isNull);
    expect(await platform.links.isEmpty, isTrue);
  });

  test('backs SharedFiles', () async {
    final files = await platform.getFilesDirectory(null);
    expect(files, isNotNull);
  });
}
