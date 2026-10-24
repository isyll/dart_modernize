// The header has nowhere to keep a constructor's doc comment, annotation, or
// comments, so the class stays as written.
class Token {
  final String value;

  /// Creates a token. Never pass an empty [value].
  const Token(this.value);
}

class LegacyToken {
  final String value;

  @Deprecated('Use Token')
  const LegacyToken(this.value);
}

class CommentedToken {
  final String value;

  const CommentedToken(
    // raw text, already trimmed
    this.value,
  );
}

class NotedToken {
  final String value;

  // Kept for the JSON decoder.
  const NotedToken(this.value);
}
