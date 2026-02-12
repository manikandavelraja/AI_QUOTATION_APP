import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/saved_results_provider.dart';
import '../widgets/language_toggle.dart';
import '../widgets/voice_memo_section_enhanced.dart';
import '../models/analysis_result.dart';
import '../utils/logger.dart';
import '../widgets/result_card.dart';
import '../services/tts_service.dart';
import 'package:intl/intl.dart';

class VoiceMemoScreen extends StatefulWidget {
  const VoiceMemoScreen({super.key});

  @override
  State<VoiceMemoScreen> createState() => _VoiceMemoScreenState();
}

class _VoiceMemoScreenState extends State<VoiceMemoScreen> {
  final TtsService _ttsService = TtsService();

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    AppLogger.info('VoiceMemoScreen initialized');
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

  Future<void> _deleteSavedResult(
    BuildContext context,
    SavedResultsProvider provider,
    int index,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Result'),
        content: const Text(
          'Are you sure you want to delete this saved result?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await provider.deleteResult(index);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Result deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic),
            SizedBox(width: 8),
            Text('Voice Memo'),
          ],
        ),
      ),
      body: Consumer2<LanguageProvider, SavedResultsProvider>(
        builder: (context, languageProvider, savedProvider, _) {
          final targetLang = languageProvider.locale.languageCode;
          // Filter saved results to show only voice results
          final voiceResults = savedProvider.savedResults
              .where((result) => result.type == ResultType.voice)
              .toList();

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Language Toggle
                  const LanguageToggleWidget(),
                  const SizedBox(height: 24),

                  // Enhanced Voice Memo Section with modes
                  Builder(
                    builder: (context) {
                      final messenger = ScaffoldMessenger.of(context);
                      return VoiceMemoSectionEnhanced(
                        onShortNoteSaved: (result) async {
                          await savedProvider.saveVoiceResult(result);
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Short voice note analyzed and saved!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                        onMeetingSaved: (result) async {
                          // Convert meeting result to analysis result for saving
                          final analysisResult = AnalysisResult(
                            summary: result.summary,
                            detailedContent: result.detailedTranscription,
                            confidenceScore: result.confidenceScore,
                            imagePath: result.audioPath,
                            timestamp: result.timestamp,
                          );
                          await savedProvider.saveVoiceResult(analysisResult);
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Meeting conversation analyzed and saved!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),

                  // Saved Voice Results Section
                  if (voiceResults.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Divider(thickness: 2),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Saved Voice Results',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          '${voiceResults.length} ${voiceResults.length == 1 ? 'result' : 'results'}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...voiceResults.asMap().entries.map((entry) {
                      final savedResult = entry.value;
                      final result = savedResult.result;
                      // Find the actual index in the full savedResults list
                      final actualIndex = savedProvider.savedResults.indexOf(savedResult);
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header with timestamp and delete button
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.mic,
                                        color: Colors.purple,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Voice Memo',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        DateFormat('MMM dd, yyyy HH:mm')
                                            .format(result.timestamp),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        color: Colors.red,
                                        iconSize: 20,
                                        onPressed: () => _deleteSavedResult(
                                          context,
                                          savedProvider,
                                          actualIndex,
                                        ),
                                        tooltip: 'Delete',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Result content
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: ResultCard(
                                result: result,
                                summary: result.summary,
                                content: result.detailedContent,
                                isTranslating: false,
                                onSpeak: (text) => _speakText(text, targetLang),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
