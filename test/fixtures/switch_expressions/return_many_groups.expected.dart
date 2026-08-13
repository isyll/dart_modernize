String category(int httpStatus) {
  return switch (httpStatus) {
    200 || 201 || 204 => 'success',
    301 || 302 => 'redirect',
    400 || 401 || 403 || 404 => 'client error',
    _ => 'unknown',
  };
}
