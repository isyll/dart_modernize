class Reporter {
  final bool color;
  final bool verbose;
  Reporter({required this.color, required this.verbose});
  void error(String msg) {}
  void errorHint(String msg) {}
}

bool resolveColor({required String? colorFlag}) => colorFlag != null;

void run(Object e) {
  final r = Reporter(color: resolveColor(colorFlag: null), verbose: false);
  r.error(e.toString());
  r.errorHint('Run dart_modernize --help for usage.');
}
