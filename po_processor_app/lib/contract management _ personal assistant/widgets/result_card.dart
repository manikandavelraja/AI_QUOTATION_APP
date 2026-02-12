import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/analysis_result.dart';
import 'dart:io';

class ResultCard extends StatelessWidget {
  final AnalysisResult result;
  final String? imagePath;
  final String? fileName;
  final String summary;
  final String content;
  final bool isTranslating;
  final Function(String) onSpeak;

  const ResultCard({
    super.key,
    required this.result,
    this.imagePath,
    this.fileName,
    required this.summary,
    required this.content,
    this.isTranslating = false,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image/PDF Preview
            if (imagePath != null)
              Builder(
                builder: (context) {
                  final isPdf = imagePath!.toLowerCase().endsWith('.pdf') ||
                      imagePath!.startsWith('data:application/pdf') ||
                      imagePath!.startsWith('data:application/pdf;base64');
                  
                  final exists = kIsWeb
                      ? (imagePath!.startsWith('http') ||
                          imagePath!.startsWith('data:'))
                      : File(imagePath!).existsSync();

                  if (!exists && !isPdf) return const SizedBox.shrink();

                  return Container(
                    width: double.infinity,
                    height: 200,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                      color: Colors.grey.shade100,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isPdf
                          ? _buildPdfPreview(context, imagePath!, fileName)
                          : (kIsWeb ||
                              imagePath!.startsWith('http') ||
                                  imagePath!.startsWith('data:'))
                          ? Image.network(
                              imagePath!,
                              fit: BoxFit.contain,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                    return _buildErrorPlaceholder();
                              },
                            )
                          : Image.file(
                              File(imagePath!),
                              fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildErrorPlaceholder();
                                  },
                            ),
                    ),
                  );
                },
              ),

            // Confidence Score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getConfidenceColor(result.confidenceScore)
                    .withOpacity(0.1),
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
                  onPressed: () => onSpeak(summary),
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
                summary,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

            const SizedBox(height: 16),

            // Detailed Content Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Detailed Content',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up),
                  onPressed: () => onSpeak(content),
                  tooltip: 'Read content',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isTranslating)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  content,
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

  Widget _buildPdfPreview(BuildContext context, String pdfPath, String? fileName) {
    // Extract filename from path if not provided
    String displayName = fileName ?? _extractFileName(pdfPath);
    
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.picture_as_pdf,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              displayName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'PDF Document',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  String _extractFileName(String path) {
    try {
      // Handle data URLs
      if (path.startsWith('data:')) {
        // For data URLs, try to extract from the path or return a default
        return 'document.pdf';
      }
      
      // Handle file paths
      if (path.contains('/')) {
        return path.split('/').last;
      } else if (path.contains('\\')) {
        return path.split('\\').last;
      }
      
      // If no separator found, return the path itself if it's short, otherwise default
      return path.length > 30 ? 'document.pdf' : path;
    } catch (e) {
      return 'document.pdf';
    }
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported,
              size: 48,
              color: Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              'Image not available',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

}
