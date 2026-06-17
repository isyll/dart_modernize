const slash = 47;
const star = 42;
const comma = 44;

String toOperator(int c) => 'op';
String toPunctuation(int c) => 'punct';

String tokenize(int charCode) {
  switch (charCode) {
    case slash:
    case star:
      return toOperator(charCode);
    case comma:
      return toPunctuation(charCode);
    default:
      throw FormatException('Invalid');
  }
}
