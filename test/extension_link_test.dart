import 'package:extension_bridge/extension_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExtensionLink.parse', () {
    test('removes the marker and exposes the source', () {
      final link = ExtensionLink.parse(
        'myapp://counter/details?id=7&extension_bridge=widget',
      );
      expect(link.uri, Uri.parse('myapp://counter/details?id=7'));
      expect(link.source, 'widget');
    });

    test('drops the query when the marker was its only parameter', () {
      final link = ExtensionLink.parse('myapp://open?extension_bridge=');
      expect(link.uri.toString(), 'myapp://open');
      expect(link.source, isNull);
    });

    test('keeps repeated parameters and fragments', () {
      final link = ExtensionLink.parse(
        'https://example.com/a?tag=x&tag=y&extension_bridge=share#top',
      );
      expect(link.uri.queryParametersAll, {
        'tag': ['x', 'y'],
      });
      expect(link.uri.fragment, 'top');
      expect(link.uri.host, 'example.com');
      expect(link.source, 'share');
    });

    test('has value semantics', () {
      expect(
        ExtensionLink.parse('myapp://a?extension_bridge=w'),
        ExtensionLink(uri: Uri.parse('myapp://a'), source: 'w'),
      );
    });
  });
}
