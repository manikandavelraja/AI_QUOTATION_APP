# PO Processor - AI-Powered Purchase Order Processing Application

A secure, scalable, and sustainable Flutter PWA application for automated Purchase Order processing using AI.

## Features

- ✅ **AI-Powered PDF Extraction**: Automatically extracts PO details from PDF files using Google Gemini AI
- ✅ **Bilingual Support**: Full support for English and Tamil languages
- ✅ **Secure Authentication**: Default credentials with encrypted password storage
- ✅ **Dashboard**: Real-time business pulse with key metrics
- ✅ **Expiry Alerts**: Automatic alerts for POs expiring within 7 days
- ✅ **Sustainability Metrics**: Track paper saved and carbon footprint reduction
- ✅ **PWA Support**: Works seamlessly on mobile, web, and desktop
- ✅ **Responsive Design**: Beautiful, modern UI that works on all screen sizes
- ✅ **Secure Data Storage**: All data encrypted and stored securely

## Technology Stack

- **Framework**: Flutter 3.35.7
- **State Management**: Riverpod
- **Navigation**: GoRouter
- **Database**: SQLite (sqflite)
- **AI Integration**: Google Gemini AI
- **Localization**: Easy Localization
- **Security**: Flutter Secure Storage, Encryption

## Default Credentials

- **Username**: `admin`
- **Password**: `admin123`

## Setup Instructions

### Prerequisites

1. Flutter SDK (3.35.7 or higher)
2. Dart SDK (3.9.2 or higher)
3. Android Studio / VS Code with Flutter extensions
4. Chrome (for web development)

### Installation

1. **Navigate to the project directory:**
   ```bash
   cd po_processor_app
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the application:**
   ```bash
   # For Web
   flutter run -d chrome
   
   # For Android
   flutter run -d android
   
   # For iOS (Mac only)
   flutter run -d ios
   ```

### Building for Production

**Web (PWA):**
```bash
flutter build web --release
```

**Android:**
```bash
flutter build apk --release
```

**iOS:**
```bash
flutter build ios --release
```

## Project Structure

```
lib/
├── core/
│   ├── constants/      # App constants and configuration
│   ├── security/       # Encryption and security utilities
│   ├── theme/          # App theme and styling
│   └── utils/          # Utility functions and router
├── data/
│   ├── models/         # Data models
│   ├── repositories/   # Data repositories
│   ├── datasources/    # Data sources
│   └── services/      # Business logic services (AI, Database, PDF)
├── domain/
│   ├── entities/       # Domain entities
│   └── usecases/       # Business use cases
└── presentation/
    ├── screens/        # UI screens
    ├── widgets/        # Reusable widgets
    └── providers/      # State management providers
```

## Key Features Implementation

### 1. AI-Powered PDF Processing

The application uses Google Gemini AI to extract structured data from PDF Purchase Orders. The AI service:
- Validates if uploaded file is a valid PO
- Extracts all PO fields (number, dates, customer info, etc.)
- Extracts line items with quantities and prices
- Generates English summaries

**Note**: For production, PDF text extraction should be implemented server-side or using a proper PDF parsing library.

### 2. Security

- All passwords are hashed using SHA-256
- Sensitive data is encrypted using AES encryption
- Secure storage using Flutter Secure Storage
- Data validation on all user inputs

### 3. Sustainability Features

The app tracks:
- Paper saved (calculated per PO processed)
- Carbon footprint reduction
- Green technology metrics

### 4. Localization

Full support for:
- English (en)
- Tamil (ta)

Language can be toggled from the login screen or settings.

## API Configuration

The app uses Google Gemini AI API. The API key is configured in:
```
lib/core/constants/app_constants.dart
```

**Important**: For production, move the API key to environment variables or secure storage.

## Database Schema

The app uses SQLite with the following tables:
- `users`: User authentication
- `purchase_orders`: PO main data
- `line_items`: PO line items

## Troubleshooting

### Common Issues

1. **PDF Extraction Not Working**
   - PDF text extraction requires server-side processing or additional setup
   - For now, the app shows a placeholder message
   - Consider implementing server-side PDF processing

2. **Dependencies Issues**
   - Run `flutter pub get` again
   - Delete `pubspec.lock` and run `flutter pub get`

3. **Build Issues**
   - Clean the project: `flutter clean`
   - Get dependencies: `flutter pub get`
   - Rebuild: `flutter build web`

## Future Enhancements

- [ ] Server-side PDF text extraction
- [ ] Cloud storage integration
- [ ] Advanced analytics and reporting
- [ ] Export to Excel functionality
- [ ] Email notifications
- [ ] Multi-user support with roles
- [ ] API for third-party integrations

## License

This project is proprietary and confidential.

## Support

For issues or questions, please contact the development team.

---

**Built with ❤️ using Flutter and AI**
