String severity(int code) {
  String label;
  switch (code) {
    case 0:
    case 1:
      label = 'low';
      break;
    case 2:
    case 3:
      label = 'medium';
      break;
    default:
      label = 'high';
  }
  return label;
}
