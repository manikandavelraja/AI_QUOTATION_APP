import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../providers/language_provider.dart';
import '../providers/saved_results_provider.dart';
import '../widgets/image_upload_section.dart';
import '../widgets/language_toggle.dart';
import '../widgets/analysis_results_section.dart';
import '../utils/logger.dart';

/// Image Analysis screen – same workflow as Secure_Vision:
/// upload images, select language, analyze, view results (with optional save).
class ImageAnalysisScreen extends StatefulWidget {
  /// When false, no app bar is shown (e.g. when embedded in hub with its own app bar).
  final bool showAppBar;

  const ImageAnalysisScreen({super.key, this.showAppBar = true});

  @override
  State<ImageAnalysisScreen> createState() => _ImageAnalysisScreenState();
}

class _ImageAnalysisScreenState extends State<ImageAnalysisScreen> {
  @override
  void initState() {
    super.initState();
    AppLogger.info('ImageAnalysisScreen initialized');
  }

  @override
  Widget build(BuildContext context) {
    final body = Consumer3<AppProvider, LanguageProvider, SavedResultsProvider>(
        builder: (context, appProvider, languageProvider, savedProvider, _) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LanguageToggleWidget(),
                  const SizedBox(height: 24),
                  ImageUploadSection(
                    onImagesSelected: (images) {
                      appProvider.syncImages(images);
                    },
                  ),
                  const SizedBox(height: 24),
                  if (appProvider.uploadedImages.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: appProvider.isLoading
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await appProvider.analyzeImages(
                                  languageProvider.locale.languageCode);
                              if (mounted &&
                                  appProvider.errorMessage != null) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(appProvider.errorMessage!),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              } else if (mounted &&
                                  appProvider.analysisResults.isNotEmpty) {
                                for (int i = 0;
                                    i < appProvider.analysisResults.length;
                                    i++) {
                                  final result =
                                      appProvider.analysisResults[i];
                                  final imagePath =
                                      i < appProvider.uploadedImages.length
                                          ? appProvider.uploadedImages[i]
                                          : null;
                                  if (imagePath != null) {
                                    await savedProvider.saveImageResult(
                                        result, imagePath);
                                  }
                                }
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Analysis completed and saved!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                      icon: appProvider.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : const Icon(Icons.analytics),
                      label: Text(appProvider.isLoading
                          ? 'Analyzing...'
                          : 'Analyze Images'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  if (appProvider.isLoading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 24),
                  if (appProvider.analysisResults.isNotEmpty)
                    AnalysisResultsSection(
                      results: appProvider.analysisResults,
                      uploadedImages: appProvider.uploadedImages,
                    ),
                  const SizedBox(height: 24),
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
                  Icon(Icons.image),
                  SizedBox(width: 8),
                  Text('Image Analysis'),
                ],
              ),
            )
          : null,
      body: body,
    );
  }
}
