String category(int httpStatus) {
  switch (httpStatus) {
    case 200:
    case 201:
    case 204:
      return 'success';
    case 301:
    case 302:
      return 'redirect';
    case 400:
    case 401:
    case 403:
    case 404:
      return 'client error';
    default:
      return 'unknown';
  }
}
