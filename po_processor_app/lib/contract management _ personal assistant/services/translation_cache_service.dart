import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

class TranslationCacheService {
  static final TranslationCacheService _instance = TranslationCacheService._internal();
  factory TranslationCacheService() => _instance;
  TranslationCacheService._internal();

  static const String _prefix = 'translation_cache_';

  /// Generate a cache key for a result
  String _getCacheKey(String resultId, String languageCode, String type) {
    return '$_prefix${resultId}_${languageCode}_$type';
  }

  /// Cache a translation
  Future<void> cacheTranslation(
    String resultId,
    String languageCode,
    String summary,
    String content,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final summaryKey = _getCacheKey(resultId, languageCode, 'summary');
      final contentKey = _getCacheKey(resultId, languageCode, 'content');
      
      await prefs.setString(summaryKey, summary);
      await prefs.setString(contentKey, content);
      
      AppLogger.info('Cached translation for result $resultId in language $languageCode');
    } catch (e) {
      AppLogger.error('Error caching translation', e);
    }
  }

  /// Get cached translation
  Future<Map<String, String>?> getCachedTranslation(
    String resultId,
    String languageCode,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final summaryKey = _getCacheKey(resultId, languageCode, 'summary');
      final contentKey = _getCacheKey(resultId, languageCode, 'content');
      
      final cachedSummary = prefs.getString(summaryKey);
      final cachedContent = prefs.getString(contentKey);
      
      if (cachedSummary != null && cachedContent != null) {
        AppLogger.info('Retrieved cached translation for result $resultId in language $languageCode');
        return {
          'summary': cachedSummary,
          'content': cachedContent,
        };
      }
      
      return null;
    } catch (e) {
      AppLogger.error('Error getting cached translation', e);
      return null;
    }
  }

  /// Clear cached translations for a specific result
  Future<void> clearCacheForResult(String resultId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith('$_prefix${resultId}_'));
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      AppLogger.info('Cleared cache for result $resultId');
    } catch (e) {
      AppLogger.error('Error clearing cache', e);
    }
  }

  /// Clear all cached translations
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_prefix));
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      AppLogger.info('Cleared all translation cache');
    } catch (e) {
      AppLogger.error('Error clearing all cache', e);
    }
  }
}

