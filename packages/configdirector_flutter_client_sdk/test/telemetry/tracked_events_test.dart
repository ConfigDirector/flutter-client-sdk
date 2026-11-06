import 'dart:convert';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/src/client/default_config_director_client.dart';
import 'package:configdirector_flutter_client_sdk/src/client_session.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/event_reporter.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_event_collector.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/tracked_events.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

Matcher causedBy(TrackedEventWarning warning) => startsWith(warning.message);

final class _Plan {
  _Plan(this.name);

  String name;

  Map<String, Object?> toJson() => {'name': name};
}

final class _Rate {
  const _Rate(this.rate);

  final double rate;

  Map<String, Object?> toJson() => {'rate': rate};
}

void main() {
  late RecordingLogger logger;
  late List<http.Request> reports;
  late FakeTransport transport;
  late TelemetryEventCollector telemetry;
  late DefaultConfigDirectorClient client;
  late int nextStatus;

  setUp(() {
    logger = RecordingLogger();
    reports = [];
    nextStatus = 202;
    transport = FakeTransport();
    telemetry = TelemetryEventCollector(
      reporter: HttpEventReporter(
        sdkKey: 'a-client-sdk-key',
        baseUrl: Uri.parse('https://sdk.example.com'),
        logger: logger,
        httpClient: MockClient((request) async {
          reports.add(request);
          return http.Response('', nextStatus);
        }),
      ),
      currentMetaContext: () => const SdkMetaContext(
        sdkName: 'tracked-events-tests',
        sdkVersion: '1.0.0',
      ),
      instanceId: Future.value('instance-id'),
      logger: logger,
    );
    client = DefaultConfigDirectorClient(
      'a-client-sdk-key',
      options: ConfigDirectorClientOptions(
        logger: logger,
        connection: const ConnectionOptions(timeout: Duration(seconds: 3)),
        caching: const CachingOptions(enabled: false),
      ),
      telemetryClient: telemetry,
      transportFactory: (_) => transport,
      lifecycleWatcher: FakeLifecycleWatcher(),
      appInfoResolver: () async => const ConfigDirectorMetaContext(),
      clientSession: ClientSession.provisional(),
    );
  });

  tearDown(() => client.dispose());

  Future<void> connect(ConfigDirectorContext context) async {
    final initialization = client.initialize(context);
    transport.emitConfigSet(configSet(configs: const {}));
    await initialization;
    await telemetry.flush();
    reports.clear();
  }

  List<Object?> trackedEventsIn(http.Request report) =>
      ((jsonDecode(report.body) as Map<String, Object?>)['discreteEvents']!
              as Map<String, Object?>)['trackedEvents']!
          as List<Object?>;

  String rawBodyOf(http.Request report) => utf8.decode(report.bodyBytes);

  test('sends an event tracked for the client\'s context on the next telemetry '
      'batch with its value and details', () async {
    await connect(const ConfigDirectorContext(id: 'user-123'));

    client.track(
      'checkout-completed',
      const TrackOptions(value: 49.9, details: {'plan': 'pro', 'seats': 3}),
    );
    await telemetry.flush();

    expect(reports, hasLength(1));
    expect(trackedEventsIn(reports.single), [
      {
        'name': 'checkout-completed',
        'contextKind': 'user',
        'contextIdentifier': 'user-123',
        'value': 49.9,
        'details': {'plan': 'pro', 'seats': 3},
        'happenedAt': isA<String>(),
      },
    ]);
    expect(logger.warnings, isEmpty);
  });

  group('the context', () {
    test('sends the kind of the client\'s context', () async {
      await connect(
        const ConfigDirectorContext(id: 'device-42', kind: 'device'),
      );

      client.track('firmware-updated');
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'firmware-updated',
          'contextKind': 'device',
          'contextIdentifier': 'device-42',
          'happenedAt': isA<String>(),
        },
      ]);
    });

    test('sends an event tracked before the client has a context with no '
        'context kind or identifier and logs nothing', () async {
      client.track('app-opened');
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'app-opened', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, isEmpty);
      expect(logger.errorMessages, isEmpty);
    });

    test('sends an event tracked for a context without an id with no context '
        'kind or identifier and logs nothing', () async {
      await connect(
        const ConfigDirectorContext(kind: 'device', name: 'Kitchen tablet'),
      );

      client.track('firmware-updated');
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'firmware-updated', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, isEmpty);
      expect(logger.errorMessages, isEmpty);
    });

    test('withholds the identifier of an anonymous context from the event '
        'tracked for it', () async {
      await connect(
        const ConfigDirectorContext(id: 'user-123', anonymous: true),
      );

      client.track('checkout-completed');
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'checkout-completed', 'happenedAt': isA<String>()},
      ]);
    });

    test('sends the identifier of a context marked not anonymous', () async {
      await connect(
        const ConfigDirectorContext(id: 'user-123', anonymous: false),
      );

      client.track('checkout-completed');
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'contextKind': 'user',
          'contextIdentifier': 'user-123',
          'happenedAt': isA<String>(),
        },
      ]);
    });

    test('sends each event for the context the client had when it was '
        'tracked', () async {
      await connect(const ConfigDirectorContext(id: 'user-1'));
      client.track('first');

      final update = client.updateContext(
        const ConfigDirectorContext(id: 'user-2'),
      );
      transport.emitConfigSet(configSet(configs: const {}));
      await update;
      client.track('second');
      await telemetry.flush();

      final entries = [
        for (final report in reports) ...trackedEventsIn(report),
      ];
      expect(entries, [
        {
          'name': 'first',
          'contextKind': 'user',
          'contextIdentifier': 'user-1',
          'happenedAt': isA<String>(),
        },
        {
          'name': 'second',
          'contextKind': 'user',
          'contextIdentifier': 'user-2',
          'happenedAt': isA<String>(),
        },
      ]);
    });

    test('sends an event tracked after a context with an invalid kind was '
        'ignored without a context', () async {
      await connect(
        const ConfigDirectorContext(id: 'device-42', kind: 'Device'),
      );

      client.track('firmware-updated');
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'firmware-updated', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, isEmpty);
    });
  });

  test('stamps an event with the time track was called rather than the time it '
      'was sent', () async {
    final before = DateTime.now();

    client.track('checkout-completed');
    final after = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await telemetry.flush();

    final entry = trackedEventsIn(reports.single).single! as Map;
    final happenedAt = DateTime.parse(entry['happenedAt'] as String);
    expect(happenedAt.isUtc, isTrue);
    expect(happenedAt.isBefore(before), isFalse);
    expect(happenedAt.isAfter(after), isFalse);
  });

  test('reports the events left when the client is disposed', () async {
    client.track('checkout-completed');

    client.dispose();
    await pumpEventQueue();

    expect(trackedEventsIn(reports.single), [
      {'name': 'checkout-completed', 'happenedAt': isA<String>()},
    ]);
  });

  test('sends nothing and logs nothing for an event tracked after the client '
      'was disposed', () async {
    client.dispose();
    await pumpEventQueue();

    client.track('');
    client.track('checkout-completed');
    await pumpEventQueue();

    expect(reports, isEmpty);
    expect(logger.warnings, isEmpty);
  });

  test('sends nothing and logs nothing about an event tracked after '
      'ConfigDirector refused the client SDK key', () async {
    nextStatus = 401;
    client.track('first');
    await telemetry.flush();
    logger.warnings.clear();
    reports.clear();

    client.track('');
    client.track('second');
    await telemetry.flush();

    expect(reports, isEmpty);
    expect(logger.warnings, isEmpty);
  });

  test('keeps reporting tracked events after a report too large for '
      'ConfigDirector', () async {
    nextStatus = 413;
    client.track('refused');
    await telemetry.flush();
    expect(logger.warnings, [contains('413')]);

    nextStatus = 202;
    client.track('the-next-report');
    await telemetry.flush();

    expect(reports, hasLength(2));
    expect(trackedEventsIn(reports.last), [
      {'name': 'the-next-report', 'happenedAt': isA<String>()},
    ]);
  });

  group('the value', () {
    test('sends a double as it was written', () async {
      client.track('checkout-completed', const TrackOptions(value: 49.9));
      await telemetry.flush();

      expect(rawBodyOf(reports.single), contains('"value":49.9,'));
    });

    test('sends a double whose binary form is not exact without rounding '
        'it', () async {
      client.track('checkout-completed', const TrackOptions(value: 0.1));
      await telemetry.flush();

      expect(rawBodyOf(reports.single), contains('"value":0.1,'));
    });

    test('sends a whole number', () async {
      client.track('seats-added', const TrackOptions(value: 3));
      await telemetry.flush();

      expect(rawBodyOf(reports.single), contains('"value":3,'));
    });

    test('sends a value of zero', () async {
      client.track('seats-added', const TrackOptions(value: 0));
      await telemetry.flush();

      expect(rawBodyOf(reports.single), contains('"value":0,'));
    });

    test('sends an integer with more digits than a double holds without '
        'rounding it', () async {
      client.track(
        'bytes-exported',
        TrackOptions(value: int.parse('9007199254740993')),
      );
      await telemetry.flush();

      expect(rawBodyOf(reports.single), contains('"value":9007199254740993,'));
    }, skip: kIsWeb ? 'every number is a double on the web' : false);

    test('leaves out a value that is not a number, sends the event and logs a '
        'warning', () async {
      client.track('checkout-completed', const TrackOptions(value: double.nan));
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'checkout-completed', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.valueNotAFiniteNumber),
      ]);
    });

    test('leaves out an infinite value, sends the event and logs a '
        'warning', () async {
      client.track(
        'checkout-completed',
        const TrackOptions(value: double.infinity),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'checkout-completed', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.valueNotAFiniteNumber),
      ]);
    });
  });

  group('the details', () {
    test('sends details with 20 top-level keys', () async {
      final details = {
        for (var index = 1; index <= 20; index += 1) 'key-$index': index,
      };

      client.track('checkout-completed', TrackOptions(details: details));
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'details': details,
          'happenedAt': isA<String>(),
        },
      ]);
      expect(logger.warnings, isEmpty);
    });

    test('leaves out details with 21 top-level keys, sends the event and logs '
        'a warning', () async {
      final details = {
        for (var index = 1; index <= 21; index += 1) 'key-$index': index,
      };

      client.track(
        'checkout-completed',
        TrackOptions(value: 49.9, details: details),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'value': 49.9,
          'happenedAt': isA<String>(),
        },
      ]);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.detailsNotReportable),
      ]);
    });

    test('sends details of exactly 1,024 bytes as JSON in the same bytes they '
        'were measured in', () async {
      final padding = 'p' * 1016;

      client.track('checkout-completed', TrackOptions(details: {'k': padding}));
      await telemetry.flush();

      expect(
        rawBodyOf(reports.single),
        contains('"details":{"k":"$padding"},'),
      );
      expect(logger.warnings, isEmpty);
    });

    test('leaves out details of 1,025 bytes as JSON, sends the event and logs '
        'a warning', () async {
      client.track(
        'checkout-completed',
        TrackOptions(details: {'k': 'p' * 1017}),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'checkout-completed', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.detailsNotReportable),
      ]);
    });

    test('sends 508 two-byte characters, which are 1,024 bytes as JSON, in '
        'UTF-8 rather than as escape sequences', () async {
      final text = 'é' * 508;

      client.track('checkout-completed', TrackOptions(details: {'k': text}));
      await telemetry.flush();

      expect(rawBodyOf(reports.single), contains('"details":{"k":"$text"},'));
      expect(logger.warnings, isEmpty);
    });

    test('measures details in bytes, so 509 two-byte characters are left '
        'out', () async {
      client.track(
        'checkout-completed',
        TrackOptions(details: {'k': 'é' * 509}),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'checkout-completed', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.detailsNotReportable),
      ]);
    });

    test('writes details without spaces', () async {
      client.track(
        'checkout-completed',
        const TrackOptions(
          details: {
            'plan': 'pro',
            'addons': ['sso', 'audit'],
            'limits': {'seats': 3},
          },
        ),
      );
      await telemetry.flush();

      expect(
        rawBodyOf(reports.single),
        contains(
          '"details":{"plan":"pro","addons":["sso","audit"],'
          '"limits":{"seats":3}},',
        ),
      );
    });

    test('sends empty details given explicitly', () async {
      client.track('checkout-completed', const TrackOptions(details: {}));
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'details': <String, Object?>{},
          'happenedAt': isA<String>(),
        },
      ]);
      expect(logger.warnings, isEmpty);
    });

    test('sends a number that is not finite inside details as null', () async {
      client.track(
        'checkout-completed',
        const TrackOptions(
          details: {
            'rate': double.nan,
            'rates': [double.infinity, 1.5],
          },
        ),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'details': {
            'rate': null,
            'rates': [null, 1.5],
          },
          'happenedAt': isA<String>(),
        },
      ]);
      expect(logger.warnings, isEmpty);
    });

    test('sends a DateTime inside details as ISO 8601 text', () async {
      client.track(
        'checkout-completed',
        TrackOptions(details: {'renewsAt': DateTime.utc(2027, 1, 2, 3, 4, 5)}),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'details': {'renewsAt': '2027-01-02T03:04:05.000Z'},
          'happenedAt': isA<String>(),
        },
      ]);
      expect(logger.warnings, isEmpty);
    });

    test('sends a DateTime in local time inside details in UTC', () async {
      final renewsAt = DateTime(2027, 1, 2, 3, 4, 5);

      client.track(
        'checkout-completed',
        TrackOptions(details: {'renewsAt': renewsAt}),
      );
      await telemetry.flush();

      final entry = trackedEventsIn(reports.single).single! as Map;
      final sent = (entry['details'] as Map)['renewsAt'] as String;
      expect(sent, endsWith('Z'));
      expect(DateTime.parse(sent).isAtSameMomentAs(renewsAt), isTrue);
    });

    test('sends an object inside details as what its toJson method '
        'returns', () async {
      client.track(
        'checkout-completed',
        TrackOptions(details: {'plan': _Plan('pro')}),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'details': {
            'plan': {'name': 'pro'},
          },
          'happenedAt': isA<String>(),
        },
      ]);
    });

    test('sends an object inside details as it was when the event was '
        'tracked', () async {
      final plan = _Plan('pro');

      client.track('checkout-completed', TrackOptions(details: {'plan': plan}));
      plan.name = 'team';
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'details': {
            'plan': {'name': 'pro'},
          },
          'happenedAt': isA<String>(),
        },
      ]);
    });

    test('sends a number that is not finite in what a toJson method returns '
        'as null', () async {
      client.track(
        'checkout-completed',
        const TrackOptions(details: {'exchange': _Rate(double.infinity)}),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'details': {
            'exchange': {'rate': null},
          },
          'happenedAt': isA<String>(),
        },
      ]);
      expect(logger.warnings, isEmpty);
    });

    test('leaves out details holding a value with no JSON form, sends the '
        'event and logs a warning', () async {
      client.track(
        'checkout-completed',
        TrackOptions(details: {'callback': Object()}),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'checkout-completed', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.detailsNotReportable),
      ]);
    });

    test('leaves out details holding a map whose keys are not strings, sends '
        'the event and logs a warning', () async {
      client.track(
        'checkout-completed',
        const TrackOptions(
          details: {
            'limits': {1: 'one seat'},
          },
        ),
      );
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'checkout-completed', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.detailsNotReportable),
      ]);
    });

    test('leaves out details that refer to themselves, sends the event and '
        'logs a warning', () async {
      final details = <String, Object?>{};
      details['self'] = details;

      client.track('checkout-completed', TrackOptions(details: details));
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': 'checkout-completed', 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.detailsNotReportable),
      ]);
    });

    test('sends the details as they were when the event was tracked', () async {
      final details = <String, Object?>{
        'addons': ['sso'],
      };

      client.track('checkout-completed', TrackOptions(details: details));
      (details['addons']! as List<Object?>).add('audit');
      details['plan'] = 'pro';
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {
          'name': 'checkout-completed',
          'details': {
            'addons': ['sso'],
          },
          'happenedAt': isA<String>(),
        },
      ]);
    });
  });

  group('the limit of one batch', () {
    test('sends 1,000 events tracked before a batch is sent', () async {
      for (var index = 1; index <= 1000; index += 1) {
        client.track('event-$index');
      }
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), hasLength(1000));
      expect(logger.warnings, isEmpty);
    });

    test('does not send the 1,001st event tracked before a batch is sent and '
        'logs a warning', () async {
      for (var index = 1; index <= 1001; index += 1) {
        client.track('event-$index');
      }
      await telemetry.flush();

      final entries = trackedEventsIn(reports.single);
      expect(entries, hasLength(1000));
      expect((entries.last! as Map)['name'], 'event-1000');
      expect(logger.warnings, [causedBy(TrackedEventWarning.batchAlreadyFull)]);
    });

    test('logs one warning however many events go beyond the limit of one '
        'batch', () async {
      for (var index = 1; index <= 1005; index += 1) {
        client.track('event-$index');
      }

      expect(logger.warnings, hasLength(1));
    });

    test('logs only the warning about the limit for an event beyond it whose '
        'value would be left out', () async {
      for (var index = 1; index <= 1000; index += 1) {
        client.track('event-$index');
      }

      client.track('event-1001', const TrackOptions(value: double.nan));

      expect(logger.warnings, [causedBy(TrackedEventWarning.batchAlreadyFull)]);
    });

    test('sends events tracked after a full batch was sent on the following '
        'batch', () async {
      for (var index = 1; index <= 1001; index += 1) {
        client.track('event-$index');
      }
      await telemetry.flush();

      client.track('the-next-batch');
      await telemetry.flush();

      expect(reports, hasLength(2));
      expect(trackedEventsIn(reports.last), [
        {'name': 'the-next-batch', 'happenedAt': isA<String>()},
      ]);
    });
  });

  test('logs each cause of one batch separately', () {
    client.track('');
    client.track('value-left-out', const TrackOptions(value: double.nan));
    client.track('details-left-out', TrackOptions(details: {'bad': Object()}));
    for (var index = 1; index <= 999; index += 1) {
      client.track('event-$index');
    }

    expect(logger.warnings, [
      causedBy(TrackedEventWarning.nameOutsideTheCharacterLimit),
      causedBy(TrackedEventWarning.valueNotAFiniteNumber),
      causedBy(TrackedEventWarning.detailsNotReportable),
      causedBy(TrackedEventWarning.batchAlreadyFull),
    ]);
  });

  group('the name', () {
    test('sends an event whose name has 150 characters', () async {
      final name = 'n' * 150;

      client.track(name);
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': name, 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, isEmpty);
    });

    test('counts a character outside the basic plane as one character of the '
        'name', () async {
      final name = '😀' * 150;

      client.track(name);
      await telemetry.flush();

      expect(trackedEventsIn(reports.single), [
        {'name': name, 'happenedAt': isA<String>()},
      ]);
      expect(logger.warnings, isEmpty);
    });

    test('does not send an event whose name has 151 characters and logs a '
        'warning', () async {
      client.track('n' * 151);
      await telemetry.flush();

      expect(reports, isEmpty);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.nameOutsideTheCharacterLimit),
      ]);
    });

    test('does not send an event whose name has 151 characters outside the '
        'basic plane and logs a warning', () async {
      client.track('😀' * 151);
      await telemetry.flush();

      expect(reports, isEmpty);
      expect(logger.warnings, [
        causedBy(TrackedEventWarning.nameOutsideTheCharacterLimit),
      ]);
    });

    test(
      'does not send an event whose name is empty and logs a warning',
      () async {
        client.track('');
        await telemetry.flush();

        expect(reports, isEmpty);
        expect(logger.warnings, [
          causedBy(TrackedEventWarning.nameOutsideTheCharacterLimit),
        ]);
      },
    );

    test('logs a repeated cause once until the telemetry batch is sent, and '
        'again in the following batch', () async {
      client.track('');
      client.track('');
      expect(logger.warnings, hasLength(1));

      client.track('sent so that the batch is not empty');
      await telemetry.flush();
      client.track('');

      expect(logger.warnings, hasLength(2));
    });
  });
}
