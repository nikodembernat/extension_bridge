import 'dart:convert';
import 'dart:typed_data';

// Encodes storage values as JSON for platforms that keep them in text form
// (web `localStorage` and the JSON file used on Linux and Windows).
//
// Every value is wrapped with its type so `int` and `double` as well as
// `String` and `Uint8List` survive the round trip unchanged.

/// Wraps [value] in a JSON compatible envelope.
Map<String, Object> encodeStoredValue(Object value) => switch (value) {
  bool() => {'type': 'bool', 'value': value},
  int() => {'type': 'int', 'value': value},
  double() => {'type': 'double', 'value': value.toString()},
  String() => {'type': 'string', 'value': value},
  Uint8List() => {'type': 'bytes', 'value': base64Encode(value)},
  _ => throw ArgumentError.value(value, 'value', 'Unsupported type'),
};

/// Unwraps a value produced by [encodeStoredValue].
///
/// Returns `null` for envelopes it does not understand.
Object? decodeStoredValue(Object? envelope) {
  if (envelope case {'type': final String type, 'value': final Object raw}) {
    return switch ((type, raw)) {
      ('bool', final bool value) => value,
      ('int', final int value) => value,
      ('double', final String value) => double.tryParse(value),
      ('string', final String value) => value,
      ('bytes', final String value) => base64Decode(value),
      _ => null,
    };
  }
  return null;
}

/// Encodes a whole storage map as a JSON string.
String encodeStoredValues(Map<String, Object> values) => jsonEncode(
  values.map((key, value) => MapEntry(key, encodeStoredValue(value))),
);

/// Decodes a JSON string produced by [encodeStoredValues].
///
/// Entries it does not understand are skipped.
Map<String, Object> decodeStoredValues(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?>) {
    return {};
  }
  return {
    for (final MapEntry(:key, :value) in decoded.entries)
      if (decodeStoredValue(value) case final Object value) key: value,
  };
}
