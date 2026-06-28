class Logger {}

class Service {
  final Logger _logger = Logger();

  Logger get logger => _logger;
}
