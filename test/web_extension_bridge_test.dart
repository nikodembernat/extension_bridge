@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:extension_bridge/extension_bridge.dart';
import 'package:extension_bridge/src/platform/web_extension_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  late ExtensionBridgeWeb platform;

  setUp(() {
    web.window.localStorage.clear();
    platform = ExtensionBridgeWeb();
  });

  test('round trips values per app group', () async {
    await platform.setValue(null, 'string', 'text');
    await platform.setValue(null, 'int', 1);
    await platform.setValue(null, 'double', 1.5);
    await platform.setValue(null, 'bool', true);
    await platform.setValue(null, 'bytes', Uint8List.fromList([1, 2]));
    await platform.setValue('group', 'string', 'grouped');
    web.window.localStorage.setItem('unrelated', 'value');

    expect(await platform.getAllValues(null), {
      'string': 'text',
      'int': 1,
      'double': 1.5,
      'bool': true,
      'bytes': Uint8List.fromList([1, 2]),
    });
    expect(await platform.getValue('group', 'string'), 'grouped');

    await platform.clearValues(null);
    expect(await platform.getAllValues(null), isEmpty);
    expect(await platform.getValue('group', 'string'), 'grouped');
    expect(web.window.localStorage.getItem('unrelated'), 'value');
  });

  test('ignores corrupted entries', () async {
    web.window.localStorage.setItem('extension_bridge/default/bad', '{oops');
    expect(await platform.getValue(null, 'bad'), isNull);
    expect(await platform.getAllValues(null), isEmpty);
  });

  test('has no files, features or background execution', () async {
    expect(await platform.getFilesDirectory(null), isNull);
    await expectLater(
      platform.invokeFeature('a', 'b', null),
      throwsA(isA<ExtensionBridgeException>()),
    );
    expect(await platform.isBackgroundExecutionSupported(), isFalse);
  });
}
