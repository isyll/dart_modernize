class Config {
  final String host; // the target host

  int retries = 3; // how many times to retry

  void reset() {} // restore defaults

  Config(this.host); // primary constructor
}
