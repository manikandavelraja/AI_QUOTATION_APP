import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/voice_recorder_service.dart';
import '../services/gemini_service.dart';
import '../services/tts_service.dart';
import '../models/analysis_result.dart';
import '../models/meeting_analysis_result.dart';
import '../providers/language_provider.dart';
import 'result_card.dart';
import '../utils/logger.dart';

enum VoiceMode { shortNote, meeting }

class VoiceMemoSectionEnhanced extends StatefulWidget {
  final Function(AnalysisResult)? onShortNoteSaved;
  final Function(MeetingAnalysisResult)? onMeetingSaved;

  const VoiceMemoSectionEnhanced({
    super.key,
    this.onShortNoteSaved,
    this.onMeetingSaved,
  });

  @override
  State<VoiceMemoSectionEnhanced> createState() =>
      _VoiceMemoSectionEnhancedState();
}

class _VoiceMemoSectionEnhancedState extends State<VoiceMemoSectionEnhanced> {
  final VoiceRecorderService _recorderService = VoiceRecorderService();
  final GeminiService _geminiService = GeminiService();
  final TtsService _ttsService = TtsService();

  VoiceMode _selectedMode = VoiceMode.shortNote;
  AnalysisResult? _shortNoteResult;
  MeetingAnalysisResult? _meetingResult;
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
  }

  Future<void> _startRecording() async {
    try {
      setState(() {
        _errorMessage = null;
      });
      
      final started = await _recorderService.startRecording();
      if (started && mounted) {
        setState(() {
          _isRecording = true;
          _errorMessage = null;
          _shortNoteResult = null;
          _meetingResult = null;
        });
        AppLogger.info('Voice recording started in ${_selectedMode.name} mode');
      } else if (!started && mounted) {
        final errorMsg = 'Unable to start recording. Please ensure microphone permissions are granted and try again.';
        setState(() {
          _errorMessage = errorMsg;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error starting recording', e);
      final errorMsg = _getRecordingError(e);
      if (mounted) {
        setState(() {
          _errorMessage = errorMsg;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  String _getRecordingError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('permission') || errorString.contains('denied')) {
      return 'Microphone permission is required. Please grant permission and try again.';
    } else if (errorString.contains('not found') || errorString.contains('device')) {
      return 'No microphone found. Please check your device settings.';
    } else if (errorString.contains('busy') || errorString.contains('in use')) {
      return 'Microphone is currently in use by another application.';
    } else {
      return 'Unable to start recording. Please try again or check your device settings.';
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
      final languageProvider =
          Provider.of<LanguageProvider>(context, listen: false);
      final languageCode = languageProvider.locale.languageCode;

      if (_selectedMode == VoiceMode.shortNote) {
        AppLogger.info('Processing short voice note: $audioPath');
        final result = await _geminiService.processShortVoiceNote(
          audioPath,
          languageCode: languageCode,
        );

        setState(() {
          _shortNoteResult = result;
          _isProcessing = false;
        });

        // Notify parent about saved result
        if (mounted && widget.onShortNoteSaved != null) {
          widget.onShortNoteSaved!(result);
        }
      } else {
        AppLogger.info('Processing meeting conversation: $audioPath');
        final result = await _geminiService.analyzeMeetingConversation(
          audioPath,
          languageCode: languageCode,
        );

        setState(() {
          _meetingResult = result;
          _isProcessing = false;
        });

        // Notify parent about saved result
        if (mounted && widget.onMeetingSaved != null) {
          widget.onMeetingSaved!(result);
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
      _shortNoteResult = null;
      _meetingResult = null;
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice Mode',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<VoiceMode>(
                      segments: const [
                        ButtonSegment<VoiceMode>(
                          value: VoiceMode.shortNote,
                          label: Text('Short Note\n(Billing)'),
                          icon: Icon(Icons.note),
                        ),
                        ButtonSegment<VoiceMode>(
                          value: VoiceMode.meeting,
                          label: Text('Meeting\nConversation'),
                          icon: Icon(Icons.groups),
                        ),
                      ],
                      selected: {_selectedMode},
                      onSelectionChanged: (Set<VoiceMode> newSelection) {
                        setState(() {
                          _selectedMode = newSelection.first;
                          _shortNoteResult = null;
                          _meetingResult = null;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedMode == VoiceMode.shortNote
                          ? 'Precise transcription for billing purposes - every word captured exactly'
                          : 'Complete meeting analysis with summary, important points, and popular words',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Recording Section
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
                          _selectedMode == VoiceMode.shortNote
                              ? 'Short Voice Note'
                              : 'Meeting Conversation',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        if (_shortNoteResult != null || _meetingResult != null)
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
                          onPressed: _isProcessing
                              ? null
                              : (_isRecording
                                  ? _stopRecording
                                  : _startRecording),
                          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                          label: Text(_isRecording
                              ? 'Stop Recording'
                              : 'Start Recording'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording
                                ? Colors.red
                                : Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 16),
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

            // Short Note Result
            if (_shortNoteResult != null) ...[
              const SizedBox(height: 24),
              Text(
                'Voice Note Result',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ResultCard(
                result: _shortNoteResult!,
                summary: _shortNoteResult!.summary,
                content: _shortNoteResult!.detailedContent,
                isTranslating: false,
                onSpeak: (text) => _speakText(text, targetLang),
              ),
            ],

            // Meeting Result
            if (_meetingResult != null) ...[
              const SizedBox(height: 24),
              Text(
                'Meeting Analysis Result',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _buildMeetingResultCard(_meetingResult!, targetLang),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMeetingResultCard(
      MeetingAnalysisResult result, String targetLang) {
    final displaySummary = result.summary;
    final displayContent = result.detailedTranscription;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Confidence Score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getConfidenceColor(result.confidenceScore)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _getConfidenceColor(result.confidenceScore),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.analytics,
                    size: 16,
                    color: _getConfidenceColor(result.confidenceScore),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Confidence: ${(result.confidenceScore * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getConfidenceColor(result.confidenceScore),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Summary Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up),
                  onPressed: () => _speakText(displaySummary, targetLang),
                  tooltip: 'Read summary',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                displaySummary,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

            const SizedBox(height: 16),

            // Important Points
            if (result.importantPoints.isNotEmpty) ...[
              Text(
                'Important Points',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              ...result.importantPoints.map((point) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            point,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
            ],

            // Popular Words
            if (result.popularWords.isNotEmpty) ...[
              Text(
                'Popular Words',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: result.popularWords
                    .map((word) => Chip(
                          label: Text(word),
                          backgroundColor: Colors.purple.shade50,
                          side: BorderSide(color: Colors.purple.shade200),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Detailed Transcription
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Detailed Transcription',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up),
                  onPressed: () => _speakText(displayContent, targetLang),
                  tooltip: 'Read transcription',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                displayContent,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }
}
