import 'package:flutter_tts/flutter_tts.dart';
import '../utils/logger.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
      AppLogger.info('TTS Service initialized');
    } catch (e) {
      AppLogger.error('Error initializing TTS', e);
    }
  }

  Future<void> setLanguage(String languageCode) async {
    try {
      String ttsLanguage = 'en-US';
      switch (languageCode) {
        case 'ta':
          ttsLanguage = 'ta-IN';
          break;
        case 'hi':
          ttsLanguage = 'hi-IN';
          break;
        default:
          ttsLanguage = 'en-US';
      }
      await _flutterTts.setLanguage(ttsLanguage);
    } catch (e) {
      AppLogger.warning('Could not set TTS language to $languageCode, using default');
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    try {
      await initialize();
      await _flutterTts.speak(text);
      AppLogger.info('TTS: Speaking text');
    } catch (e) {
      AppLogger.error('Error in TTS speak', e);
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      AppLogger.error('Error stopping TTS', e);
    }
  }

  Future<void> pause() async {
    try {
      await _flutterTts.pause();
    } catch (e) {
      AppLogger.error('Error pausing TTS', e);
    }
  }

  // Note: completionHandler is a callback, not a stream
  // Use setCompletionHandler() to set up completion callback
  void setCompletionHandler(Function() handler) {
    _flutterTts.setCompletionHandler(handler);
  }
}

