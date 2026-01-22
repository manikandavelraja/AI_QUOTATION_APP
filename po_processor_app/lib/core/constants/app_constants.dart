class AppConstants {
  // API Configuration
  static const String geminiApiKey = 'AIzaSyCnIqu_wbb-aHv3d9idWAP-0FnBfRlvzO0';
  static const String geminiModel = 'gemini-2.5-flash';
  
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
  
  // Security
  static const String encryptionKey = 'po_processor_secure_key_2024';
  
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
  static const String emailAddress = 'kumarionix07@gmail.com';
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
  static const String? gmailWebClientId = '549513027640-44n7snhn257tbamp0hhnkb8g67if4nrg.apps.googleusercontent.com';
}

