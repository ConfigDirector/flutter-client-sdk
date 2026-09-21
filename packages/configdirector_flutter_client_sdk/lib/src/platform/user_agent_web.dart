import 'package:web/web.dart' as web;

/// Returns the browser's user agent string.
String? resolveUserAgent() {
  final userAgent = web.window.navigator.userAgent;
  return userAgent.isEmpty ? null : userAgent;
}
