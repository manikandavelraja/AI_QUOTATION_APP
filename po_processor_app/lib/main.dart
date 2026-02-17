import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_router.dart';
import 'data/services/database_service.dart';
import 'data/services/email_service.dart';
import 'presentation/providers/language_provider.dart';
import 'contract management _ personal assistant/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ Environment variables loaded successfully');
  } catch (e) {
    debugPrint('⚠️ Warning: Could not load .env file: $e');
    debugPrint(
      '⚠️ Make sure .env file exists in the po_processor_app directory',
    );
    debugPrint('⚠️ You can copy .env.example to .env and fill in your values');
  }

  // Initialize logger first
  AppLogger.initialize();

  // Initialize localization first
  await EasyLocalization.ensureInitialized();

  // Initialize database/storage
  try {
    await DatabaseService.instance.database;
  } catch (e) {
    debugPrint('Database initialization error: $e');
  }

  // Initialize email app password if not already set
  // NOTE: For production, remove this and let users configure via settings
  try {
    final emailService = EmailService();
    final existingPassword = await emailService.getEmailPassword();
    if (existingPassword == null || existingPassword.isEmpty) {
      // Store the app password: kddh aiyq zjgf pzyo
      await emailService.setEmailPassword('kddh aiyq zjgf pzyo');
      debugPrint('✅ Email app password initialized');
    }
  } catch (e) {
    debugPrint('Email password initialization error: $e');
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ta')],
      path: 'assets/locales',
      fallbackLocale: const Locale('en'),
      useOnlyLangCode: true,
      child: const ProviderScope(child: POProcessorApp()),
    ),
  );
}

class POProcessorApp extends ConsumerStatefulWidget {
  const POProcessorApp({super.key});

  @override
  ConsumerState<POProcessorApp> createState() => _POProcessorAppState();
}

class _POProcessorAppState extends ConsumerState<POProcessorApp> {
  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);

    // Set locale based on language provider
    EasyLocalization.of(context)?.setLocale(Locale(language));

    return MaterialApp.router(
      title: 'ELEVATEIONIX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: Locale(language),
      routerConfig: AppRouter.router,
    );
  }
}
