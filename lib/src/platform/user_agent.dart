// Resolves the user agent reported to ConfigDirector, which targeting rules can
// be written against.
//
// On web this is the browser's user agent string, matching what the JavaScript
// SDKs report. On every other platform it is the platform name — `android`,
// `iOS`, `macOS`, `windows`, `linux`, or `fuchsia`.
export 'user_agent_native.dart'
    if (dart.library.js_interop) 'user_agent_web.dart';
