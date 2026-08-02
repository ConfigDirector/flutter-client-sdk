import 'types.dart';

class EventSourceParser {
  bool _isFirstChunk = true;
  String _bufferedInput = '';
  String? _currentType;
  String _currentData = '';
  String? _lastEventId;

  final EventSourceMessageHandler onEvent;
  final EventParserRetryCallback? onRetry;
  final EventSourceCommentHandler? onComment;

  EventSourceParser({
    EventSourceMessageHandler? onEvent,
    this.onRetry,
    this.onComment,
  }) : onEvent = onEvent ?? ((_) {});

  void parse(String chunk) {
    var input = chunk;

    if (_isFirstChunk) {
      _isFirstChunk = false;
      if (input.startsWith('\uFEFF')) {
        input = input.substring(1);
      } else if (input.startsWith('\u00EF\u00BB\u00BF')) {
        input = input.substring(3);
      }
    }

    final lines = _scanLines(_bufferedInput + input);
    for (final line in lines) {
      _dispatchLine(line);
    }
  }

  // Per the SSE spec, any data still buffered when the stream ends is
  // discarded — an event requires a terminating empty line to be dispatched.
  void finish() {
    _bufferedInput = '';
  }

  // Scans character by character to extract complete lines, recognizing CR,
  // LF, and CRLF as line terminators per the SSE spec. Any unterminated
  // trailing text is buffered and prepended to the next chunk.
  List<String> _scanLines(String text) {
    final lines = <String>[];
    var lineStart = 0;
    var i = 0;

    while (i < text.length) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x0D || unit == 0x0A) {
        lines.add(text.substring(lineStart, i));
        // Consume CRLF as a single terminator rather than two separate lines.
        if (unit == 0x0D &&
            i + 1 < text.length &&
            text.codeUnitAt(i + 1) == 0x0A) {
          i++;
        }
        i++;
        lineStart = i;
      } else {
        i++;
      }
    }

    _bufferedInput = text.substring(lineStart);
    return lines;
  }

  void _dispatchLine(String line) {
    if (line.startsWith(':')) {
      onComment?.call(_extractValue(line, 1));
      return;
    }

    if (line.isEmpty) {
      _emitEvent();
      return;
    }

    _applyField(_parseField(line));
  }

  void _emitEvent() {
    final data = _currentData.endsWith('\n')
        ? _currentData.substring(0, _currentData.length - 1)
        : _currentData;

    if (data.isNotEmpty) {
      onEvent(
        EventSourceMessage(id: _lastEventId, type: _currentType, data: data),
      );
    }

    _currentType = null;
    _currentData = '';
  }

  void _applyField(({String field, String value}) parsed) {
    switch (parsed.field) {
      case 'event':
        _currentType = parsed.value;
        break;
      case 'data':
        _currentData += '${parsed.value}\n';
        break;
      case 'id':
        // Spec: ignore id values that contain a null character.
        if (!parsed.value.contains('\u0000')) {
          _lastEventId = parsed.value;
        }
        break;
      case 'retry':
        if (RegExp(r'^\d+$').hasMatch(parsed.value)) {
          onRetry?.call(Duration(milliseconds: int.parse(parsed.value)));
        }
        break;
      default:
        break;
    }
  }

  ({String field, String value}) _parseField(String line) {
    final colon = line.indexOf(':');
    if (colon == -1) {
      return (field: line, value: '');
    }
    return (
      field: line.substring(0, colon),
      value: _extractValue(line, colon + 1),
    );
  }

  String _extractValue(String line, int from) {
    if (from < line.length && line.codeUnitAt(from) == 0x20) {
      return line.substring(from + 1);
    }
    return line.substring(from);
  }
}
