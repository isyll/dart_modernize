// A comment at the end of a field's line has no place in the header, and
// one at the end of the constructor's line would land on the wrong member.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? code; // ex: 'NETWORK', 'TIMEOUT'

  ApiException({this.statusCode, required this.message, this.code});
}

class Point {
  final int x;

  Point(this.x); // the origin is Point(0)
}
