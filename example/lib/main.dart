import 'package:flutter/material.dart';

import 'src/app.dart';

/// The client SDK key, supplied at build time so it does not have to be
/// committed:
///
/// ```sh
/// flutter run --dart-define-from-file=env.json
/// ```
///
/// See `env.example.json` and the README for the setup.
const String sdkKey = String.fromEnvironment('CONFIGDIRECTOR_SDK_KEY');

void main() {
  runApp(const SampleApp(sdkKey: sdkKey));
}
