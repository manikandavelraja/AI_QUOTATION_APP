import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';

class LanguageNotifier extends StateNotifier<String> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  LanguageNotifier() : super(AppConstants.defaultLanguage) {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final savedLanguage = await _storage.read(key: AppConstants.languageKey);
    if (savedLanguage != null && AppConstants.supportedLanguages.contains(savedLanguage)) {
      state = savedLanguage;
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (AppConstants.supportedLanguages.contains(languageCode)) {
      state = languageCode;
      await _storage.write(key: AppConstants.languageKey, value: languageCode);
    }
  }

  String get currentLanguage => state;
  bool get isEnglish => state == 'en';
  bool get isTamil => state == 'ta';
}

final languageProvider = StateNotifierProvider<LanguageNotifier, String>((ref) {
  return LanguageNotifier();
});

