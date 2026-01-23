import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // API Configuration
  // Load from environment variables, with fallback to compile-time constants
  // For production, always use environment variables
  static String get geminiApiKey {
    // Try environment variable first (from .env file)
    final envKey = dotenv.env['GEMINI_API_KEY'];
    if (envKey != null && envKey.isNotEmpty) {
      return envKey;
    }
    // Fallback to compile-time constant (for development only)
    // TODO: Remove this fallback in production
    const fallbackKey = String.fromEnvironment(
      'GEMINI_API_KEY',
      defaultValue: '',
    );
    if (fallbackKey.isNotEmpty) {
      return fallbackKey;
    }
    // Last resort: throw error to prevent using leaked key
    throw Exception(
      'GEMINI_API_KEY not found in environment variables. '
      'Please create a .env file with GEMINI_API_KEY=your_key',
    );
  }
  
  static String get geminiModel {
    return dotenv.env['GEMINI_MODEL'] ?? 
           const String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.5-flash');
  }
  
  // Default Authentication Credentials
  static const String defaultUsername = 'admin';
  static const String defaultPassword = 'admin123';
  
  // App Configuration
  static const String appName = 'PO Processor';
  static const String appVersion = '1.0.0';
  
  // PO Expiry Alert Days
  static const int expiryAlertDays = 7;
  
  // File Upload Limits
  static const int maxFileSizeMB = 10;
  static const List<String> allowedFileTypes = ['pdf'];
  
  // Database Configuration
  static const String databaseName = 'po_processor.db';
  static const int databaseVersion = 3; // Incremented to add sender_email column
  
  // Supported Languages
  static const String defaultLanguage = 'en';
  static const List<String> supportedLanguages = ['en', 'ta'];
  
  // Storage Keys
  static const String authTokenKey = 'auth_token';
  static const String languageKey = 'app_language';
  static const String themeKey = 'app_theme';
  static const String userIdKey = 'user_id';
  
  // API Endpoints (if using backend)
  static const String baseUrl = 'https://api.poprocessor.com';
  static const Duration apiTimeout = Duration(seconds: 30);
  
  // Sustainability Metrics
  static const double carbonFootprintPerPO = 0.05; // kg CO2
  static const double paperSavedPerPO = 0.1; // sheets
  
  // Email Configuration
  static const String smtpHost = 'smtp.gmail.com';
  static const int smtpPort = 587;
  // IMAP Configuration
  static const String imapHost = 'imap.gmail.com';
  static const int imapPort = 993;
  // Note: App password should be stored securely, not in constants
  // For production, use secure storage or environment variables
  
  // Gmail API Configuration for Web
  // To get OAuth2 Client ID:
  // 1. Go to https://console.cloud.google.com/
  // 2. Create a project or select existing
  // 3. Enable Gmail API
  // 4. Create OAuth2 credentials (Web application)
  // 5. Add authorized JavaScript origins: http://localhost:PORT
  // 6. Add authorized redirect URIs: http://localhost:PORT
  static String? get gmailWebClientId {
    // Try environment variable first
    final envClientId = dotenv.env['GMAIL_WEB_CLIENT_ID'];
    if (envClientId != null && envClientId.isNotEmpty) {
      return envClientId;
    }
    // Fallback to compile-time constant
    const fallbackClientId = String.fromEnvironment('GMAIL_WEB_CLIENT_ID');
    if (fallbackClientId.isNotEmpty) {
      return fallbackClientId;
    }
    // Return null if not found (optional for some configurations)
    return null;
  }
  
  // Email Configuration
  static String get emailAddress {
    return dotenv.env['EMAIL_ADDRESS'] ?? 
           const String.fromEnvironment('EMAIL_ADDRESS', defaultValue: 'kumarionix07@gmail.com');
  }
  
  // Security - Encryption Key
  static String get encryptionKey {
    final envKey = dotenv.env['ENCRYPTION_KEY'];
    if (envKey != null && envKey.isNotEmpty) {
      return envKey;
    }
    // Fallback for development (should be changed in production)
    return const String.fromEnvironment(
      'ENCRYPTION_KEY',
      defaultValue: 'po_processor_secure_key_2024',
    );
  }
}

