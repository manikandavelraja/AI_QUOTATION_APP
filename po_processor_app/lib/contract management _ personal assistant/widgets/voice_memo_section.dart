import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/voice_recorder_service.dart';
import '../services/gemini_service.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
import '../models/analysis_result.dart';
import '../providers/language_provider.dart';
import 'result_card.dart';
import '../utils/logger.dart';

class VoiceMemoSection extends StatefulWidget {
  final Function(AnalysisResult)? onResultSaved;
  
  const VoiceMemoSection({
    super.key,
    this.onResultSaved,
  });

  @override
  State<VoiceMemoSection> createState() => _VoiceMemoSectionState();
}

class _VoiceMemoSectionState extends State<VoiceMemoSection> {
  final VoiceRecorderService _recorderService = VoiceRecorderService();
  final GeminiService _geminiService = GeminiService();
  final TranslationService _translationService = TranslationService();
  final TtsService _ttsService = TtsService();
  
  AnalysisResult? _voiceResult;
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _errorMessage;
  
  // Translation states
  final Map<String, String> _translatedSummaries = {};
  final Map<String, String> _translatedContents = {};
  final Map<String, bool> _isTranslating = {};

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
  }

  Future<void> _startRecording() async {
    try {
      final started = await _recorderService.startRecording();
      if (started && mounted) {
        setState(() {
          _isRecording = true;
          _errorMessage = null;
          _voiceResult = null;
        });
        AppLogger.info('Voice recording started');
      } else if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to start recording. Please check microphone permissions.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error starting recording', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final audioPath = await _recorderService.stopRecording();
      setState(() {
        _isRecording = false;
      });

      if (audioPath != null) {
        await _processAudio(audioPath);
      }
    } catch (e) {
      AppLogger.error('Error stopping recording', e);
      setState(() {
        _isRecording = false;
        _errorMessage = 'Error processing recording. Please try again.';
      });
    }
  }

  Future<void> _processAudio(String audioPath) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      AppLogger.info('Processing audio with Gemini: $audioPath');
      final result = await _geminiService.processVoiceAudio(audioPath);
      
      setState(() {
        _voiceResult = result;
        _isProcessing = false;
      });
      
      // Auto-translate if language is not English
      if (mounted) {
        final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
        if (languageProvider.locale.languageCode != 'en') {
          _translateResult(languageProvider.locale.languageCode);
        }
        
        // Notify parent about saved result
        if (widget.onResultSaved != null) {
          widget.onResultSaved!(result);
        }
      }
    } catch (e) {
      AppLogger.error('Error processing audio', e);
      setState(() {
        _isProcessing = false;
        _errorMessage = _getUserFriendlyError(e);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage ?? 'Error processing voice memo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _translateResult(String targetLang) async {
    if (_voiceResult == null || targetLang == 'en') {
      setState(() {
        _translatedSummaries.remove('voice');
        _translatedContents.remove('voice');
      });
      return;
    }

    setState(() {
      _isTranslating['voice'] = true;
    });

    try {
      final translatedSummary = await _translationService.translateText(
        _voiceResult!.summary,
        targetLang,
      );
      final translatedContent = await _translationService.translateText(
        _voiceResult!.detailedContent,
        targetLang,
      );

      setState(() {
        _translatedSummaries['voice'] = translatedSummary;
        _translatedContents['voice'] = translatedContent;
        _isTranslating['voice'] = false;
      });
    } catch (e) {
      AppLogger.error('Error translating voice result', e);
      setState(() {
        _isTranslating['voice'] = false;
      });
    }
  }

  Future<void> _speakText(String text, String languageCode) async {
    try {
      await _ttsService.setLanguage(languageCode);
      await _ttsService.speak(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to read text: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearResult() {
    setState(() {
      _voiceResult = null;
      _translatedSummaries.clear();
      _translatedContents.clear();
      _errorMessage = null;
    });
    _recorderService.cancelRecording();
  }

  String _getUserFriendlyError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Unable to connect to the server. Please check your internet connection and try again.';
    } else if (errorString.contains('api') || errorString.contains('key')) {
      return 'There was an issue with the service configuration. Please contact support if this continues.';
    } else if (errorString.contains('timeout')) {
      return 'The request took too long to process. Please try again with a shorter recording or check your connection.';
    } else if (errorString.contains('permission')) {
      return 'Please grant the necessary permissions to access your microphone.';
    } else {
      return 'Something went wrong while processing your voice memo. Please try again.';
    }
  }

  @override
  void dispose() {
    _recorderService.dispose();
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, _) {
        final targetLang = languageProvider.locale.languageCode;
        
        // Translate result if language changed and not already translated
        if (_voiceResult != null && !_translatedSummaries.containsKey('voice') && targetLang != 'en') {
          _translateResult(targetLang);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Voice Memo Recording Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Voice Memo',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (_voiceResult != null)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearResult,
                            tooltip: 'Clear result',
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Recording controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : (_isRecording ? _stopRecording : _startRecording),
                          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                          label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          ),
                        ),
                      ],
                    ),
                    
                    if (_isRecording) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: Column(
                          children: [
                            Icon(Icons.mic, color: Colors.red, size: 48),
                            SizedBox(height: 8),
                            Text(
                              'Recording...',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    if (_isProcessing) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('Processing audio with Gemini...'),
                          ],
                        ),
                      ),
                    ],
                    
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Voice Analysis Result
            if (_voiceResult != null) ...[
              const SizedBox(height: 24),
              Text(
                'Voice Analysis Result',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ResultCard(
                result: _voiceResult!,
                summary: _translatedSummaries['voice'] ?? _voiceResult!.summary,
                content: _translatedContents['voice'] ?? _voiceResult!.detailedContent,
                isTranslating: _isTranslating['voice'] ?? false,
                onSpeak: (text) => _speakText(text, targetLang),
              ),
            ],
          ],
        );
      },
    );
  }
}
