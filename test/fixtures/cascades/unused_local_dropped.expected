class Reporter {
  final bool color;
  final bool verbose;
  Reporter({required this.color, required this.verbose});
  void error(String msg) {}
  void errorHint(String msg) {}
}

bool resolveColor({required String? colorFlag}) => colorFlag != null;

void run(Object e) {
  Reporter(color: resolveColor(colorFlag: null), verbose: false)
    ..error(e.toString())
    ..errorHint('Run dart_modernize --help for usage.');
}
