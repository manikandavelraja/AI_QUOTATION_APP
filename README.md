# AI Quotation App

An AI-powered application for processing customer inquiries, generating quotations, and managing purchase orders.

## Features

- **Email Integration**: Automatically fetch customer inquiries from Gmail
- **AI-Powered Extraction**: Extract inquiry details from PDF documents using Gemini AI
- **Quotation Generation**: Create and manage quotations with automatic pricing
- **Purchase Order Management**: Convert quotations to purchase orders
- **Multi-language Support**: Support for English and Tamil
- **Web & Mobile**: Flutter-based application that works on web, Android, and iOS

## Technology Stack

- **Framework**: Flutter
- **AI Service**: Google Gemini AI
- **Email**: Gmail API integration
- **Database**: SQLite (via sqflite)
- **State Management**: Riverpod

## Getting Started

### Prerequisites

- Flutter SDK (3.9.2 or higher)
- Dart SDK
- Gmail API credentials (OAuth2)
- Gemini API key

### Installation

1. Clone the repository:
```bash
git clone https://github.com/manikandavelraja/AI_QUOTATION_APP.git
cd AI_QUOTATION_APP
```

2. Navigate to the app directory:
```bash
cd po_processor_app
```

3. Install dependencies:
```bash
flutter pub get
```

4. Configure API keys:
   - Update `lib/core/constants/app_constants.dart` with your Gemini API key
   - Configure Gmail OAuth2 credentials for web in the same file

5. Run the application:
```bash
flutter run
```

## Project Structure

```
po_processor_app/
├── lib/
│   ├── core/           # Core utilities, constants, themes
│   ├── data/           # Data layer (services, repositories)
│   ├── domain/         # Domain entities and use cases
│   └── presentation/   # UI layer (screens, widgets, providers)
├── assets/             # Images, icons, locales
├── android/            # Android-specific files
├── ios/                # iOS-specific files
└── web/                # Web-specific files
```

## Key Features

### Customer Email Extraction
- Automatically extracts customer email from Gmail messages
- Falls back to PDF extraction if email not found in headers
- Validates email addresses to ensure correct customer identification

### Inquiry Processing
- Fetches inquiry emails from Gmail automatically
- Extracts inquiry details from PDF attachments using AI
- Matches items with catalog for automatic pricing

### Quotation Management
- Generate quotations with automatic VAT calculation
- Email quotations directly to customers
- Track quotation status and validity

## Configuration

### Gmail API Setup
1. Create a project in Google Cloud Console
2. Enable Gmail API
3. Create OAuth2 credentials
4. Add authorized JavaScript origins and redirect URIs
5. Update `app_constants.dart` with your Client ID

### Gemini AI Setup
1. Get API key from Google AI Studio
2. Update `geminiApiKey` in `app_constants.dart`

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is private and proprietary.

## Author

manikandavelraja

## Support

For issues and questions, please open an issue on GitHub.

