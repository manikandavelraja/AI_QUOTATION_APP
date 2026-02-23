import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/gemini_service.dart';
import '../services/tts_service.dart';
import '../providers/language_provider.dart';
import '../providers/saved_results_provider.dart';
import '../models/analysis_result.dart';
import '../widgets/result_card.dart';
import '../widgets/language_toggle.dart';
import '../utils/logger.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';

class PDFAnalysisScreen extends StatefulWidget {
  /// When false, no app bar is shown (e.g. when embedded in hub with its own app bar).
  final bool showAppBar;

  const PDFAnalysisScreen({super.key, this.showAppBar = true});

  @override
  State<PDFAnalysisScreen> createState() => _PDFAnalysisScreenState();
}

class _PDFAnalysisScreenState extends State<PDFAnalysisScreen> {
  final GeminiService _geminiService = GeminiService();
  final TtsService _ttsService = TtsService();

  String? _selectedPdfPath;
  String? _pdfFileName;
  AnalysisResult? _pdfResult;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    AppLogger.info('PDFAnalysisScreen initialized');
  }

  Future<void> _pickPDF() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: kIsWeb, // On web, we need the bytes
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        String pdfPath;
        String fileName = file.name;

        if (kIsWeb) {
          // On web, use bytes to create data URL
          if (file.bytes != null) {
            final base64 = base64Encode(file.bytes!);
            pdfPath = 'data:application/pdf;base64,$base64';
          } else {
            throw Exception('PDF file bytes are not available');
          }
        } else {
          // On mobile, use file path
          if (file.path != null) {
            pdfPath = file.path!;
          } else {
            throw Exception('PDF file path is not available');
          }
        }

        setState(() {
          _selectedPdfPath = pdfPath;
          _pdfFileName = fileName;
          _pdfResult = null;
          _errorMessage = null;
        });

        AppLogger.info('PDF selected: $fileName');
      }
    } catch (e) {
      AppLogger.error('Error picking PDF', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load PDF. Please try again.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _analyzePDF() async {
    if (_selectedPdfPath == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _pdfResult = null;
    });

    try {
      AppLogger.info('Analyzing PDF: $_pdfFileName');
      final languageProvider =
          Provider.of<LanguageProvider>(context, listen: false);
      final result = await _geminiService.parsePDF(
        _selectedPdfPath!,
        languageCode: languageProvider.locale.languageCode,
      );

      setState(() {
        _pdfResult = result;
        _isProcessing = false;
      });

      // Auto-save result
      if (!mounted) return;
      final savedProvider =
          Provider.of<SavedResultsProvider>(context, listen: false);
      await savedProvider.saveImageResult(result, _selectedPdfPath!);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('PDF analyzed and saved!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      AppLogger.error('Error analyzing PDF', e);
      setState(() {
        _isProcessing = false;
        _errorMessage = _getUserFriendlyError(e);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage ?? 'Error analyzing PDF'),
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

  String _getUserFriendlyError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Unable to connect to the server. Please check your internet connection and try again.';
    } else if (errorString.contains('api') || errorString.contains('key')) {
      return 'There was an issue with the service configuration. Please contact support if this continues.';
    } else if (errorString.contains('timeout')) {
      return 'The request took too long to process. Please try again with a smaller PDF or check your connection.';
    } else {
      return 'Something went wrong while processing your PDF. Please try again.';
    }
  }

  Future<void> _deleteSavedResult(
    BuildContext context,
    SavedResultsProvider provider,
    int index,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
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

    if (confirmed != true) return;
    await provider.deleteResult(index);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Result deleted successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Consumer2<LanguageProvider, SavedResultsProvider>(
        builder: (context, languageProvider, savedProvider, _) {
          final targetLang = languageProvider.locale.languageCode;
          // Filter saved results to show only PDF/image results
          final pdfResults = savedProvider.savedResults
              .where((result) => result.type == ResultType.image)
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

                  // PDF Upload Section
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
                                'Upload PDF',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _pickPDF,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Select PDF'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_pdfFileName != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.picture_as_pdf,
                                      color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _pdfFileName!,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      setState(() {
                                        _selectedPdfPath = null;
                                        _pdfFileName = null;
                                        _pdfResult = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.grey.shade50,
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.picture_as_pdf,
                                    size: 48,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No PDF selected',
                                    style:
                                        TextStyle(color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Analyze Button
                  if (_selectedPdfPath != null)
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _analyzePDF,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.analytics),
                      label:
                          Text(_isProcessing ? 'Analyzing...' : 'Analyze PDF'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),

                  if (_isProcessing) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
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

                  const SizedBox(height: 24),

                  // PDF Analysis Result
                  if (_pdfResult != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PDF Analysis Result',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        ResultCard(
                          result: _pdfResult!,
                          imagePath: _selectedPdfPath,
                          fileName: _pdfFileName,
                          summary: _pdfResult!.summary,
                          content: _pdfResult!.detailedContent,
                          isTranslating: false,
                          onSpeak: (text) => _speakText(text, targetLang),
                        ),
                      ],
                    ),

                  // Saved PDF Results Section
                  if (pdfResults.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Divider(thickness: 2),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Saved PDF Results',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          '${pdfResults.length} ${pdfResults.length == 1 ? 'result' : 'results'}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...pdfResults.asMap().entries.map((entry) {
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
                                color: Colors.blue.shade50,
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
                                        Icons.picture_as_pdf,
                                        color: Colors.blue,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'PDF Analysis',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
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
                                imagePath: savedResult.thumbnailPath,
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
      );
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              centerTitle: false,
              title: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf),
                  SizedBox(width: 8),
                  Text('PDF Analysis'),
                ],
              ),
            )
          : null,
      body: body,
    );
  }
}
