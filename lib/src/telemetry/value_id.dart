import 'dart:convert';

import 'package:crypto/crypto.dart';

/// How many bytes of the digest make up a value id.
const int _digestBytes = 16;

/// The length every value id is padded to: `ceil(128 / log2(62))`, the number
/// of base62 digits [_digestBytes] bytes can produce.
const int _valueIdLength = 22;

const String _base62Alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// Derives the identifier ConfigDirector knows [value] by, so that values too
/// large to report inline can still be counted.
///
/// The same value produces the same id in every ConfigDirector SDK: the first
/// [_digestBytes] bytes of its SHA-256 digest, encoded as base62.
String generateValueId(Object? value) {
  final digest = sha256.convert(utf8.encode(value?.toString() ?? ''));
  return _toBase62(digest.bytes.take(_digestBytes));
}

String _toBase62(Iterable<int> bytes) {
  final base = BigInt.from(_base62Alphabet.length);
  var remaining = bytes.fold(
    BigInt.zero,
    (value, byte) => (value << 8) | BigInt.from(byte),
  );

  final digits = <String>[];
  while (remaining > BigInt.zero) {
    digits.add(_base62Alphabet[(remaining % base).toInt()]);
    remaining = remaining ~/ base;
  }

  return digits.reversed.join().padLeft(_valueIdLength, '0');
}
