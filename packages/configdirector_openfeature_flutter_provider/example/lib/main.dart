import 'dart:async';

import 'package:configdirector_openfeature_flutter_provider/configdirector_openfeature_flutter_provider.dart';
import 'package:flutter/material.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

const String sdkKey = String.fromEnvironment('CONFIGDIRECTOR_SDK_KEY');
const String userId = String.fromEnvironment('CONFIGDIRECTOR_USER_ID');

void main() {
  runApp(
    SampleApp(
      provider: sdkKey.isEmpty
          ? null
          : ConfigDirectorProvider(clientSdkKey: sdkKey),
      context: userId.isEmpty
          ? EvaluationContext.empty
          : EvaluationContext(targetingKey: userId),
    ),
  );
}

class SampleApp extends StatefulWidget {
  const SampleApp({required this.provider, required this.context, super.key});

  final FeatureProvider? provider;
  final EvaluationContext context;

  @override
  State<SampleApp> createState() => _SampleAppState();
}

class _SampleAppState extends State<SampleApp> {
  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    if (provider != null) {
      unawaited(_register(provider));
    }
  }

  Future<void> _register(FeatureProvider provider) async {
    try {
      await OpenFeatureAPI.instance.setEvaluationContextAndWait(widget.context);
      await OpenFeatureAPI.instance.setProviderAndWait(provider);
    } on OpenFeatureException catch (error) {
      debugPrint('ConfigDirector is not ready yet: ${error.message}');
    }
  }

  @override
  void dispose() {
    unawaited(OpenFeatureAPI.instance.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConfigDirector OpenFeature sample',
      home: widget.provider == null ? const MissingKeyPage() : const HomePage(),
    );
  }
}

class MissingKeyPage extends StatelessWidget {
  const MissingKeyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No client SDK key. Copy env.example.json to env.json, fill in '
            'CONFIGDIRECTOR_SDK_KEY, and run with '
            '--dart-define-from-file=env.json.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final OpenFeatureClient _client = OpenFeatureAPI.instance.getClient();
  final List<ProviderEventSubscription> _handlers = [];

  @override
  void initState() {
    super.initState();
    for (final type in const [
      ProviderEventType.ready,
      ProviderEventType.error,
      ProviderEventType.configurationChanged,
      ProviderEventType.contextChanged,
    ]) {
      _handlers.add(_client.addHandler(type, _rebuild));
    }
  }

  void _rebuild(ProviderEventDetails details) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final handler in _handlers) {
      handler.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final featureFlag = client.getBooleanValue('temporary-feature-flag', false);
    final killSwitch = client.getBooleanValue('permanent-kill-switch', false);
    final integer = client.getIntegerValue('integer-config', 0);
    final dayOfTheWeek = client.getStringValue(
      'day-of-the-week-config',
      'unknown',
    );
    final json = client.getStructureValue('json-value-config', const {});

    return Scaffold(
      appBar: AppBar(title: const Text('ConfigDirector + OpenFeature')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Provider status'),
            subtitle: Text(client.providerStatus.name),
          ),
          ListTile(
            title: const Text('temporary-feature-flag'),
            subtitle: Text('$featureFlag'),
          ),
          ListTile(
            title: const Text('permanent-kill-switch'),
            subtitle: Text('$killSwitch'),
          ),
          ListTile(
            title: const Text('integer-config'),
            subtitle: Text('$integer'),
          ),
          ListTile(
            title: const Text('day-of-the-week-config'),
            subtitle: Text(dayOfTheWeek),
          ),
          ListTile(
            title: const Text('json-value-config'),
            subtitle: Text('$json'),
          ),
        ],
      ),
    );
  }
}
