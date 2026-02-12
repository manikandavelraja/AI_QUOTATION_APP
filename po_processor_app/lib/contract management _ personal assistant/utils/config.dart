class Config {
  // Store API key securely
  // IMPORTANT: This file is gitignored. Never commit API keys to version control.
  // For production, use environment variables (see DEPLOYMENT.md)
  // Current API key is stored here for local development only
  static const String geminiApiKey = 'AIzaSyC-Nm2fG7S0mAzcPFCQkgce66hC0Y1syqA';
  
  // API Configuration
  static const String geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  static const String geminiModel = 'gemini-1.5-flash';
  
  // App Configuration
  static const String appName = 'Secure Vision';
  static const String appVersion = '1.0.0';
}

