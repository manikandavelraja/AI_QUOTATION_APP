import 'package:logger/logger.dart';

class AppLogger {
  static Logger? _logger;
  static bool _isInitialized = false;

  static void initialize() {
    if (_isInitialized) return;
    _logger = Logger(
      printer: PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 120,
        colors: true,
        printEmojis: true,
      ),
    );
    _isInitialized = true;
  }

  static void _ensureInitialized() {
    if (!_isInitialized) {
      initialize();
    }
  }

  static void debug(String message) {
    _ensureInitialized();
    _logger?.d(message);
  }

  static void info(String message) {
    _ensureInitialized();
    _logger?.i(message);
  }

  static void warning(String message) {
    _ensureInitialized();
    _logger?.w(message);
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _ensureInitialized();
    // Sanitize error to prevent API key exposure
    dynamic sanitizedError = error;
    if (error != null) {
      final errorString = error.toString();
      // Remove API key patterns from error messages
      final sanitized = errorString
          .replaceAll(
            RegExp(r'key=[A-Za-z0-9_-]+', caseSensitive: false),
            'key=***REDACTED***',
          )
          .replaceAll(
            RegExp(r'AIzaSy[A-Za-z0-9_-]+'),
            'AIzaSy***REDACTED***',
          );
      sanitizedError = sanitized != errorString ? sanitized : error;
    }
    _logger?.e(message, error: sanitizedError, stackTrace: stackTrace);
  }
}
