// Sample app for the ConfigDirector Flutter client SDK: it reads a few configs
// and re-renders as their values change.
//
//   flutter run --dart-define-from-file=env.json

import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:flutter/material.dart';

// Supplied at build time so the key does not have to be committed. See
// env.example.json.
const String sdkKey = String.fromEnvironment('CONFIGDIRECTOR_SDK_KEY');

void main() => runApp(const SampleApp(sdkKey: sdkKey));

// Owns the client: one instance for the life of the app.
class SampleApp extends StatefulWidget {
  const SampleApp({required this.sdkKey, super.key});

  final String sdkKey;

  @override
  State<SampleApp> createState() => _SampleAppState();
}

class _SampleAppState extends State<SampleApp> {
  ConfigDirectorClient? _client;

  @override
  void initState() {
    super.initState();
    if (widget.sdkKey.isEmpty) {
      return;
    }

    final client = ConfigDirectorClient(
      clientSdkKey: widget.sdkKey,
      // The SDK logs at `warn` by default; turned up here so the connection can
      // be followed in the console.
      options: ConfigDirectorClientOptions(
        logger: ConsoleLogger(level: ConfigDirectorLogLevel.debug),
      ),
    );
    _client = client;

    // Configs return their defaults until this completes, so there is nothing
    // to wait for before building the UI.
    unawaited(client.initialize(_contextFromEnvironment()));
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;

    return MaterialApp(
      title: 'ConfigDirector Flutter Sample',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0EA5E9)),
      ),
      home: client == null
          ? const _MissingSdkKey()
          : ConfigDirectorScope(client: client, child: const HomePage()),
    );
  }
}

// The context targeting rules are evaluated against. Call `updateContext` to
// change it while the app is running.
ConfigDirectorContext _contextFromEnvironment() {
  const id = String.fromEnvironment('CONFIGDIRECTOR_USER_ID');
  const name = String.fromEnvironment('CONFIGDIRECTOR_USER_NAME');
  const role = String.fromEnvironment('CONFIGDIRECTOR_USER_ROLE');

  return ConfigDirectorContext(
    id: id.isEmpty ? null : id,
    name: name.isEmpty ? null : name,
    traits: role.isEmpty ? null : {'role': role},
  );
}

// Hands the client to the widgets below it: `ConfigDirectorScope.of(context)`.
class ConfigDirectorScope extends InheritedWidget {
  const ConfigDirectorScope({
    required this.client,
    required super.child,
    super.key,
  });

  final ConfigDirectorClient client;

  static ConfigDirectorClient of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ConfigDirectorScope>();
    assert(scope != null, 'No ConfigDirectorScope found above this widget.');
    return scope!.client;
  }

  @override
  bool updateShouldNotify(ConfigDirectorScope oldWidget) =>
      client != oldWidget.client;
}

// Builds from the current value of a config and rebuilds whenever it changes,
// whether from an edit in the dashboard or a context update.
class ConfigValue<T extends Object> extends StatefulWidget {
  const ConfigValue({
    required this.configKey,
    required this.defaultValue,
    required this.builder,
    super.key,
  });

  final String configKey;

  // Determines `T`, and is what gets built until the client is ready.
  final T defaultValue;

  final Widget Function(BuildContext context, T value) builder;

  @override
  State<ConfigValue<T>> createState() => _ConfigValueState<T>();
}

class _ConfigValueState<T extends Object> extends State<ConfigValue<T>> {
  // `watch` hands out a new stream per call, so it is called when the client
  // changes rather than on every build.
  Stream<T>? _values;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _values = ConfigDirectorScope.of(
      context,
    ).watch(widget.configKey, widget.defaultValue);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: _values,
    initialData: widget.defaultValue,
    builder: (context, snapshot) =>
        widget.builder(context, snapshot.data ?? widget.defaultValue),
  );
}

// The keys below are the ones in the ConfigDirector sample project. Against a
// project without them, each config falls back to its default value.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ConfigDirector'),
      actions: const [_ReadyIndicator(), SizedBox(width: 16)],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _Config<bool>('temporary-feature-flag', true),
          _Config<bool>('permanent-kill-switch', false),
          _Config<int>('integer-config', 10),
          _Config<String>('day-of-the-week-config', 'Friday'),
          _Config<Map<String, dynamic>>('json-value-config', {}),
          Divider(height: 40),
          _ActiveContext(),
        ],
      ),
    ),
  );
}

// One config, read as `T` — which is what its default value determines.
class _Config<T extends Object> extends StatelessWidget {
  const _Config(this.configKey, this.defaultValue);

  final String configKey;
  final T defaultValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConfigValue<T>(
      configKey: configKey,
      defaultValue: defaultValue,
      builder: (context, value) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(configKey, style: _mono(theme.textTheme.bodySmall!)),
        subtitle: Text('$value', style: theme.textTheme.titleMedium),
      ),
    );
  }
}

class _ReadyIndicator extends StatelessWidget {
  const _ReadyIndicator();

  @override
  Widget build(BuildContext context) {
    final client = ConfigDirectorScope.of(context);

    return Center(
      child: StreamBuilder<ClientReadyEvent>(
        stream: client.onClientReady,
        builder: (context, snapshot) =>
            Text(client.isReady ? 'Ready' : 'Connecting…'),
      ),
    );
  }
}

// The context the configs above were evaluated against.
class _ActiveContext extends StatelessWidget {
  const _ActiveContext();

  @override
  Widget build(BuildContext context) {
    final active = ConfigDirectorScope.of(context).context;
    final theme = Theme.of(context);

    return Text(
      active == null
          ? 'No context — configs are evaluated without one.'
          : 'Context\n'
                'id: ${active.id ?? '—'}\n'
                'name: ${active.name ?? '—'}\n'
                'traits: ${active.traits ?? '—'}',
      style: _mono(theme.textTheme.bodySmall!),
    );
  }
}

class _MissingSdkKey extends StatelessWidget {
  const _MissingSdkKey();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No client SDK key. Copy env.example.json to env.json, put your '
          'client SDK key in it, and run:\n\n'
          'flutter run --dart-define-from-file=env.json',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

// The family names differ per platform, so the fallbacks cover the ones the
// sample runs on.
TextStyle _mono(TextStyle style) => style.copyWith(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
);
