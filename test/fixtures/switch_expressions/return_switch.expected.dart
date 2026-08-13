const slash = 47;
const star = 42;
const comma = 44;

String toOperator(int c) => 'op';
String toPunctuation(int c) => 'punct';

String tokenize(int charCode) {
  return switch (charCode) {
    slash || star => toOperator(charCode),
    comma => toPunctuation(charCode),
    _ => throw FormatException('Invalid'),
  };
}
