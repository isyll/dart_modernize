List<String> headers(String contentType, String? auth, String? trace) {
  return [
    'Content-Type: $contentType',
    if (auth != null) auth,
    if (trace != null) trace,
  ];
}
