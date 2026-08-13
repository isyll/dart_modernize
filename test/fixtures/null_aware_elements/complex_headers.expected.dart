List<String> headers(String contentType, String? auth, String? trace) {
  return ['Content-Type: $contentType', ?auth, ?trace];
}
