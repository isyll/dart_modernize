const slash = 47;
const star = 42;
const comma = 44;

String toOperator(int c) => 'op';
String toPunctuation(int c) => 'punct';

String tokenize(int charCode) {
  String token;
  switch (charCode) {
    case slash:
    case star:
      token = toOperator(charCode);
      break;
    case comma:
      token = toPunctuation(charCode);
      break;
    default:
      throw FormatException('Invalid');
  }
  return token;
}
