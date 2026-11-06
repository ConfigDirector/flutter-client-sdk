import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../types.dart';

/// An event the code under test tracked, as a test client recorded it.
@immutable
final class TrackedEvent {
  const TrackedEvent({
    required this.name,
    this.context,
    this.value,
    this.details,
  });

  /// The name the event was tracked with.
  final String name;

  /// The context the event was tracked for, if any.
  final ConfigDirectorContext? context;

  /// The value the event was tracked with, when it is a finite number.
  final num? value;

  /// The details the event was tracked with, when they are within the limits.
  final TrackedEventDetails? details;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackedEvent &&
          other.name == name &&
          other.context == context &&
          other.value == value &&
          const DeepCollectionEquality().equals(other.details, details));

  @override
  int get hashCode => Object.hash(
    name,
    context,
    value,
    const DeepCollectionEquality().hash(details),
  );

  @override
  String toString() =>
      'TrackedEvent(name: $name, context: $context, value: $value, '
      'details: $details)';
}
