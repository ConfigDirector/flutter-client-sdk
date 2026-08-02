import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:flutter/material.dart';

import 'config_director_scope.dart';
import 'context_screen.dart';
import 'flags_screen.dart';
import 'theme.dart';

/// The sample app's root widget.
///
/// It owns the [ConfigDirectorClient]: one instance is created for the life of
/// the app, initialized on startup, and disposed on shutdown. Everything below
/// reaches it through [ConfigDirectorScope].
class SampleApp extends StatefulWidget {
  const SampleApp({required this.sdkKey, super.key});

  /// The client SDK key from the ConfigDirector dashboard.
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
      options: ConfigDirectorClientOptions(
        // The SDK logs at `warn` by default; the sample turns it all the way up
        // so the connection can be followed in the console.
        logger: ConsoleLogger(level: ConfigDirectorLogLevel.debug),
      ),
    );
    _client = client;

    // Configs return their default values until this completes, so there is
    // nothing to wait for before building the UI.
    unawaited(client.initialize());
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
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: client == null
          ? const _MissingSdkKeyPage()
          : ConfigDirectorScope(client: client, child: const _HomePage()),
    );
  }
}

/// The two tabs of the sample: the configs it reads, and the context it
/// evaluates them against.
class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const _Wordmark()),
      // An IndexedStack keeps both tabs alive, so the context tab does not lose
      // what was typed into it while the flags tab is on screen.
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: const [FlagsScreen(), ContextScreen()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Flags',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Context',
          ),
        ],
      ),
    );
  }
}

/// The ConfigDirector wordmark, in the two colors of the logo.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Config',
            style: style?.copyWith(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.onSurface
                  : AppTheme.brandDeep,
            ),
          ),
          TextSpan(
            text: 'Director',
            style: style?.copyWith(color: AppTheme.brandBright),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the app when no SDK key was supplied at build time, since
/// the client cannot be created without one.
class _MissingSdkKeyPage extends StatelessWidget {
  const _MissingSdkKeyPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const _Wordmark()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.key_off_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No client SDK key',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Copy env.example.json to env.json, put your client SDK key in '
                'it, and run:\n\n'
                'flutter run --dart-define-from-file=env.json',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
