import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../models/analysis_result.dart';
import '../services/gemini_service.dart';
import '../utils/logger.dart';

class AppProvider extends ChangeNotifier {
  final GeminiService _geminiService = GeminiService();
  
  List<String> _uploadedImages = [];
  List<AnalysisResult> _analysisResults = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<String> get uploadedImages => _uploadedImages;
  List<AnalysisResult> get analysisResults => _analysisResults;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void addImage(String imagePath) {
    if (!_uploadedImages.contains(imagePath)) {
      _uploadedImages.add(imagePath);
      notifyListeners();
      AppLogger.info('Image added: $imagePath');
    }
  }

  void removeImage(int index) {
    if (index >= 0 && index < _uploadedImages.length) {
      _uploadedImages.removeAt(index);
      if (index < _analysisResults.length) {
        _analysisResults.removeAt(index);
      }
      notifyListeners();
      AppLogger.info('Image removed at index: $index');
    }
  }

  void clearAllImages() {
    _uploadedImages.clear();
    _analysisResults.clear();
    _errorMessage = null;
    notifyListeners();
    AppLogger.info('All images cleared');
  }

  void syncImages(List<String> images) {
    _uploadedImages = List<String>.from(images);
    // Clear results if images were removed
    if (_analysisResults.length > _uploadedImages.length) {
      _analysisResults = _analysisResults.take(_uploadedImages.length).toList();
    }
    notifyListeners();
    AppLogger.info('Images synced: ${_uploadedImages.length} images');
  }

  Future<void> analyzeImages(String languageCode) async {
    if (_uploadedImages.isEmpty) {
      _errorMessage = 'Please upload at least one image to analyze';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _analysisResults.clear();
    notifyListeners();

    try {
      AppLogger.info('Starting analysis of ${_uploadedImages.length} images in language: $languageCode');
      
      for (int i = 0; i < _uploadedImages.length; i++) {
        final imagePath = _uploadedImages[i];
        AppLogger.info('Analyzing image $i: $imagePath');
        
        final result = await _geminiService.analyzeImage(imagePath, languageCode: languageCode);
        _analysisResults.add(result);
        notifyListeners();
      }

      AppLogger.info('Analysis completed successfully');
    } catch (e) {
      AppLogger.error('Error during image analysis', e);
      _errorMessage = _getUserFriendlyError(e);
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _getUserFriendlyError(dynamic error) {
    // 403 = invalid API key, quota, or API not enabled
    if (error is DioException && error.response?.statusCode == 403) {
      return 'Access denied (403). Check your .env: set GEMINI_API_KEY to a valid key and ensure the Gemini API is enabled in Google AI Studio / Google Cloud.';
    }
    final errorString = error.toString().toLowerCase();
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Unable to connect to the server. Check your internet connection and try again.';
    } else if (errorString.contains('api') || errorString.contains('key') || errorString.contains('403')) {
      return 'Invalid API key or access denied. Set GEMINI_API_KEY in .env and enable the Gemini API in Google AI Studio.';
    } else if (errorString.contains('timeout')) {
      return 'The request took too long. Try a smaller image or check your connection.';
    } else if (errorString.contains('permission')) {
      return 'Please grant the necessary permissions to access your images.';
    } else {
      return 'Something went wrong while processing your images. Please try again.';
    }
  }

  AnalysisResult? getResultForImage(int index) {
    if (index >= 0 && index < _analysisResults.length) {
      return _analysisResults[index];
    }
    return null;
  }
}

