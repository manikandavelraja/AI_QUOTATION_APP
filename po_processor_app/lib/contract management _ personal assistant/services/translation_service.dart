import '../utils/logger.dart';
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

class TranslationService {
  final Dio _dio = Dio();
  final String _apiKey = AppConstants.geminiApiKey;

  TranslationService() {
    // Set longer timeouts for translation operations
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(seconds: 120);
    _dio.options.sendTimeout = const Duration(seconds: 60);
  }

  Future<String> translateText(String text, String targetLanguage) async {
    if (text.isEmpty) return text;

    try {
      AppLogger.info('Translating text to $targetLanguage');

      String targetLangName = 'English';
      switch (targetLanguage) {
        case 'ta':
          targetLangName = 'Tamil';
          break;
        case 'hi':
          targetLangName = 'Hindi';
          break;
        default:
          return text; // Return original if English
      }

      final prompt = '''
Translate the following text to $targetLangName. Preserve the original meaning, formatting, and structure exactly.

Text to translate:
$text

Provide only the translated text without any additional explanation or formatting.
''';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {
                'text': prompt
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.3,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 8192,
        }
      };

      final response = await _dio.post(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro-vision-latest:generateContent?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 120), // 2 minutes for translation
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final translatedText = response.data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? text;
        AppLogger.info('Translation completed');
        return translatedText.trim();
      } else {
        AppLogger.warning('Translation failed, returning original text');
        return text;
      }
    } catch (e) {
      AppLogger.error('Error in translation', e);
      return text; // Return original text on error
    }
  }
}

