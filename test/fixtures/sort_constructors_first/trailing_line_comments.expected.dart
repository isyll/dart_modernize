class Config {
  Config(this.host); // primary constructor

  final String host; // the target host

  int retries = 3; // how many times to retry

  void reset() {} // restore defaults
}
