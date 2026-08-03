// Builds the [EventReporter] the telemetry collector flushes into.
//
// Everywhere isolates exist, reports are prepared and sent from a background
// isolate so that the main one is left alone. The web has no isolates, and a
// package cannot ship a web worker of its own, so there reports are prepared on
// the main thread; they are still built off the render path, one batch every
// flush interval, rather than while a config is being evaluated.
export 'reporter_factory_native.dart'
    if (dart.library.js_interop) 'reporter_factory_web.dart';
