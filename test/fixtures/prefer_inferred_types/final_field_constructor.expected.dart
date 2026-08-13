class Logger {}

class Service {
  final _logger = Logger();

  Logger get logger => _logger;
}
