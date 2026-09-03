import 'dart:async';
import 'dart:convert';

import 'package:configdirector_flutter_client_sdk/src/eventsource/eventsource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.ByteStream _streamOf(List<String> chunks) {
  return http.ByteStream.fromBytes(utf8.encode(chunks.join()));
}

http.StreamedResponse _sseResponse(
  List<String> chunks, {
  int statusCode = 200,
}) {
  return http.StreamedResponse(
    _streamOf(chunks),
    statusCode,
    headers: {'content-type': 'text/event-stream'},
  );
}

/// A stream that never closes, simulating a long-lived open SSE connection.
http.ByteStream _neverEndingStream() {
  final controller = StreamController<List<int>>();
  return http.ByteStream(controller.stream);
}

/// Resolves once [client]'s `readyState` is [state], returning immediately
/// if it's already there.
///
/// Only appropriate for "wait until an in-flight action reaches this state"
/// call sites — i.e. call it *after* triggering the action you're waiting
/// on, not before, since `closed` is also the resting initial state and the
/// shortcut can't distinguish "already settled there" from "hasn't started
/// yet".
Future<void> _waitForState(EventSourceClient client, ReadyState state) {
  if (client.readyState == state) return Future<void>.value();

  final completer = Completer<void>();
  void listener() {
    if (client.readyState == state && !completer.isCompleted) {
      completer.complete();
    }
  }

  client.addListener(listener);
  return completer.future.whenComplete(() => client.removeListener(listener));
}

class _RequestStub implements Exception {
  const _RequestStub();

  @override
  String toString() => '_RequestStub: simulated network error';
}

void main() {
  group('EventSourceClient', () {
    group('request configuration', () {
      test('sends Accept: text/event-stream header', () async {
        http.BaseRequest? captured;
        final client = MockClient.streaming((request, bodyStream) async {
          captured = request;
          return _sseResponse(['data: hi\n\n']);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (_) => false,
        );
        source.connect();
        await source.messages.first;

        expect(captured?.headers['Accept'], 'text/event-stream');
      });

      test('merges custom headers with default Accept header', () async {
        http.BaseRequest? captured;
        final client = MockClient.streaming((request, bodyStream) async {
          captured = request;
          return _sseResponse(['data: hi\n\n']);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          headers: {'Authorization': 'Bearer token123', 'X-Custom': 'value'},
          shouldReconnect: (_) => false,
        );
        source.connect();
        await source.messages.first;

        expect(captured?.headers['Accept'], 'text/event-stream');
        expect(captured?.headers['Authorization'], 'Bearer token123');
        expect(captured?.headers['X-Custom'], 'value');
      });

      test(
        'sends Last-Event-ID header when lastEventId is configured',
        () async {
          http.BaseRequest? captured;
          final client = MockClient.streaming((request, bodyStream) async {
            captured = request;
            return _sseResponse(['data: hi\n\n']);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            lastEventId: '42',
            shouldReconnect: (_) => false,
          );
          source.connect();
          await source.messages.first;

          expect(captured?.headers['Last-Event-ID'], '42');
          expect(source.lastEventId, '42');
        },
      );

      test(
        'sends Last-Event-ID from server-provided event id on reconnect',
        () async {
          var requestCount = 0;
          final capturedLastEventIds = <String?>[];

          final client = MockClient.streaming((request, bodyStream) async {
            requestCount++;
            capturedLastEventIds.add(request.headers['Last-Event-ID']);
            if (requestCount == 1) {
              return _sseResponse(['id: 99\ndata: first\n\n']);
            }
            return _sseResponse(['data: second\n\n']);
          });

          var openCount = 0;
          final done = Completer<void>();
          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            calculateReconnectDelay: (_) => const Duration(milliseconds: 1),
            shouldReconnect: (_) {
              if (openCount >= 2) {
                done.complete();
                return false;
              }
              return true;
            },
          );
          source.addListener(() {
            if (source.readyState == ReadyState.open) openCount++;
          });
          source.connect();
          await done.future;

          expect(capturedLastEventIds[0], isNull);
          expect(capturedLastEventIds[1], '99');
          expect(source.lastEventId, '99');
        },
      );

      test(
        'does not send Last-Event-ID header when lastEventId is absent',
        () async {
          http.BaseRequest? captured;
          final client = MockClient.streaming((request, bodyStream) async {
            captured = request;
            return _sseResponse(['data: hi\n\n']);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            shouldReconnect: (_) => false,
          );
          source.connect();
          await source.messages.first;

          expect(captured?.headers.containsKey('Last-Event-ID'), isFalse);
        },
      );

      test('sends body with POST method', () async {
        String? capturedBody;
        final client = MockClient.streaming((request, bodyStream) async {
          capturedBody = await utf8.decodeStream(bodyStream);
          return _sseResponse(['data: hi\n\n']);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          method: 'POST',
          body: '{"filter":"test"}',
          shouldReconnect: (_) => false,
        );
        source.connect();
        await source.messages.first;

        expect(capturedBody, '{"filter":"test"}');
      });

      test(
        'reports a redirect status as an error when followRedirects is false',
        () async {
          final client = MockClient.streaming((request, bodyStream) async {
            return http.StreamedResponse(_streamOf(const []), 302);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            followRedirects: false,
            shouldReconnect: (_) => false,
          );
          final errorFuture = source.errors.first;
          source.connect();

          final error = await errorFuture;
          await _waitForState(source, ReadyState.closed);

          expect(error, isNotNull);
        },
      );
    });

    group('readyState', () {
      test('starts as CLOSED', () {
        final client = MockClient.streaming((request, bodyStream) async {
          return _sseResponse(['data: hi\n\n']);
        });
        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
        );
        expect(source.readyState, ReadyState.closed);
      });

      test('becomes CONNECTING synchronously after connect()', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return _sseResponse(['data: hi\n\n']);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (_) => false,
        );
        source.connect();

        expect(source.readyState, ReadyState.connecting);
        await _waitForState(source, ReadyState.closed);
      });

      test(
        'becomes OPEN once the response headers arrive, then notifies listeners',
        () async {
          final client = MockClient.streaming((request, bodyStream) async {
            return _sseResponse(['data: hi\n\n']);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            shouldReconnect: (_) => false,
          );
          final openFuture = _waitForState(source, ReadyState.open);
          source.connect();
          await openFuture;

          expect(source.readyState, ReadyState.open);
        },
      );

      test('returns to CLOSED after a 204 response', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(_streamOf(const []), 204);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
        );
        source.connect();
        await _waitForState(source, ReadyState.closed);

        expect(source.readyState, ReadyState.closed);
      });

      test('returns to CLOSED after close()', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(_neverEndingStream(), 200);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
        );
        final openFuture = _waitForState(source, ReadyState.open);
        source.connect();
        await openFuture;

        expect(source.readyState, ReadyState.open);
        source.close();
        expect(source.readyState, ReadyState.closed);
      });

      test('does not transition to OPEN for error responses', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(_streamOf(const []), 503);
        });

        var openedAtLeastOnce = false;
        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (_) => false,
        );
        source.addListener(() {
          if (source.readyState == ReadyState.open) openedAtLeastOnce = true;
        });
        source.connect();
        await _waitForState(source, ReadyState.closed);

        expect(openedAtLeastOnce, isFalse);
      });

      test(
        'does not fire an extra notification when close() is called explicitly on an open connection',
        () async {
          final client = MockClient.streaming((request, bodyStream) async {
            return http.StreamedResponse(_neverEndingStream(), 200);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
          );
          final openFuture = _waitForState(source, ReadyState.open);
          source.connect();
          await openFuture;

          var notificationsAfterClose = 0;
          source.addListener(() => notificationsAfterClose++);
          source.close();

          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(
            notificationsAfterClose,
            1,
          ); // exactly the open -> closed transition
        },
      );
    });

    group('messages', () {
      test('delivers parsed events', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return _sseResponse(['event: update\nid: 7\ndata: hello world\n\n']);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (_) => false,
        );
        source.connect();

        final message = await source.messages.first;
        expect(message.data, 'hello world');
        expect(message.type, 'update');
        expect(message.id, '7');
      });

      test(
        'delivers events to multiple listeners (broadcast stream)',
        () async {
          final client = MockClient.streaming((request, bodyStream) async {
            return _sseResponse(['data: {"key":42}\n\n']);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            method: 'POST',
            shouldReconnect: (_) => false,
          );
          final first = source.messages.first;
          final second = source.messages.first;
          source.connect();

          final results = await Future.wait([first, second]);
          expect(jsonDecode(results[0].data), {'key': 42});
          expect(results[0], results[1]);
        },
      );

      test('delivers multiple events in order', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return _sseResponse(['data: one\n\ndata: two\n\ndata: three\n\n']);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (_) => false,
        );
        final messages = source.messages.take(3).toList();
        source.connect();

        expect((await messages).map((m) => m.data), ['one', 'two', 'three']);
      });
    });

    group('comments', () {
      test('delivers SSE comment lines', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return _sseResponse([': keep-alive\ndata: hi\n\n']);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (_) => false,
        );
        final commentFuture = source.comments.first;
        source.connect();

        expect(await commentFuture, 'keep-alive');
      });
    });

    group('errors', () {
      test('emits on a network error', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          throw const _RequestStub();
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (_) => false,
        );
        final errorFuture = source.errors.first;
        source.connect();

        final error = await errorFuture;
        await _waitForState(source, ReadyState.closed);

        expect(error, isNotNull);
      });

      test(
        'emits ValueOutOfRangeError when calculateReconnectDelay returns an out-of-range value',
        () async {
          final client = MockClient.streaming((request, bodyStream) async {
            return _sseResponse(['retry: 5\ndata: hi\n\n']);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            calculateReconnectDelay: (_) =>
                Duration.zero, // below the minimum of 1 ms
            shouldReconnect: (_) => true,
          );
          final errorFuture = source.errors.first;
          source.connect();

          final error = await errorFuture;
          source.close();

          expect(error, isA<ValueOutOfRangeError>());
        },
      );

      test('does not emit for HTTP error responses', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(_streamOf(const []), 503);
        });

        final errors = <Object>[];
        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (_) => false,
        );
        source.errors.listen(errors.add);
        source.connect();
        await _waitForState(source, ReadyState.closed);

        expect(errors, isEmpty);
      });
    });

    group('HTTP status handling', () {
      test('204 response triggers disconnect without reconnection', () async {
        var requestCount = 0;
        final client = MockClient.streaming((request, bodyStream) async {
          requestCount++;
          return http.StreamedResponse(_streamOf(const []), 204);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
        );
        source.connect();
        await _waitForState(source, ReadyState.closed);

        expect(requestCount, 1);
      });

      test('4xx response is passed as status to shouldReconnect', () async {
        int? capturedStatus;
        final client = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(_streamOf(const []), 403);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          shouldReconnect: (state) {
            capturedStatus = state.status;
            return false;
          },
        );
        source.connect();
        await _waitForState(source, ReadyState.closed);

        expect(capturedStatus, 403);
      });

      test('5xx response triggers reconnect by default', () async {
        var requestCount = 0;
        final client = MockClient.streaming((request, bodyStream) async {
          requestCount++;
          if (requestCount == 1) {
            return http.StreamedResponse(_streamOf(const []), 503);
          }
          return _sseResponse(['data: hi\n\n']);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          calculateReconnectDelay: (_) => const Duration(milliseconds: 1),
          shouldReconnect: (state) => state.attempt <= 1,
        );
        source.connect();
        await source.messages.first;
        source.close();

        expect(requestCount, 2);
      });
    });

    group('reconnection', () {
      test(
        'reconnects automatically when stream ends and shouldReconnect returns true',
        () async {
          var openCount = 0;
          final client = MockClient.streaming((request, bodyStream) async {
            return _sseResponse(['data: hi\n\n']);
          });

          final done = Completer<void>();
          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            calculateReconnectDelay: (_) => const Duration(milliseconds: 1),
            shouldReconnect: (_) {
              if (openCount >= 3) {
                done.complete();
                return false;
              }
              return true;
            },
          );
          source.addListener(() {
            if (source.readyState == ReadyState.open) openCount++;
          });
          source.connect();
          await done.future;

          expect(openCount, 3);
        },
      );

      test(
        'passes incrementing attempt count to shouldReconnect on consecutive failures',
        () async {
          final attempts = <int>[];
          final client = MockClient.streaming((request, bodyStream) async {
            return http.StreamedResponse(_streamOf(const []), 503);
          });

          final done = Completer<void>();
          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            calculateReconnectDelay: (_) => const Duration(milliseconds: 1),
            shouldReconnect: (state) {
              attempts.add(state.attempt);
              if (state.attempt >= 3) {
                done.complete();
                return false;
              }
              return true;
            },
          );
          source.connect();
          await done.future;

          expect(attempts, [1, 2, 3]);
        },
      );

      test(
        'resets attempt counter when connect() is called on a closed client',
        () async {
          final attempts = <int>[];
          final client = MockClient.streaming((request, bodyStream) async {
            return http.StreamedResponse(_streamOf(const []), 503);
          });

          // Tied directly to shouldReconnect invocations rather than polling
          // readyState: `closed` is also the client's resting initial state,
          // so waiting on it before the first connect() has even started
          // would resolve immediately instead of waiting for the real cycle.
          var firstAttempt = Completer<void>();
          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            shouldReconnect: (state) {
              attempts.add(state.attempt);
              if (!firstAttempt.isCompleted) firstAttempt.complete();
              return false;
            },
          );

          source.connect();
          await firstAttempt.future;
          firstAttempt = Completer<void>();

          source.connect();
          await firstAttempt.future;

          expect(attempts, [1, 1]);
        },
      );

      test(
        'passes serverReconnectionTime from SSE retry field to calculateReconnectDelay',
        () async {
          Duration? capturedServerReconnectionTime;
          final client = MockClient.streaming((request, bodyStream) async {
            return _sseResponse(['retry: 5000\ndata: hi\n\n']);
          });

          final calculateCompleter = Completer<void>();
          late final EventSourceClient source;
          source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            calculateReconnectDelay: (state) {
              capturedServerReconnectionTime = state.serverReconnectionTime;
              if (!calculateCompleter.isCompleted) {
                calculateCompleter.complete();
              }
              return const Duration(seconds: 10);
            },
            shouldReconnect: (_) => true,
          );
          source.connect();
          await calculateCompleter.future;
          source.close();

          expect(
            capturedServerReconnectionTime,
            const Duration(milliseconds: 5000),
          );
        },
      );

      test('passes reconnection state to calculateReconnectDelay', () async {
        ReconnectionState? capturedState;
        final client = MockClient.streaming((request, bodyStream) async {
          return _sseResponse(['data: hi\n\n']);
        });

        final calculateCompleter = Completer<void>();
        late final EventSourceClient source;
        source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          calculateReconnectDelay: (state) {
            capturedState = state;
            if (!calculateCompleter.isCompleted) calculateCompleter.complete();
            return const Duration(seconds: 10);
          },
          shouldReconnect: (_) => true,
        );
        source.connect();
        await calculateCompleter.future;
        source.close();

        expect(capturedState?.attempt, 1);
        expect(
          capturedState?.serverReconnectionTime,
          const Duration(seconds: 2),
        );
      });

      for (final entry in <String, Duration>{
        'zero': Duration.zero,
        'negative': const Duration(milliseconds: -1),
        'above the one-hour maximum': const Duration(hours: 1, milliseconds: 1),
      }.entries) {
        test(
          'emits an error and falls back to serverReconnectionTime when delay is ${entry.key}',
          () async {
            final client = MockClient.streaming((request, bodyStream) async {
              return _sseResponse(['retry: 5\ndata: hi\n\n']);
            });

            final source = EventSourceClient(
              url: Uri.parse('http://localhost/sse'),
              client: client,
              calculateReconnectDelay: (_) => entry.value,
              shouldReconnect: (_) => true,
            );
            final errorFuture = source.errors.first;
            source.connect();

            final error = await errorFuture;
            source.close();

            expect(error, isA<ValueOutOfRangeError>());
          },
        );
      }

      for (final entry in <String, Duration>{
        'minimum (1 ms)': const Duration(milliseconds: 1),
        'maximum (1 hour)': const Duration(hours: 1),
      }.entries) {
        test(
          'does not emit an error when delay is at the valid boundary: ${entry.key}',
          () async {
            final client = MockClient.streaming((request, bodyStream) async {
              return _sseResponse(['data: hi\n\n']);
            });

            final errors = <Object>[];
            final calculateCompleter = Completer<void>();
            late final EventSourceClient source;
            source = EventSourceClient(
              url: Uri.parse('http://localhost/sse'),
              client: client,
              calculateReconnectDelay: (_) {
                if (!calculateCompleter.isCompleted) {
                  calculateCompleter.complete();
                }
                return entry.value;
              },
              shouldReconnect: (_) => true,
            );
            source.errors.listen(errors.add);
            source.connect();
            await calculateCompleter.future;
            source.close();

            expect(errors, isEmpty);
          },
        );
      }

      test(
        'connect() is a no-op when a connection is already in progress',
        () async {
          var requestCount = 0;
          final client = MockClient.streaming((request, bodyStream) async {
            requestCount++;
            return _sseResponse(['data: hi\n\n']);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
            shouldReconnect: (_) => false,
          );
          final openFuture = _waitForState(source, ReadyState.open);

          source.connect();
          source.connect();
          source.connect();

          await openFuture;
          expect(requestCount, 1);
        },
      );
    });

    group('close()', () {
      test('close() prevents a scheduled reconnect from firing', () async {
        var requestCount = 0;
        final client = MockClient.streaming((request, bodyStream) async {
          requestCount++;
          return http.StreamedResponse(_streamOf(const []), 503);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
          calculateReconnectDelay: (_) => const Duration(milliseconds: 200),
          shouldReconnect: (_) => true,
        );

        source.connect();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        source.close();
        await Future<void>.delayed(const Duration(milliseconds: 250));

        expect(requestCount, 1);
      });

      test(
        'close() allows a subsequent connect() to re-establish the connection',
        () async {
          final client = MockClient.streaming((request, bodyStream) async {
            return http.StreamedResponse(_neverEndingStream(), 200);
          });

          final source = EventSourceClient(
            url: Uri.parse('http://localhost/sse'),
            client: client,
          );

          final firstOpen = _waitForState(source, ReadyState.open);
          source.connect();
          await firstOpen;

          source.close();
          await Future<void>.delayed(const Duration(milliseconds: 10));

          final secondOpen = _waitForState(source, ReadyState.open);
          source.connect();
          await secondOpen;

          expect(source.readyState, ReadyState.open);
        },
      );

      test('close() while connecting releases the late response', () async {
        final body = StreamController<List<int>>();
        final responseGate = Completer<void>();
        final client = MockClient.streaming((request, bodyStream) async {
          await responseGate.future;
          return http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });
        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
        );

        source.connect();
        await pumpEventQueue();
        source.close();
        responseGate.complete();
        await pumpEventQueue();

        expect(body.hasListener, isFalse);
        expect(source.readyState, ReadyState.closed);
        await body.close();
      });

      test('a failure from an attempt abandoned by close() leaves the next '
          'connection open', () async {
        var attempts = 0;
        final firstAttemptFails = Completer<void>();
        final client = MockClient.streaming((request, bodyStream) async {
          attempts++;
          if (attempts == 1) {
            await firstAttemptFails.future;
            throw const _RequestStub();
          }
          return http.StreamedResponse(_neverEndingStream(), 200);
        });
        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
        );

        source.connect();
        await pumpEventQueue();
        source.close();
        source.connect();
        await _waitForState(source, ReadyState.open);
        firstAttemptFails.complete();
        await pumpEventQueue();

        expect(source.readyState, ReadyState.open);
        source.dispose();
      });
    });

    group('dispose()', () {
      test('closes the messages, comments, and errors streams', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(_neverEndingStream(), 200);
        });

        final source = EventSourceClient(
          url: Uri.parse('http://localhost/sse'),
          client: client,
        );
        final openFuture = _waitForState(source, ReadyState.open);
        source.connect();
        await openFuture;

        source.dispose();

        expect(source.readyState, ReadyState.closed);
        await expectLater(source.messages, emitsDone);
        await expectLater(source.comments, emitsDone);
        await expectLater(source.errors, emitsDone);
      });
    });
  });
}
