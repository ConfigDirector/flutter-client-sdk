import 'dart:convert';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:flutter/material.dart';

import 'config_director_scope.dart';
import 'config_value.dart';
import 'theme.dart';

/// Shows the configs this app reads, each one watched for changes.
///
/// The keys below are the ones set up in the ConfigDirector sample project.
/// Point the app at your own project and these fall back to the defaults passed
/// to [ConfigValue] until keys with the same names exist.
class FlagsScreen extends StatelessWidget {
  const FlagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Feature Flags',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const _ConnectionStatus(),
          ],
        ),
        const SizedBox(height: 16),
        const _BooleanConfig(
          configKey: 'temporary-feature-flag',
          defaultValue: true,
        ),
        const _BooleanConfig(
          configKey: 'permanent-kill-switch',
          defaultValue: false,
        ),
        const _ScalarConfig<int>(configKey: 'integer-config', defaultValue: 10),
        const _ScalarConfig<String>(
          configKey: 'day-of-the-week-config',
          defaultValue: 'Friday',
        ),
        const _JsonConfig(
          configKey: 'json-value-config',
          defaultValue: <String, dynamic>{},
        ),
      ],
    );
  }
}

/// A config read as a `bool`, shown as an ON/OFF badge.
class _BooleanConfig extends StatelessWidget {
  const _BooleanConfig({required this.configKey, required this.defaultValue});

  final String configKey;
  final bool defaultValue;

  @override
  Widget build(BuildContext context) {
    return ConfigValue<bool>(
      configKey: configKey,
      defaultValue: defaultValue,
      builder: (context, value) => _ConfigCard(
        configKey: configKey,
        dartType: 'bool',
        trailing: _Badge(
          label: value ? 'ON' : 'OFF',
          color: value ? AppTheme.on : AppTheme.off,
        ),
      ),
    );
  }
}

/// A config read as a single value of type [T], shown as-is.
class _ScalarConfig<T extends Object> extends StatelessWidget {
  const _ScalarConfig({required this.configKey, required this.defaultValue});

  final String configKey;
  final T defaultValue;

  @override
  Widget build(BuildContext context) {
    return ConfigValue<T>(
      configKey: configKey,
      defaultValue: defaultValue,
      builder: (context, value) => _ConfigCard(
        configKey: configKey,
        dartType: '$T',
        trailing: _Badge(
          label: '$value',
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// A JSON config, decoded into a map and shown pretty-printed.
class _JsonConfig extends StatelessWidget {
  const _JsonConfig({required this.configKey, required this.defaultValue});

  final String configKey;
  final Map<String, dynamic> defaultValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConfigValue<Map<String, dynamic>>(
      configKey: configKey,
      defaultValue: defaultValue,
      builder: (context, value) => _ConfigCard(
        configKey: configKey,
        dartType: 'Map<String, dynamic>',
        below: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              const JsonEncoder.withIndent('  ').convert(value),
              style: AppTheme.monospace(
                theme.textTheme.bodySmall!,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame every config on this screen is shown in.
class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.configKey,
    required this.dartType,
    this.trailing,
    this.below,
  });

  final String configKey;

  /// The Dart type the config is read as, which is what the default value
  /// passed to `watch` determines.
  final String dartType;

  /// Shown to the right of the key, for values short enough to fit there.
  final Widget? trailing;

  /// Shown underneath the key, for values that need the full width.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          configKey,
                          style: AppTheme.monospace(
                            theme.textTheme.bodyMedium!,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dartType,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              ?below,
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Whether the client has config state yet, driven by the client's ready event.
class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus();

  @override
  Widget build(BuildContext context) {
    final client = ConfigDirectorScope.of(context);
    final theme = Theme.of(context);

    return StreamBuilder<ClientReadyEvent>(
      stream: client.onClientReady,
      builder: (context, snapshot) {
        final ready = client.isReady;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ready ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
              size: 16,
              color: ready ? AppTheme.on : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              ready ? 'Ready' : 'Connecting',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}
