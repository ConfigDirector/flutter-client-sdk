import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart'
    show ConfigDirectorValidationException;
import 'package:configdirector_openfeature_flutter_provider/configdirector_openfeature_flutter_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';

void main() {
  late OpenFeatureAPI api;

  setUp(() {
    api = createIsolatedOpenFeatureAPI(
      lifecycleTimeout: const Duration(seconds: 2),
    );
  });

  tearDown(() => api.shutdown());

  test('serves offline values to OpenFeature clients without a client SDK '
      'key', () async {
    final provider = ConfigDirectorProvider(
      options: const ConfigDirectorClientOptions(
        connection: ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': true, 'max-items': 20},
        ),
      ),
    );

    await api.setProviderAndWait(provider);

    final client = api.getClient();
    expect(client.providerStatus, ProviderStatus.ready);
    expect(client.getBooleanValue('new-checkout', false), isTrue);
    expect(client.getIntegerValue('max-items', 0), 20);
    expect(
      client.getBooleanDetails('new-checkout', false).reason,
      'TARGETING_MATCH',
    );
  });

  test('fails registration with the initialization exception when an offline '
      'value is refused', () async {
    final provider = ConfigDirectorProvider(
      options: const ConfigDirectorClientOptions(
        connection: ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': null},
        ),
      ),
    );

    await expectLater(
      api.setProviderAndWait(provider),
      throwsA(isA<ConfigDirectorInitializationException>()),
    );

    expect(api.getClient().providerStatus, ProviderStatus.notReady);
  });

  test('still requires a client SDK key outside offline mode', () {
    expect(
      () => ConfigDirectorProvider(),
      throwsA(isA<ConfigDirectorValidationException>()),
    );
  });
}
