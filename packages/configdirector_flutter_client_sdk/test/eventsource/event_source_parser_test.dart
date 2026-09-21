import 'package:configdirector_flutter_client_sdk/src/eventsource/eventsource.dart';
import 'package:flutter_test/flutter_test.dart';

class _ParserHarness {
  final events = <EventSourceMessage>[];
  final retries = <Duration>[];
  final comments = <String>[];
  late final EventSourceParser parser;

  _ParserHarness() {
    parser = EventSourceParser(
      onEvent: events.add,
      onRetry: retries.add,
      onComment: comments.add,
    );
  }
}

void main() {
  group('EventSourceParser', () {
    group('basic event dispatching', () {
      test(
        'dispatches an event when an empty line is encountered after data',
        () {
          final h = _ParserHarness();
          h.parser.parse('data: hello\n\n');
          expect(h.events, hasLength(1));
          expect(h.events[0].data, 'hello');
        },
      );

      test(
        'does not dispatch an event for an empty line with no accumulated data',
        () {
          final h = _ParserHarness();
          h.parser.parse('\n');
          expect(h.events, isEmpty);
        },
      );

      test(
        'does not dispatch an event when only id or type are set but data is empty',
        () {
          final h = _ParserHarness();
          h.parser.parse('id: 1\nevent: test\n\n');
          expect(h.events, isEmpty);
        },
      );

      test('resets the current event after dispatching', () {
        final h = _ParserHarness();
        h.parser.parse('data: first\n\ndata: second\n\n');
        expect(h.events, hasLength(2));
        expect(h.events[0].data, 'first');
        expect(h.events[1].data, 'second');
      });

      test('resets event type after dispatching', () {
        final h = _ParserHarness();
        h.parser.parse('event: custom\ndata: first\n\ndata: second\n\n');
        expect(h.events[0].type, 'custom');
        expect(h.events[1].type, isNull);
      });

      test(
        'carries the last event ID to subsequent events that do not set a new id',
        () {
          final h = _ParserHarness();
          h.parser.parse('id: 42\ndata: first\n\ndata: second\n\n');
          expect(h.events[0].id, '42');
          expect(h.events[1].id, '42');
        },
      );
    });

    group('data field', () {
      test('parses a simple data field', () {
        final h = _ParserHarness();
        h.parser.parse('data: hello\n\n');
        expect(h.events[0].data, 'hello');
      });

      test('strips leading space after colon from value', () {
        final h = _ParserHarness();
        h.parser.parse('data: value\n\n');
        expect(h.events[0].data, 'value');
      });

      test('does not strip more than one leading space', () {
        final h = _ParserHarness();
        h.parser.parse('data:  two spaces\n\n');
        expect(h.events[0].data, ' two spaces');
      });

      test('parses data with no space after colon', () {
        final h = _ParserHarness();
        h.parser.parse('data:value\n\n');
        expect(h.events[0].data, 'value');
      });

      test('concatenates multiple data lines with newlines between them', () {
        final h = _ParserHarness();
        h.parser.parse('data: line1\ndata: line2\ndata: line3\n\n');
        expect(h.events[0].data, 'line1\nline2\nline3');
      });

      test(
        'treats a data line with no value as an empty string (appending a newline)',
        () {
          final h = _ParserHarness();
          h.parser.parse('data:\ndata: second\n\n');
          expect(h.events[0].data, '\nsecond');
        },
      );

      test('does not dispatch when data field has no colon and no value', () {
        final h = _ParserHarness();
        h.parser.parse('data\n\n');
        expect(h.events, isEmpty);
      });
    });

    group('event type field', () {
      test('sets the event type', () {
        final h = _ParserHarness();
        h.parser.parse('event: message\ndata: hello\n\n');
        expect(h.events[0].type, 'message');
      });

      test('uses the last event field value if specified multiple times', () {
        final h = _ParserHarness();
        h.parser.parse('event: first\nevent: second\ndata: hello\n\n');
        expect(h.events[0].type, 'second');
      });

      test('does not set type if event field is absent', () {
        final h = _ParserHarness();
        h.parser.parse('data: hello\n\n');
        expect(h.events[0].type, isNull);
      });
    });

    group('id field', () {
      test('sets the event id', () {
        final h = _ParserHarness();
        h.parser.parse('id: 123\ndata: hello\n\n');
        expect(h.events[0].id, '123');
      });

      test('ignores id field containing a null character (U+0000)', () {
        final h = _ParserHarness();
        h.parser.parse('id: abc\u0000def\ndata: hello\n\n');
        expect(h.events[0].id, isNull);
      });

      test('accepts id with empty value', () {
        final h = _ParserHarness();
        h.parser.parse('id:\ndata: hello\n\n');
        expect(h.events[0].id, '');
      });

      test('accepts id with no space after colon', () {
        final h = _ParserHarness();
        h.parser.parse('id:42\ndata: hello\n\n');
        expect(h.events[0].id, '42');
      });
    });

    group('retry field', () {
      test('calls onRetry with the parsed value as a Duration', () {
        final h = _ParserHarness();
        h.parser.parse('retry: 3000\n\n');
        expect(h.retries, [const Duration(milliseconds: 3000)]);
      });

      test('ignores retry if value contains non-digit characters', () {
        final h = _ParserHarness();
        h.parser.parse('retry: 3000ms\n\n');
        expect(h.retries, isEmpty);
      });

      test('ignores retry if value is empty', () {
        final h = _ParserHarness();
        h.parser.parse('retry:\n\n');
        expect(h.retries, isEmpty);
      });

      test('ignores retry if value contains a float', () {
        final h = _ParserHarness();
        h.parser.parse('retry: 1.5\n\n');
        expect(h.retries, isEmpty);
      });

      test('ignores retry if value is too long to be a delay', () {
        final h = _ParserHarness();
        h.parser.parse('retry: 99999999999999999999\n\n');
        expect(h.retries, isEmpty);
      });

      test('processes retry without dispatching an event if data is empty', () {
        final h = _ParserHarness();
        h.parser.parse('retry: 5000\n\n');
        expect(h.events, isEmpty);
        expect(h.retries, [const Duration(milliseconds: 5000)]);
      });
    });

    group('comments', () {
      test('calls onComment for lines starting with colon', () {
        final h = _ParserHarness();
        h.parser.parse(': this is a comment\n\n');
        expect(h.comments, ['this is a comment']);
      });

      test('calls onComment for colon-only lines (empty comment)', () {
        final h = _ParserHarness();
        h.parser.parse(':\n\n');
        expect(h.comments, ['']);
      });

      test('does not dispatch an event for a comment line', () {
        final h = _ParserHarness();
        h.parser.parse(': comment\n\n');
        expect(h.events, isEmpty);
      });

      test('can mix comments and data fields in the same event block', () {
        final h = _ParserHarness();
        h.parser.parse(': keep-alive\ndata: hello\n\n');
        expect(h.comments, ['keep-alive']);
        expect(h.events, hasLength(1));
        expect(h.events[0].data, 'hello');
      });
    });

    group('unknown fields', () {
      test('silently ignores unknown field names', () {
        final h = _ParserHarness();
        h.parser.parse('unknown: value\ndata: hello\n\n');
        expect(h.events, hasLength(1));
        expect(h.events[0].data, 'hello');
      });
    });

    group('line ending variants', () {
      test('handles LF line endings', () {
        final h = _ParserHarness();
        h.parser.parse('data: hello\n\n');
        expect(h.events[0].data, 'hello');
      });

      test('handles CR line endings', () {
        final h = _ParserHarness();
        h.parser.parse('data: hello\r\r');
        expect(h.events[0].data, 'hello');
      });

      test('handles CRLF line endings', () {
        final h = _ParserHarness();
        h.parser.parse('data: hello\r\n\r\n');
        expect(h.events[0].data, 'hello');
      });

      test('handles mixed line endings within the same chunk', () {
        final h = _ParserHarness();
        h.parser.parse('data: line1\r\ndata: line2\n\r\n');
        expect(h.events[0].data, 'line1\nline2');
      });
    });

    group('BOM stripping', () {
      test('strips Unicode BOM (U+FEFF) from the start of the first chunk', () {
        final h = _ParserHarness();
        h.parser.parse('﻿data: hello\n\n');
        expect(h.events[0].data, 'hello');
      });

      test(
        'strips UTF-8 BOM (bytes 0xEF 0xBB 0xBF as individual chars) at the start of the first chunk',
        () {
          const bom = 'ï»¿';
          final h = _ParserHarness();
          h.parser.parse('${bom}data: hello\n\n');
          expect(h.events[0].data, 'hello');
        },
      );

      test(
        'does not strip BOM if it appears after the start of the stream',
        () {
          const bom = 'ï»¿';
          final h = _ParserHarness();
          h.parser.parse('data: ${bom}hello\n\n');
          expect(h.events[0].data, '${bom}hello');
        },
      );
    });

    group('chunked / streaming input', () {
      test('handles a field split across two chunks', () {
        final h = _ParserHarness();
        h.parser.parse('data: hel');
        h.parser.parse('lo\n\n');
        expect(h.events[0].data, 'hello');
      });

      test('handles the event delimiter split across two chunks', () {
        final h = _ParserHarness();
        h.parser.parse('data: hello\n');
        h.parser.parse('\n');
        expect(h.events[0].data, 'hello');
      });

      test('handles multiple events delivered in a single chunk', () {
        final h = _ParserHarness();
        h.parser.parse('data: one\n\ndata: two\n\ndata: three\n\n');
        expect(h.events, hasLength(3));
        expect(h.events.map((e) => e.data), ['one', 'two', 'three']);
      });

      test(
        'handles events split across many small single-character chunks',
        () {
          final h = _ParserHarness();
          const input = 'data: hello\n\n';
          for (final unit in input.split('')) {
            h.parser.parse(unit);
          }
          expect(h.events[0].data, 'hello');
        },
      );

      test(
        'accumulates incomplete line and processes it on the next chunk',
        () {
          final h = _ParserHarness();
          h.parser.parse('data: par');
          h.parser.parse('tial\n\n');
          expect(h.events[0].data, 'partial');
        },
      );
    });

    group('finish()', () {
      test('does not dispatch when stream ends without a trailing newline', () {
        final h = _ParserHarness();
        h.parser.parse('data: hello');
        h.parser.finish();
        expect(h.events, isEmpty);
      });

      test(
        'does not dispatch when stream ends with a single trailing newline and no empty line',
        () {
          final h = _ParserHarness();
          h.parser.parse('data: hello\n');
          h.parser.finish();
          expect(h.events, isEmpty);
        },
      );

      test(
        'does not re-dispatch a completed event when finish is called after a full stream',
        () {
          final h = _ParserHarness();
          h.parser.parse('data: complete\n\n');
          h.parser.finish();
          expect(h.events, hasLength(1));
          expect(h.events[0].data, 'complete');
        },
      );
    });

    group('spec examples', () {
      test("parses multi-line data from the spec 'data only' example", () {
        final h = _ParserHarness();
        h.parser.parse('data: YHOO\ndata: +2\ndata: 10\n\n');
        expect(h.events, hasLength(1));
        expect(h.events[0].data, 'YHOO\n+2\n10');
      });

      test("parses named events from the spec 'named events' example", () {
        final h = _ParserHarness();
        h.parser.parse(
          'event: add\ndata: 73857293\n\nevent: remove\ndata: 2153\n\nevent: add\ndata: 113411\n\n',
        );
        expect(h.events, hasLength(3));
        expect(h.events[0].type, 'add');
        expect(h.events[0].data, '73857293');
        expect(h.events[1].type, 'remove');
        expect(h.events[1].data, '2153');
        expect(h.events[2].type, 'add');
        expect(h.events[2].data, '113411');
      });

      test('carries the last event ID to events that do not set a new id', () {
        final h = _ParserHarness();
        h.parser.parse(
          'id: 1\ndata: first event\n\nid: 2\ndata: second event\n\ndata: third event\n\n',
        );
        expect(h.events[0].id, '1');
        expect(h.events[0].data, 'first event');
        expect(h.events[1].id, '2');
        expect(h.events[1].data, 'second event');
        expect(h.events[2].id, '2');
      });

      test(
        'does not dispatch when data field has no colon and resolves to empty value',
        () {
          final h = _ParserHarness();
          h.parser.parse('data\n\n');
          expect(h.events, isEmpty);
        },
      );
    });

    group('edge cases', () {
      test('handles a stream with only comments and no events', () {
        final h = _ParserHarness();
        h.parser.parse(': ping\n: pong\n\n');
        expect(h.events, isEmpty);
        expect(h.comments, ['ping', 'pong']);
      });

      test('handles very long data values', () {
        final h = _ParserHarness();
        final longValue = 'x' * 100000;
        h.parser.parse('data: $longValue\n\n');
        expect(h.events[0].data, longValue);
      });

      test('does not throw when onEvent callback is not provided', () {
        final parser = EventSourceParser();
        expect(() => parser.parse('data: hello\n\n'), returnsNormally);
      });

      test('does not throw when onRetry callback is not provided', () {
        final parser = EventSourceParser();
        expect(() => parser.parse('retry: 1000\n\n'), returnsNormally);
      });

      test('does not throw when onComment callback is not provided', () {
        final parser = EventSourceParser();
        expect(() => parser.parse(': comment\n\n'), returnsNormally);
      });

      test('handles an empty input string', () {
        final h = _ParserHarness();
        expect(() => h.parser.parse(''), returnsNormally);
        expect(h.events, isEmpty);
      });

      test(
        'handles multiple consecutive empty lines (only one event dispatched per data block)',
        () {
          final h = _ParserHarness();
          h.parser.parse('data: hello\n\n\n\n');
          expect(h.events, hasLength(1));
        },
      );

      test('handles a field with a colon in its value', () {
        final h = _ParserHarness();
        h.parser.parse('data: key:value\n\n');
        expect(h.events[0].data, 'key:value');
      });

      test('handles JSON data correctly', () {
        final h = _ParserHarness();
        const json = '{"foo":"bar","n":42}';
        h.parser.parse('data: $json\n\n');
        expect(h.events[0].data, json);
      });
    });
  });
}
