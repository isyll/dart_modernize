class Widget {
  /// The key that identifies this widget.
  final String key;

  @Deprecated('use rebuild')
  void build() {}

  /// Creates a [Widget] with the given [key].
  ///
  /// The [key] must be unique within its parent.
  @pragma('vm:prefer-inline')
  const Widget(this.key);

  int get length => key.length;
}
