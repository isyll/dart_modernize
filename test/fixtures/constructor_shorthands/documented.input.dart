class Token {
  /// Wraps an already trimmed [value].
  @Deprecated('Use Token.parse')
  const Token(this.value);

  final String value;
}
