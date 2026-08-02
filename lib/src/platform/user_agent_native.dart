import 'package:flutter/foundation.dart';

/// Returns the platform name, such as `android` or `iOS`.
///
/// [defaultTargetPlatform] is used rather than `dart:io`'s `Platform` so that
/// this file stays free of `dart:io`, and so that a test can override the value
/// through `debugDefaultTargetPlatformOverride`.
String? resolveUserAgent() => defaultTargetPlatform.name;
