# MASTER PROMPT: AI-Powered Purchase Order & Quotation Processing System
## Enterprise-Grade, Sovereign AI, High-Security Application Development Guide

---

## 📋 EXECUTIVE SUMMARY

**Project Name**: ELEVATEIONIX - AI-Powered PO Processing & Quotation Management System  
**Version**: 1.0.0  
**Target**: Enterprise-grade, sovereign AI application with 100-year sustainability vision  
**Architecture**: Flutter PWA (Progressive Web App) - Multi-platform (Web, Mobile, Desktop)  
**AI Provider**: Google Gemini AI (Sovereign AI compliant configuration)  
**Security Level**: Enterprise-grade with end-to-end encryption

---

## 🎯 PRIMARY OBJECTIVES

### Core Mission
Build a **simple, friendly, error-free** application that:
- **Empowers dealers**, not confuses them
- Works with **minimal steps** and intuitive workflows
- Utilizes **AI effectively** for document processing and business intelligence
- Maintains **enterprise-grade security** and **sovereign AI compliance**
- Implements **sustainability** as a core DNA principle
- Designed for **100-year longevity** with scalable, maintainable architecture

### Business Value Proposition
1. **Automated PO Processing**: Eliminate manual data entry from PDF Purchase Orders
2. **AI-Powered Intelligence**: Extract, validate, and structure business data automatically
3. **Real-time Business Visibility**: Dashboard with daily business pulse and key metrics
4. **Proactive Alerts**: Automatic notifications for POs expiring within 7 days
5. **Multi-language Support**: Full Tamil and English localization
6. **Green Technology**: Built-in sustainability metrics and carbon footprint tracking

---

## 🏗️ ARCHITECTURE & TECHNOLOGY STACK

### Core Framework
- **Flutter SDK**: 3.9.2+ (Dart 3.9.2+)
- **Platform Support**: Web (PWA), Android, iOS, Desktop (Windows, macOS, Linux)
- **Architecture Pattern**: Clean Architecture (Domain-Driven Design)
  - **Presentation Layer**: UI/UX, State Management, Navigation
  - **Domain Layer**: Business Entities, Use Cases, Business Logic
  - **Data Layer**: Services, Repositories, Data Sources

### State Management
- **Primary**: Riverpod 2.5.1+ (Reactive, type-safe, testable)
- **Secondary**: Provider 6.1.2+ (Legacy support)
- **Navigation**: GoRouter 13.2.0+ (Declarative routing)

### AI & Machine Learning
- **AI Provider**: Google Gemini AI (gemini-2.5-flash model)
- **Integration**: google_generative_ai 0.4.7+
- **Use Cases**:
  - PDF document extraction and parsing
  - Natural language understanding
  - Data validation and structuring
  - Multi-language content generation
  - Sentiment analysis (for call recordings)
  - Document summarization

### Data Persistence
- **Primary Database**: SQLite (sqflite 2.3.2+)
- **Secure Storage**: flutter_secure_storage 9.0.0+
- **Local Preferences**: shared_preferences 2.2.2+
- **Web Storage**: IndexedDB (via SharedPreferences on web)

### Security & Encryption
- **Encryption**: AES-256 (encrypt 5.0.3+)
- **Hashing**: SHA-256 (crypto 3.0.3+)
- **Secure Storage**: Flutter Secure Storage for sensitive data
- **Key Management**: Environment variables (.env) with secure key rotation

### Localization & Internationalization
- **Framework**: easy_localization 3.0.4+
- **Supported Languages**: English (en), Tamil (ta)
- **Implementation**: JSON-based translation files
- **Features**: RTL support ready, dynamic language switching

### UI/UX Libraries
- **Charts**: fl_chart 0.66.0+ (Business intelligence visualization)
- **Typography**: google_fonts 6.2.1+
- **Icons**: Material Icons, Cupertino Icons
- **Image Handling**: cached_network_image 3.3.1+
- **Loading States**: shimmer 3.0.0+

### Communication & Integration
- **Email**: Gmail API (googleapis 13.1.0+)
- **HTTP Client**: dio 5.4.0+ (with retry logic)
- **PDF Generation**: pdf 3.11.1+, printing 5.13.2+
- **File Handling**: file_picker 6.1.1+

### Voice & Audio (Contract Management Module)
- **Recording**: record 5.1.2+
- **Speech-to-Text**: speech_to_text 7.0.0+
- **Text-to-Speech**: flutter_tts 4.0.2+
- **Audio Playback**: just_audio 0.9.36+

---

## 🔐 SECURITY REQUIREMENTS & SOVEREIGN AI STANDARDS

### 1. Data Security (Data at Rest)

#### Encryption Standards
- **Algorithm**: AES-256-GCM (Galois/Counter Mode) for authenticated encryption
- **Key Management**:
  - Keys stored in environment variables (`.env` file)
  - Keys NEVER committed to version control
  - Key rotation policy: Quarterly rotation recommended
  - Key derivation: PBKDF2 with 100,000+ iterations
- **Implementation**:
  ```dart
  // All sensitive data must be encrypted before storage
  - User passwords: SHA-256 hashed (never stored in plaintext)
  - API keys: Encrypted in secure storage
  - Personal data: AES-256 encrypted
  - Database fields: Encrypt sensitive columns
  ```

#### Secure Storage Requirements
- **Flutter Secure Storage**: Use for all credentials, tokens, API keys
- **Platform-specific secure storage**:
  - Android: KeyStore (hardware-backed when available)
  - iOS: Keychain Services
  - Web: Encrypted IndexedDB with secure key derivation
- **Database Encryption**: SQLite database encrypted at rest (SQLCipher recommended for production)

### 2. Data Security (Data in Motion)

#### Network Security
- **TLS/SSL**: Mandatory TLS 1.3 for all API communications
- **Certificate Pinning**: Implement certificate pinning for production
- **API Communication**:
  - All API calls over HTTPS only
  - No HTTP traffic allowed (except localhost for development)
  - API keys transmitted in headers, never in URL parameters
  - Request/response encryption for sensitive payloads

#### API Security
- **Authentication**: Token-based authentication (JWT recommended)
- **Authorization**: Role-based access control (RBAC)
- **Rate Limiting**: Implement rate limiting to prevent abuse
- **Input Validation**: All user inputs validated and sanitized
- **Output Encoding**: Prevent XSS attacks through proper encoding

### 3. Sovereign AI Compliance

#### Data Sovereignty
- **Data Residency**: Ensure data processing complies with local data residency laws
- **Data Localization**: Critical data must remain within specified geographic boundaries
- **Cross-border Restrictions**: No unauthorized data transfer across borders
- **Compliance Frameworks**:
  - GDPR (General Data Protection Regulation)
  - CCPA (California Consumer Privacy Act)
  - Local data protection laws (India: IT Act, DPDPA when applicable)

#### AI Model Governance
- **Model Transparency**: Document all AI models used, their purposes, and limitations
- **Bias Mitigation**: Regular audits for algorithmic bias
- **Explainable AI (XAI)**: All AI decisions must be explainable and auditable
- **Human-in-the-Loop**: Critical decisions require human oversight
- **Model Versioning**: Track and version all AI models used
- **Audit Trails**: Complete logging of all AI operations

#### Responsible AI Principles
1. **Fairness**: Ensure AI treats all users equitably
2. **Accountability**: Clear ownership of AI decisions
3. **Transparency**: Users informed about AI usage
4. **Privacy**: Minimal data collection, maximum privacy protection
5. **Safety**: AI systems must be safe and reliable
6. **Robustness**: AI must handle edge cases gracefully

### 4. Enterprise Security Standards

#### Authentication & Authorization
- **Multi-factor Authentication (MFA)**: Support for 2FA/TOTP (future enhancement)
- **Session Management**: Secure session tokens with expiration
- **Password Policy**:
  - Minimum 8 characters (12+ recommended for enterprise)
  - Require uppercase, lowercase, numbers, special characters
  - Password history (prevent reuse of last 5 passwords)
  - Account lockout after failed attempts (5 attempts, 30-minute lockout)

#### Access Control
- **Role-Based Access Control (RBAC)**:
  - Admin: Full system access
  - Manager: Department-level access
  - User: Limited access to own data
  - Guest: Read-only access
- **Principle of Least Privilege**: Users granted minimum necessary permissions
- **Audit Logging**: Log all access attempts, data modifications, and security events

#### Vulnerability Management
- **Dependency Scanning**: Regular security audits of all dependencies
- **Code Scanning**: Static analysis tools (SonarQube, CodeQL)
- **Penetration Testing**: Annual third-party security audits
- **Patch Management**: Critical security patches applied within 24 hours

### 5. Security Best Practices

#### Secure Coding Standards
- **Input Validation**: Validate and sanitize ALL user inputs
- **Output Encoding**: Encode all outputs to prevent injection attacks
- **Error Handling**: Never expose sensitive information in error messages
- **Secure Defaults**: Secure by default, opt-in for less secure features
- **Defense in Depth**: Multiple layers of security controls

#### Secrets Management
- **Environment Variables**: All secrets in `.env` files (gitignored)
- **No Hardcoded Secrets**: Zero tolerance for hardcoded API keys, passwords
- **Secret Rotation**: Regular rotation of all secrets and keys
- **Secret Scanning**: Automated scanning for accidentally committed secrets

#### Security Monitoring
- **Intrusion Detection**: Monitor for suspicious activities
- **Anomaly Detection**: Alert on unusual access patterns
- **Security Incident Response**: Defined procedures for security incidents
- **Regular Security Reviews**: Quarterly security architecture reviews

---

## 🏢 ENTERPRISE GUIDELINES & BEST PRACTICES

### 1. Code Quality Standards

#### Code Organization
```
lib/
├── core/                    # Core utilities, shared across app
│   ├── constants/           # App-wide constants
│   ├── security/            # Security utilities (encryption, hashing)
│   ├── theme/               # App theming (light/dark mode)
│   └── utils/               # Utility functions (router, helpers)
├── data/                    # Data layer
│   ├── services/            # Business logic services (AI, DB, Email)
│   ├── repositories/         # Data repositories (abstraction layer)
│   └── datasources/          # Data sources (local, remote)
├── domain/                   # Domain layer (business logic)
│   ├── entities/            # Business entities (PO, Quotation, etc.)
│   └── usecases/            # Business use cases
└── presentation/             # Presentation layer (UI)
    ├── screens/             # Full-page screens
    ├── widgets/             # Reusable UI components
    └── providers/           # State management providers
```

#### Coding Standards
- **Dart Style Guide**: Follow official Dart style guide
- **Naming Conventions**:
  - Classes: PascalCase (`PurchaseOrder`, `GeminiAIService`)
  - Variables/Functions: camelCase (`poNumber`, `extractPOData`)
  - Constants: lowerCamelCase with `k` prefix (`kDefaultTimeout`)
  - Files: snake_case (`purchase_order.dart`, `gemini_ai_service.dart`)
- **Documentation**: All public APIs must have documentation comments
- **Type Safety**: Prefer explicit types, avoid `dynamic` unless necessary
- **Null Safety**: Full null safety compliance, use nullable types appropriately

#### Code Review Requirements
- **Minimum 2 Approvals**: All code changes require 2+ approvals
- **Automated Checks**: All PRs must pass:
  - Linter checks (`flutter analyze`)
  - Unit tests (minimum 80% coverage)
  - Integration tests for critical paths
  - Security scans
- **Review Checklist**:
  - [ ] Security vulnerabilities addressed
  - [ ] Performance implications considered
  - [ ] Error handling implemented
  - [ ] Documentation updated
  - [ ] Tests added/updated
  - [ ] Accessibility considered
  - [ ] Localization strings added

### 2. Testing Standards

#### Test Pyramid
- **Unit Tests (70%)**: Test individual functions, classes, services
- **Widget Tests (20%)**: Test UI components in isolation
- **Integration Tests (10%)**: Test complete user flows

#### Testing Requirements
- **Coverage Target**: Minimum 80% code coverage
- **Critical Paths**: 100% coverage for:
  - Authentication flows
  - Payment processing (if applicable)
  - Data encryption/decryption
  - AI service integrations
- **Test Types**:
  - Unit tests for business logic
  - Widget tests for UI components
  - Integration tests for user journeys
  - Performance tests for critical operations
  - Security tests for authentication/authorization

#### Test Best Practices
- **Test Isolation**: Each test independent, no shared state
- **Mock External Dependencies**: Mock API calls, database, file system
- **Test Data**: Use factories for test data generation
- **Assertions**: Clear, descriptive assertions
- **Test Naming**: Descriptive test names explaining what is tested

### 3. Performance Standards

#### Performance Targets
- **App Launch Time**: < 2 seconds (cold start)
- **Screen Navigation**: < 300ms (smooth transitions)
- **API Response Time**: < 2 seconds (95th percentile)
- **Database Queries**: < 100ms (simple queries)
- **PDF Processing**: < 30 seconds (for typical PO)
- **Memory Usage**: < 200MB (typical usage)

#### Performance Optimization
- **Lazy Loading**: Load data on-demand, not all at once
- **Caching Strategy**: Cache frequently accessed data
- **Image Optimization**: Compress images, use appropriate formats
- **Code Splitting**: Split large files into smaller modules
- **Tree Shaking**: Remove unused code in production builds
- **Database Optimization**: Index frequently queried columns
- **Network Optimization**: Batch API calls, use pagination

#### Performance Monitoring
- **APM Tools**: Application Performance Monitoring
- **Metrics Tracking**: Track key performance metrics
- **Performance Budgets**: Set and enforce performance budgets
- **Regular Profiling**: Profile app regularly to identify bottlenecks

### 4. Scalability Requirements

#### Architecture Scalability
- **Horizontal Scaling**: Design for horizontal scaling (stateless services)
- **Database Scaling**: Plan for database sharding/partitioning
- **Caching Layer**: Implement distributed caching (Redis recommended)
- **Load Balancing**: Support for load balancing
- **Microservices Ready**: Architecture supports future microservices migration

#### Data Scalability
- **Pagination**: All list views paginated (default 20 items per page)
- **Lazy Loading**: Load data incrementally
- **Data Archival**: Archive old data to reduce database size
- **Database Optimization**: Regular database maintenance and optimization

### 5. Maintainability Standards

#### Documentation Requirements
- **README**: Comprehensive project README with setup instructions
- **API Documentation**: Document all public APIs
- **Architecture Documentation**: Document system architecture
- **Deployment Documentation**: Document deployment procedures
- **Troubleshooting Guide**: Common issues and solutions

#### Code Maintainability
- **DRY Principle**: Don't Repeat Yourself - extract common code
- **SOLID Principles**: Follow SOLID design principles
- **Design Patterns**: Use appropriate design patterns (Singleton, Factory, Repository, etc.)
- **Refactoring**: Regular refactoring to improve code quality
- **Technical Debt**: Track and address technical debt

---

## 🤖 RESPONSIBLE AI & RESPONSE AI STANDARDS

### 1. Responsible AI Framework

#### AI Ethics Principles
1. **Human-Centric**: AI augments human capabilities, doesn't replace human judgment
2. **Fairness**: AI systems treat all users fairly, without bias
3. **Transparency**: AI decisions are explainable and auditable
4. **Privacy**: AI respects user privacy and data protection
5. **Accountability**: Clear ownership and responsibility for AI decisions
6. **Reliability**: AI systems are robust, safe, and reliable

#### AI Governance
- **AI Ethics Board**: Establish AI ethics review board (for enterprise)
- **Model Documentation**: Document all AI models, their purposes, limitations
- **Bias Audits**: Regular audits for algorithmic bias
- **Impact Assessments**: Assess AI impact on users and business
- **Continuous Monitoring**: Monitor AI performance and behavior

### 2. Explainable AI (XAI) Requirements

#### Transparency Standards
- **Decision Explanations**: Provide explanations for AI decisions
- **Confidence Scores**: Display confidence scores for AI predictions
- **Uncertainty Indicators**: Show when AI is uncertain
- **Source Attribution**: Attribute AI outputs to source data/models

#### User Communication
- **AI Disclosure**: Clearly indicate when AI is being used
- **Limitations Disclosure**: Inform users about AI limitations
- **Error Handling**: Graceful handling of AI errors with user-friendly messages
- **Feedback Mechanisms**: Allow users to provide feedback on AI outputs

### 3. AI Response Standards

#### Response Quality
- **Accuracy**: AI responses must be accurate and reliable
- **Relevance**: Responses must be relevant to user queries
- **Completeness**: Responses must be complete and comprehensive
- **Timeliness**: Responses must be provided in reasonable time

#### Response Formatting
- **Structured Output**: Prefer structured (JSON) outputs for machine processing
- **Human-Readable**: Also provide human-readable summaries
- **Multi-language**: Support responses in user's preferred language
- **Accessibility**: Ensure AI responses are accessible (screen readers, etc.)

#### Error Handling
- **Graceful Degradation**: Fallback mechanisms when AI fails
- **Error Messages**: Clear, actionable error messages
- **Retry Logic**: Automatic retry with exponential backoff
- **User Notification**: Inform users of AI service issues

### 4. AI Safety & Security

#### Prompt Injection Prevention
- **Input Sanitization**: Sanitize all inputs to AI models
- **Prompt Validation**: Validate prompts before sending to AI
- **Output Validation**: Validate AI outputs before using
- **Rate Limiting**: Limit AI API calls to prevent abuse

#### Data Privacy in AI
- **Data Minimization**: Send only necessary data to AI services
- **Data Anonymization**: Anonymize sensitive data before AI processing
- **No Training on User Data**: Do not use user data to train models (unless explicitly consented)
- **Data Retention**: Delete AI-processed data after processing (unless required for business)

---

## 📱 FEATURE REQUIREMENTS

### 1. Authentication & Authorization

#### Default Credentials
- **Username**: `admin`
- **Password**: `admin123`
- **Security**: Password hashed with SHA-256, never stored in plaintext
- **Future Enhancement**: Support for multiple users, roles, MFA

#### Authentication Flow
1. User enters username and password
2. System validates credentials against secure storage
3. On success: Create secure session, redirect to dashboard
4. On failure: Show user-friendly error message (don't reveal if username exists)
5. Session management: Secure tokens with expiration

### 2. Purchase Order (PO) Processing

#### PO Upload & Processing
- **File Upload**: Support PDF files (max 10MB)
- **File Validation**: Validate file type, size, format
- **AI Extraction**: Use Gemini AI to extract:
  - PO Number
  - PO Date
  - Customer Information (name, address, contact)
  - Delivery Address
  - Terms & Conditions
  - Line Items (item code, description, quantity, unit price, total)
  - Total Amount
  - Tax Information
  - Expiry Date
- **Data Validation**: Validate extracted data for completeness and accuracy
- **User Review**: Allow user to review and edit extracted data before saving
- **Save to Database**: Store validated PO data securely

#### PO Management
- **PO List**: Display all POs with key information
- **PO Details**: View complete PO information
- **PO Search**: Search POs by number, customer, date
- **PO Filtering**: Filter by status, date range, customer
- **PO Editing**: Edit PO details (with audit trail)
- **PO Deletion**: Soft delete with confirmation

#### PO Expiry Alerts
- **Alert Threshold**: 7 days before expiry
- **Alert Display**: Dashboard notification, list view indicator
- **Alert Details**: Show PO number, customer, expiry date
- **Alert Actions**: Quick access to PO details

### 3. Customer Inquiry Management

#### Inquiry Processing
- **Email Integration**: Fetch inquiries from Gmail (optional)
- **PDF Upload**: Manual upload of inquiry PDFs
- **AI Extraction**: Extract inquiry details using Gemini AI
- **Catalog Matching**: Match inquiry items with product catalog
- **Automatic Pricing**: Apply catalog prices to inquiry items

#### Inquiry to Quotation
- **Quotation Generation**: Create quotation from inquiry
- **Price Calculation**: Automatic VAT/tax calculation
- **Quotation Numbering**: Automatic quotation number generation
- **Quotation PDF**: Generate PDF quotation
- **Email Quotation**: Send quotation via email

### 4. Quotation Management

#### Quotation Features
- **Create Quotation**: From inquiry or manually
- **Edit Quotation**: Modify quotation details
- **Quotation Status**: Track status (draft, sent, accepted, rejected)
- **Quotation Validity**: Set and track quotation validity period
- **Quotation PDF**: Generate professional PDF quotations
- **Email Integration**: Send quotations via email

#### Quotation to PO
- **PO Generation**: Convert accepted quotation to PO
- **Data Transfer**: Transfer all relevant data from quotation to PO
- **Status Update**: Update quotation status to "Converted to PO"

### 5. Dashboard & Analytics

#### Dashboard Metrics
- **Daily Business Pulse**: Key metrics for today
- **PO Statistics**: Total POs, pending, expiring, completed
- **Revenue Metrics**: Total revenue, pending revenue
- **Expiry Alerts**: Count of POs expiring within 7 days
- **Sustainability Metrics**: Paper saved, carbon footprint reduction

#### Visualizations
- **Charts**: Use fl_chart for data visualization
- **Trends**: Show trends over time (weekly, monthly)
- **Comparisons**: Compare periods (this month vs last month)
- **Drill-down**: Click charts to see detailed data

### 6. Contract Management & Personal Assistant

#### Call Recording & Analysis
- **Voice Recording**: Record calls for analysis
- **Speech-to-Text**: Convert audio to text
- **AI Analysis**: Analyze call content using Gemini AI:
  - Sentiment analysis
  - Topic extraction
  - Agent performance metrics
  - Customer satisfaction scores
  - Action items
- **Dashboard**: Comprehensive analytics dashboard
- **Multi-language**: Support for English, Tamil, Thanglish

#### PDF Analysis
- **PDF Upload**: Upload contracts, documents
- **AI Analysis**: Extract key information, summarize
- **Multi-language**: Analysis in user's preferred language

### 7. Localization (i18n)

#### Language Support
- **Primary Languages**: English (en), Tamil (ta)
- **Language Toggle**: Easy toggle between languages
- **Complete Coverage**: All UI elements, messages, errors localized
- **RTL Ready**: Architecture supports RTL languages (future)

#### Implementation
- **Translation Files**: JSON-based translation files
- **Dynamic Switching**: Change language without app restart
- **Context-Aware**: AI responses in user's language
- **Date/Number Formatting**: Locale-specific formatting

### 8. Sustainability Features

#### Green Technology Metrics
- **Paper Saved**: Track paper saved per PO processed
- **Carbon Footprint**: Calculate CO2 reduction
- **Digital Transformation**: Metrics on digitalization impact
- **Sustainability Dashboard**: Visualize sustainability impact

#### Implementation
- **Metrics Calculation**: Automatic calculation per transaction
- **Cumulative Tracking**: Track cumulative impact over time
- **Reporting**: Generate sustainability reports
- **Visualization**: Charts showing sustainability progress

---

## 🎨 UI/UX GUIDELINES

### 1. Design Principles

#### User Experience
- **Simplicity**: Simple, intuitive interface
- **Clarity**: Clear navigation, no confusion
- **Efficiency**: Minimal steps to complete tasks
- **Feedback**: Clear feedback for all user actions
- **Error Prevention**: Prevent errors through good design
- **Accessibility**: WCAG 2.1 AA compliance

#### Visual Design
- **Modern UI**: Clean, modern, professional design
- **Consistent**: Consistent design language throughout
- **Responsive**: Works on all screen sizes
- **Dark Mode**: Support for dark theme (future)
- **Branding**: Use provided logos and brand assets

### 2. Navigation Structure

#### Main Navigation
- **Dashboard**: Home screen with key metrics
- **PO Management**: Upload, list, detail screens
- **Inquiry Management**: Inquiry list, detail, upload
- **Quotation Management**: Quotation list, detail, create
- **Settings**: App settings, language, preferences
- **Contract Management**: Call recording, analysis (separate module)

#### Navigation Patterns
- **Bottom Navigation**: For main sections (mobile)
- **Drawer Navigation**: For secondary sections
- **Breadcrumbs**: Show navigation path
- **Back Button**: Consistent back navigation

### 3. Form Design

#### Input Fields
- **Labels**: Clear, descriptive labels
- **Placeholders**: Helpful placeholder text
- **Validation**: Real-time validation with clear error messages
- **Required Fields**: Clearly marked required fields
- **Help Text**: Contextual help where needed

#### Error Handling
- **Inline Errors**: Show errors near relevant fields
- **User-Friendly Messages**: Clear, actionable error messages
- **Validation Timing**: Validate on blur, not on every keystroke
- **Success Feedback**: Confirm successful actions

### 4. Responsive Design

#### Breakpoints
- **Mobile**: < 600px
- **Tablet**: 600px - 1024px
- **Desktop**: > 1024px

#### Adaptive Layouts
- **Mobile**: Single column, stacked layout
- **Tablet**: Two columns where appropriate
- **Desktop**: Multi-column, side-by-side layouts
- **Touch Targets**: Minimum 44x44px for touch devices

---

## 🔧 DEVELOPMENT GUIDELINES

### 1. Environment Setup

#### Required Tools
- **Flutter SDK**: 3.9.2 or higher
- **Dart SDK**: 3.9.2 or higher
- **IDE**: VS Code or Android Studio with Flutter extensions
- **Git**: Version control
- **Chrome**: For web development and testing

#### Environment Variables
Create `.env` file in `po_processor_app/` directory:
```env
# Gemini AI Configuration
GEMINI_API_KEY=your_gemini_api_key_here
GEMINI_MODEL=gemini-2.5-flash

# Email Configuration
EMAIL_ADDRESS=your_email@example.com
GMAIL_WEB_CLIENT_ID=your_gmail_oauth2_client_id

# Security
ENCRYPTION_KEY=your_secure_encryption_key_32_chars_minimum
```

**⚠️ CRITICAL**: Never commit `.env` file to version control!

### 2. Project Setup

#### Initial Setup
```bash
# Navigate to project directory
cd po_processor_app

# Install dependencies
flutter pub get

# Run code generation (if using code generation)
flutter pub run build_runner build

# Run the app
flutter run
```

#### Build Commands
```bash
# Web (PWA)
flutter build web --release

# Android
flutter build apk --release
flutter build appbundle --release

# iOS (Mac only)
flutter build ios --release
```

### 3. Code Organization

#### File Naming
- **Screens**: `snake_case` with `_screen.dart` suffix
- **Widgets**: `snake_case` with `_widget.dart` suffix
- **Services**: `snake_case` with `_service.dart` suffix
- **Models**: `snake_case` with `.dart` suffix
- **Providers**: `snake_case` with `_provider.dart` suffix

#### Import Organization
```dart
// 1. Dart SDK imports
import 'dart:async';
import 'dart:convert';

// 2. Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 3. Package imports
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

// 4. Project imports
import '../models/purchase_order.dart';
import '../services/gemini_ai_service.dart';
```

### 4. Error Handling

#### Error Handling Strategy
- **Try-Catch Blocks**: Wrap all async operations
- **User-Friendly Messages**: Never expose technical errors to users
- **Error Logging**: Log all errors for debugging
- **Graceful Degradation**: Provide fallbacks when services fail
- **Retry Logic**: Implement retry for transient failures

#### Error Message Guidelines
- **Clear**: Explain what went wrong in plain language
- **Actionable**: Tell user what they can do
- **Localized**: Error messages in user's language
- **Contextual**: Show errors near relevant UI elements

### 5. Logging Standards

#### Logging Levels
- **Debug**: Development debugging information
- **Info**: General information about app flow
- **Warning**: Potential issues that don't break functionality
- **Error**: Errors that affect functionality
- **Critical**: Critical errors requiring immediate attention

#### Logging Best Practices
- **No Sensitive Data**: Never log passwords, API keys, personal data
- **Structured Logging**: Use structured log format
- **Log Rotation**: Implement log rotation for production
- **Remote Logging**: Send critical errors to remote logging service (optional)

---

## 📊 QUALITY ASSURANCE

### 1. Code Quality

#### Linting
- **Flutter Lints**: Use `flutter_lints` package
- **Custom Rules**: Define project-specific linting rules
- **Pre-commit Hooks**: Run linter before commits (optional)
- **CI/CD Integration**: Run linter in CI/CD pipeline

#### Code Analysis
```bash
# Run analyzer
flutter analyze

# Fix auto-fixable issues
dart fix --apply
```

### 2. Testing

#### Test Structure
```
test/
├── unit/              # Unit tests
├── widget/            # Widget tests
└── integration/       # Integration tests
```

#### Running Tests
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/unit/gemini_ai_service_test.dart

# Run with coverage
flutter test --coverage
```

### 3. Performance Testing

#### Performance Metrics
- **Frame Rate**: Maintain 60 FPS
- **Memory Usage**: Monitor memory leaks
- **Battery Usage**: Optimize for battery efficiency
- **Network Usage**: Minimize data transfer

#### Profiling
```bash
# Profile app
flutter run --profile

# Performance overlay
flutter run --profile --enable-software-rendering
```

---

## 🚀 DEPLOYMENT & OPERATIONS

### 1. Build Configuration

#### Release Builds
- **Code Obfuscation**: Enable code obfuscation for release builds
- **Minification**: Minify JavaScript for web builds
- **Tree Shaking**: Remove unused code
- **Asset Optimization**: Optimize images and assets

#### Build Scripts
```bash
# Web build
flutter build web --release --web-renderer canvaskit

# Android build
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

### 2. Version Management

#### Versioning Strategy
- **Semantic Versioning**: MAJOR.MINOR.PATCH (e.g., 1.0.0)
- **Version Bumping**: Update version in `pubspec.yaml`
- **Changelog**: Maintain CHANGELOG.md
- **Git Tags**: Tag releases in Git

### 3. Monitoring & Analytics

#### Application Monitoring
- **Error Tracking**: Integrate error tracking (Sentry, Firebase Crashlytics)
- **Analytics**: Track user behavior (privacy-compliant)
- **Performance Monitoring**: Monitor app performance
- **User Feedback**: Collect user feedback

---

## 📝 DOCUMENTATION REQUIREMENTS

### 1. Code Documentation

#### Documentation Standards
- **Public APIs**: All public classes, methods, properties documented
- **Complex Logic**: Document complex algorithms and business logic
- **Examples**: Provide code examples for complex APIs
- **Dart Doc**: Use Dart documentation comments (`///`)

#### Example
```dart
/// Extracts Purchase Order data from PDF text using AI.
///
/// This method uses Google Gemini AI to extract structured data
/// from unstructured PDF text. It validates the extracted data
/// and returns a [PurchaseOrder] entity.
///
/// Throws [Exception] if PDF text is invalid or AI extraction fails.
///
/// Example:
/// ```dart
/// final po = await geminiService.extractPOData(pdfText);
/// print('PO Number: ${po.poNumber}');
/// ```
Future<PurchaseOrder> extractPOData(String pdfText) async {
  // Implementation
}
```

### 2. User Documentation

#### User Guides
- **Getting Started Guide**: How to use the app
- **Feature Guides**: Detailed guides for each feature
- **FAQ**: Frequently asked questions
- **Video Tutorials**: Optional video tutorials

### 3. Technical Documentation

#### Architecture Documentation
- **System Architecture**: High-level architecture diagram
- **Data Flow**: Document data flow through the system
- **API Documentation**: Document all APIs
- **Database Schema**: Document database structure

---

## 🔄 CONTINUOUS IMPROVEMENT

### 1. Code Reviews

#### Review Process
- **Pull Requests**: All changes via pull requests
- **Review Checklist**: Use review checklist
- **Automated Checks**: CI/CD runs automated checks
- **Approval Required**: Minimum 2 approvals for merge

### 2. Refactoring

#### Refactoring Guidelines
- **Regular Refactoring**: Schedule regular refactoring sessions
- **Technical Debt**: Track and address technical debt
- **Code Smells**: Identify and fix code smells
- **Performance**: Continuously optimize performance

### 3. Learning & Growth

#### Knowledge Sharing
- **Code Reviews**: Learn from code reviews
- **Tech Talks**: Share knowledge through tech talks
- **Documentation**: Document learnings and decisions
- **Best Practices**: Continuously update best practices

---

## ✅ ACCEPTANCE CRITERIA

### Functional Requirements
- [ ] User can log in with default credentials
- [ ] User can upload PO PDF and extract data automatically
- [ ] User can view, edit, and manage POs
- [ ] User can process customer inquiries
- [ ] User can generate quotations
- [ ] User can view dashboard with key metrics
- [ ] User can toggle between English and Tamil
- [ ] User receives alerts for expiring POs
- [ ] All data is encrypted and stored securely
- [ ] AI responses are accurate and reliable

### Non-Functional Requirements
- [ ] App launches in < 2 seconds
- [ ] All screens load in < 300ms
- [ ] API calls complete in < 2 seconds (95th percentile)
- [ ] App works on mobile, tablet, and desktop
- [ ] App is accessible (WCAG 2.1 AA)
- [ ] Code coverage > 80%
- [ ] Zero critical security vulnerabilities
- [ ] All secrets stored securely (no hardcoded values)

### Quality Requirements
- [ ] All code follows Dart style guide
- [ ] All public APIs documented
- [ ] All tests passing
- [ ] No linter errors
- [ ] Performance targets met
- [ ] Security standards met
- [ ] Accessibility standards met

---

## 🎯 SUCCESS METRICS

### Business Metrics
- **PO Processing Time**: Reduce from manual (hours) to automated (minutes)
- **Data Accuracy**: > 95% accuracy in AI extraction
- **User Satisfaction**: > 4.5/5 user rating
- **Adoption Rate**: > 80% of users actively using the app

### Technical Metrics
- **Uptime**: > 99.9% availability
- **Error Rate**: < 0.1% error rate
- **Performance**: All performance targets met
- **Security**: Zero security incidents

### Sustainability Metrics
- **Paper Saved**: Track cumulative paper saved
- **Carbon Reduction**: Track CO2 reduction
- **Digital Transformation**: Measure digitalization impact

---

## 📞 SUPPORT & MAINTENANCE

### Support Channels
- **Documentation**: Comprehensive documentation
- **Issue Tracking**: GitHub issues for bug reports
- **Email Support**: Email support for enterprise customers
- **Community**: Community forum (if applicable)

### Maintenance Plan
- **Regular Updates**: Monthly feature updates
- **Security Patches**: Immediate security patches
- **Bug Fixes**: Weekly bug fix releases
- **Performance Optimization**: Continuous performance improvements

---

## 🔮 FUTURE ENHANCEMENTS

### Short-term (3-6 months)
- Multi-user support with roles
- Advanced analytics and reporting
- Email integration improvements
- Mobile app optimization
- Dark mode support

### Medium-term (6-12 months)
- Multi-factor authentication
- Advanced AI features (predictive analytics)
- API for third-party integrations
- Advanced search and filtering
- Customizable dashboards

### Long-term (12+ months)
- Microservices architecture
- Machine learning model training
- Advanced business intelligence
- Integration with ERP systems
- Mobile native apps (iOS/Android)

---

## 📚 REFERENCES & RESOURCES

### Official Documentation
- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Google Gemini AI](https://ai.google.dev/)
- [Riverpod Documentation](https://riverpod.dev/)

### Security Resources
- [OWASP Mobile Top 10](https://owasp.org/www-project-mobile-top-10/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [GDPR Compliance Guide](https://gdpr.eu/)

### Best Practices
- [Flutter Best Practices](https://flutter.dev/docs/development/best-practices)
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)

---

## 📄 LICENSE & COMPLIANCE

### License
This project is **private and proprietary**. All rights reserved.

### Compliance
- **GDPR**: Compliant with General Data Protection Regulation
- **Data Protection**: Compliant with local data protection laws
- **AI Ethics**: Follows responsible AI principles
- **Security Standards**: Meets enterprise security standards

---

## 🎓 CONCLUSION

This master prompt serves as the **comprehensive guide** for developing, maintaining, and evolving the ELEVATEIONIX AI-Powered PO Processing System. It emphasizes:

1. **Enterprise-Grade Security**: Sovereign AI compliance, end-to-end encryption
2. **Best Practices**: Industry-standard coding, testing, and deployment practices
3. **User-Centric Design**: Simple, intuitive, error-free user experience
4. **Sustainability**: Green technology built into the DNA
5. **Long-term Vision**: Architecture designed for 100-year sustainability

**Remember**: The goal is to build a **simple, friendly, error-free app that empowers dealers, not confuses them**. Every decision should align with this core principle while maintaining the highest standards of security, quality, and sustainability.

---

**Document Version**: 1.0.0  
**Last Updated**: 2024  
**Maintained By**: Development Team  
**Review Cycle**: Quarterly

---

*This document is a living document and should be updated as the project evolves.*
