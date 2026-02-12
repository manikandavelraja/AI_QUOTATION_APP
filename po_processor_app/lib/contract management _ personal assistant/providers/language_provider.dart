import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { english, tamil, hindi }

class LanguageProvider extends ChangeNotifier {
  AppLanguage _currentLanguage = AppLanguage.english;
  Locale _locale = const Locale('en', '');

  AppLanguage get currentLanguage => _currentLanguage;
  Locale get locale => _locale;

  LanguageProvider() {
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('language') ?? 'en';
      switch (languageCode) {
        case 'ta':
          _currentLanguage = AppLanguage.tamil;
          _locale = const Locale('ta', '');
          break;
        case 'hi':
          _currentLanguage = AppLanguage.hindi;
          _locale = const Locale('hi', '');
          break;
        default:
          _currentLanguage = AppLanguage.english;
          _locale = const Locale('en', '');
      }
      notifyListeners();
    } catch (e) {
      // Default to English if loading fails
      _currentLanguage = AppLanguage.english;
      _locale = const Locale('en', '');
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    _currentLanguage = language;
    switch (language) {
      case AppLanguage.tamil:
        _locale = const Locale('ta', '');
        break;
      case AppLanguage.hindi:
        _locale = const Locale('hi', '');
        break;
      case AppLanguage.english:
        _locale = const Locale('en', '');
        break;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', _locale.languageCode);
    } catch (e) {
      // Continue even if saving fails
    }
    
    notifyListeners();
  }

  String getLanguageName(AppLanguage language) {
    switch (language) {
      case AppLanguage.english:
        return 'English';
      case AppLanguage.tamil:
        return 'தமிழ்';
      case AppLanguage.hindi:
        return 'हिंदी';
    }
  }
}

