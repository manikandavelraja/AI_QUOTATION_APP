import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  /// Prefer GEMINI_API_KEY from .env (same as main app). Fallback for local dev only.
  static String get geminiApiKey {
    final envKey = dotenv.env['GEMINI_API_KEY'];
    if (envKey != null && envKey.isNotEmpty) return envKey;
    return const String.fromEnvironment(
      'GEMINI_API_KEY',
      defaultValue: 'AIzaSyC-Nm2fG7S0mAzcPFCQkgce66hC0Y1syqA',
    );
  }

  // API Configuration
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';
  static const String geminiModel = 'gemini-1.5-flash';

  // App Configuration
  static const String appName = 'Secure Vision';
  static const String appVersion = '1.0.0';
}

