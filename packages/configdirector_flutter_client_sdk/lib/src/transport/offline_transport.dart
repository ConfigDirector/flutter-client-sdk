import 'dart:async';

import '../client/client_events.dart';
import '../client/connection_plan.dart';
import '../errors.dart';
import '../types.dart';
import 'transport.dart';

const String _offlineEnvironmentId = 'offline';
const String _offlineProjectId = 'offline';

final class OfflineTransport implements Transport {
  OfflineTransport(this._source);

  final OfflineSource _source;
  final StreamController<ConfigSet> _configSets =
      StreamController<ConfigSet>.broadcast(sync: true);

  @override
  Stream<ConfigSet> get configSets => _configSets.stream;

  @override
  Future<ConnectOutcome> connect(
    ConfigDirectorContext context,
    Duration timeout,
    ClientConnectAction action,
  ) async {
    _deliver(
      ConfigSet(
        environmentId: _offlineEnvironmentId,
        projectId: _offlineProjectId,
        configs: _configsOf(_source),
        kind: ConfigSetKind.full,
      ),
    );
    return ConnectOutcome.connected;
  }

  @override
  void close() {}

  @override
  void dispose() => unawaited(_configSets.close());

  void _deliver(ConfigSet configSet) {
    if (!_configSets.isClosed) {
      _configSets.add(configSet);
    }
  }

  static Map<String, ConfigState> _configsOf(OfflineSource source) =>
      switch (source) {
        InCodeDefaultValues() => const {},
        OfflineValues(:final configs) => configs,
        RejectedSource(:final message) =>
          throw ConfigDirectorInitializationException(message),
      };
}
