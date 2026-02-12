import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';

class SpeechToTextService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  String _lastRecognizedText = '';

  bool get isListening => _isListening;
  String get lastRecognizedText => _lastRecognizedText;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          AppLogger.info('Speech recognition status: $status');
        },
        onError: (error) {
          AppLogger.error('Speech recognition error: $error.errorMsg');
        },
      );

      if (available) {
        _isInitialized = true;
        AppLogger.info('Speech to Text Service initialized');
        return true;
      } else {
        AppLogger.warning('Speech recognition not available');
        return false;
      }
    } catch (e) {
      AppLogger.error('Error initializing Speech to Text', e);
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        AppLogger.info('Microphone permission granted for STT');
        return true;
      } else {
        AppLogger.warning('Microphone permission denied for STT');
        return false;
      }
    } catch (e) {
      AppLogger.error('Error requesting microphone permission for STT', e);
      return false;
    }
  }

  Future<void> startListening({
    required Function(String text) onResult,
    String localeId = 'en_US',
  }) async {
    try {
      if (!_isInitialized) {
        final initialized = await initialize();
        if (!initialized) {
          throw Exception('Speech recognition not available');
        }
      }

      if (!await requestPermission()) {
        throw Exception('Microphone permission denied');
      }

      _lastRecognizedText = '';
      _isListening = true;

      await _speech.listen(
        onResult: (result) {
          _lastRecognizedText = result.recognizedWords;
          onResult(result.recognizedWords);
          if (result.finalResult) {
            _isListening = false;
            AppLogger.info('Speech recognition completed: $_lastRecognizedText');
          }
        },
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
        ),
      );

      AppLogger.info('Started listening for speech recognition');
    } catch (e) {
      AppLogger.error('Error starting speech recognition', e);
      _isListening = false;
      rethrow;
    }
  }

  Future<void> stopListening() async {
    try {
      if (_isListening) {
        await _speech.stop();
        _isListening = false;
        AppLogger.info('Stopped listening for speech recognition');
      }
    } catch (e) {
      AppLogger.error('Error stopping speech recognition', e);
    }
  }

  Future<void> cancelListening() async {
    try {
      if (_isListening) {
        await _speech.cancel();
        _isListening = false;
        _lastRecognizedText = '';
        AppLogger.info('Cancelled speech recognition');
      }
    } catch (e) {
      AppLogger.error('Error cancelling speech recognition', e);
    }
  }
}

