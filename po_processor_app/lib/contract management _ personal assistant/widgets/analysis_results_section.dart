import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/analysis_result.dart';
import '../providers/language_provider.dart';
import '../services/translation_service.dart';
import '../services/translation_cache_service.dart';
import '../services/tts_service.dart';
import 'result_card.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class AnalysisResultsSection extends StatefulWidget {
  final List<AnalysisResult> results;
  final List<String> uploadedImages;

  const AnalysisResultsSection({
    super.key,
    required this.results,
    required this.uploadedImages,
  });

  @override
  State<AnalysisResultsSection> createState() => _AnalysisResultsSectionState();
}

class _AnalysisResultsSectionState extends State<AnalysisResultsSection> {
  final TranslationService _translationService = TranslationService();
  final TranslationCacheService _cacheService = TranslationCacheService();
  final TtsService _ttsService = TtsService();
  final Map<int, String> _translatedSummaries = {};
  final Map<int, String> _translatedContents = {};
  final Map<int, bool> _isTranslating = {};
  String? _lastLanguageCode;
  bool _isLoadingCache = false;

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
  }

  /// Generate a unique ID for a result based on its content and timestamp
  String _getResultId(int index, AnalysisResult result) {
    final content = '${result.summary}_${result.detailedContent}_${result.timestamp.millisecondsSinceEpoch}';
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // Use first 16 chars as ID
  }

  /// Load cached translations for the current language
  Future<void> _loadCachedTranslations(String targetLang) async {
    if (targetLang == 'en' || _isLoadingCache) return;
    
    setState(() {
      _isLoadingCache = true;
    });

    try {
      for (int i = 0; i < widget.results.length; i++) {
        final result = widget.results[i];
        final resultId = _getResultId(i, result);
        final cached = await _cacheService.getCachedTranslation(resultId, targetLang);
        
        if (cached != null && mounted) {
          setState(() {
            _translatedSummaries[i] = cached['summary']!;
            _translatedContents[i] = cached['content']!;
          });
        }
      }
    } catch (e) {
      // Ignore cache loading errors
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCache = false;
        });
      }
    }
  }

  Future<void> _translateResult(int index, AnalysisResult result, String targetLang) async {
    if (targetLang == 'en') {
      setState(() {
        _translatedSummaries.remove(index);
        _translatedContents.remove(index);
        _isTranslating.remove(index);
      });
      return;
    }

    // Check if already translating
    if (_isTranslating[index] == true) {
      return;
    }

    // Check cache first
    final resultId = _getResultId(index, result);
    final cached = await _cacheService.getCachedTranslation(resultId, targetLang);
    
    if (cached != null && mounted) {
      setState(() {
        _translatedSummaries[index] = cached['summary']!;
        _translatedContents[index] = cached['content']!;
      });
      return;
    }

    // Translate if not cached
    setState(() {
      _isTranslating[index] = true;
    });

    try {
      final translatedSummary = await _translationService.translateText(
        result.summary,
        targetLang,
      );
      final translatedContent = await _translationService.translateText(
        result.detailedContent,
        targetLang,
      );

      // Cache the translation
      await _cacheService.cacheTranslation(
        resultId,
        targetLang,
        translatedSummary,
        translatedContent,
      );

      if (mounted) {
        setState(() {
          _translatedSummaries[index] = translatedSummary;
          _translatedContents[index] = translatedContent;
          _isTranslating[index] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranslating[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Translation failed: ${e.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, _) {
        final targetLang = languageProvider.locale.languageCode;

        // Handle language change
        if (_lastLanguageCode != null && _lastLanguageCode != targetLang) {
          // Language changed - clear current translations and load/translate for new language
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (mounted) {
              setState(() {
                _translatedSummaries.clear();
                _translatedContents.clear();
                _isTranslating.clear();
                _lastLanguageCode = targetLang;
              });
              
              // Load cached translations or translate
              if (targetLang != 'en') {
                await _loadCachedTranslations(targetLang);
                
                // Translate any that weren't cached
                for (int i = 0; i < widget.results.length; i++) {
                  if (!_translatedSummaries.containsKey(i) && _isTranslating[i] != true) {
                    _translateResult(i, widget.results[i], targetLang);
                  }
                }
              }
            }
          });
        } else if (_lastLanguageCode == null) {
          // First load - initialize language and load cached translations
          _lastLanguageCode = targetLang;
          if (targetLang != 'en') {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await _loadCachedTranslations(targetLang);
              
              // Translate any that weren't cached
              if (mounted) {
                for (int i = 0; i < widget.results.length; i++) {
                  if (!_translatedSummaries.containsKey(i) && _isTranslating[i] != true) {
                    _translateResult(i, widget.results[i], targetLang);
                  }
                }
              }
            });
          }
        } else {
          // Same language - just ensure all results are translated/cached
          if (targetLang != 'en') {
            for (int i = 0; i < widget.results.length; i++) {
              if (!_translatedSummaries.containsKey(i) && _isTranslating[i] != true) {
                _translateResult(i, widget.results[i], targetLang);
              }
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analysis Results',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ...List.generate(widget.results.length, (index) {
              final result = widget.results[index];
              final imagePath = index < widget.uploadedImages.length
                  ? widget.uploadedImages[index]
                  : null;
              
              final displaySummary = _translatedSummaries[index] ?? result.summary;
              final displayContent = _translatedContents[index] ?? result.detailedContent;
              final isTranslating = _isTranslating[index] ?? false;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ResultCard(
                  result: result,
                  imagePath: imagePath,
                  summary: displaySummary,
                  content: displayContent,
                  isTranslating: isTranslating,
                  onSpeak: (text) => _speakText(text, targetLang),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

