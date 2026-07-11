class Session {
  Session({this.expiresAt, this.expiresIn});

  final Object? expiresAt;
  final Object? expiresIn;

  DateTime? get expiry {
    switch (expiresAt) {
      case final String value:
        return DateTime.tryParse(value)?.toUtc();
      case final num value:
        return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toUtc();
    }
    return null;
  }

  Duration? get timeUntilExpiry {
    final at = expiry;
    if (at == null) return null;
    final remaining = at.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  DateTime? computedExpiry() {
    final seconds = expiresIn;
    if (seconds is num) {
      return DateTime.now().toUtc().add(Duration(seconds: seconds.toInt()));
    }
    return null;
  }
}
