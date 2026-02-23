import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/saved_results_provider.dart';
import '../providers/language_provider.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
import '../widgets/result_card.dart';
import '../utils/logger.dart';
import 'package:intl/intl.dart';

class SavedResultsScreen extends StatefulWidget {
  const SavedResultsScreen({super.key});

  @override
  State<SavedResultsScreen> createState() => _SavedResultsScreenState();
}

class _SavedResultsScreenState extends State<SavedResultsScreen> {
  final TranslationService _translationService = TranslationService();
  final TtsService _ttsService = TtsService();
  final Map<int, String> _translatedSummaries = {};
  final Map<int, String> _translatedContents = {};
  final Map<int, bool> _isTranslating = {};

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
  }

  Future<void> _translateResult(
      int index, String summary, String content, String targetLang) async {
    if (targetLang == 'en') {
      setState(() {
        _translatedSummaries.remove(index);
        _translatedContents.remove(index);
      });
      return;
    }

    setState(() {
      _isTranslating[index] = true;
    });

    try {
      final translatedSummary = await _translationService.translateText(
        summary,
        targetLang,
      );
      final translatedContent = await _translationService.translateText(
        content,
        targetLang,
      );

      setState(() {
        _translatedSummaries[index] = translatedSummary;
        _translatedContents[index] = translatedContent;
        _isTranslating[index] = false;
      });
    } catch (e) {
      AppLogger.error('Error translating result', e);
      setState(() {
        _isTranslating[index] = false;
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

  Future<void> _deleteResult(int index, SavedResultsProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Result'),
        content:
            const Text('Are you sure you want to delete this saved result?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.deleteResult(index);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Result deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _clearAllResults(SavedResultsProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Results'),
        content: const Text(
            'Are you sure you want to delete all saved results? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.clearAllResults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All results cleared'),
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
            Icon(Icons.history),
            SizedBox(width: 8),
            Text('Saved Results'),
          ],
        ),
        actions: [
          Consumer<SavedResultsProvider>(
            builder: (context, provider, _) {
              if (provider.savedResults.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Clear all',
                onPressed: () => _clearAllResults(provider),
              );
            },
          ),
        ],
      ),
      body: Consumer2<SavedResultsProvider, LanguageProvider>(
        builder: (context, savedProvider, languageProvider, _) {
          final results = savedProvider.savedResults;
          final targetLang = languageProvider.locale.languageCode;

          // Translate results if language changed
          for (int i = 0; i < results.length; i++) {
            if (!_translatedSummaries.containsKey(i) && targetLang != 'en') {
              _translateResult(
                i,
                results[i].result.summary,
                results[i].result.detailedContent,
                targetLang,
              );
            }
          }

          if (results.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No saved results yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Analyze images or record voice memos to see results here',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final savedResult = results[index];
              final result = savedResult.result;
              final displaySummary =
                  _translatedSummaries[index] ?? result.summary;
              final displayContent =
                  _translatedContents[index] ?? result.detailedContent;
              final isTranslating = _isTranslating[index] ?? false;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with type and timestamp
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: savedResult.type == ResultType.image
                            ? Colors.blue.shade50
                            : Colors.purple.shade50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                savedResult.type == ResultType.image
                                    ? Icons.image
                                    : Icons.mic,
                                color: savedResult.type == ResultType.image
                                    ? Colors.blue
                                    : Colors.purple,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                savedResult.type == ResultType.image
                                    ? 'Image Analysis'
                                    : 'Voice Memo',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: savedResult.type == ResultType.image
                                      ? Colors.blue.shade700
                                      : Colors.purple.shade700,
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
                                onPressed: () =>
                                    _deleteResult(index, savedProvider),
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
                        imagePath: savedResult.thumbnailPath,
                        summary: displaySummary,
                        content: displayContent,
                        isTranslating: isTranslating,
                        onSpeak: (text) => _speakText(text, targetLang),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
