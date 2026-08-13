enum LogLevel { info, warning, error }

void log(String message, {required LogLevel level}) {}

void main() {
  log('boom', level: .error);
}
