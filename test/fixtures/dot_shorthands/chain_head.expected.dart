class Session {
  Session({this.expiresAt, this.expiresIn});

  final Object? expiresAt;
  final Object? expiresIn;

  DateTime? get expiry {
    switch (expiresAt) {
      case final String value:
        return .tryParse(value)?.toUtc();
      case final num value:
        return .fromMillisecondsSinceEpoch(value.toInt()).toUtc();
    }
    return null;
  }

  Duration? get timeUntilExpiry {
    final at = expiry;
    if (at == null) return null;
    final remaining = at.difference(.now().toUtc());
    return remaining.isNegative ? .zero : remaining;
  }

  DateTime? computedExpiry() {
    final seconds = expiresIn;
    if (seconds is num) {
      return .now().toUtc().add(.new(seconds: seconds.toInt()));
    }
    return null;
  }
}
