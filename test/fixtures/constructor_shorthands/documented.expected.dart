class Token {
  /// Wraps an already trimmed [value].
  @Deprecated('Use Token.parse')
  const new(this.value);

  final String value;
}
