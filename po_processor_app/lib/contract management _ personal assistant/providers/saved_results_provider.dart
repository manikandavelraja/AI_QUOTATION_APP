import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/analysis_result.dart';
import '../utils/logger.dart';

enum ResultType { image, voice }

class SavedResult {
  final AnalysisResult result;
  final ResultType type;
  final String? thumbnailPath; // For images, this is the image path; for voice, it's null

  SavedResult({
    required this.result,
    required this.type,
    this.thumbnailPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'result': result.toJson(),
      'type': type == ResultType.image ? 'image' : 'voice',
      'thumbnailPath': thumbnailPath,
    };
  }

  factory SavedResult.fromJson(Map<String, dynamic> json) {
    return SavedResult(
      result: AnalysisResult.fromJson(json['result']),
      type: json['type'] == 'image' ? ResultType.image : ResultType.voice,
      thumbnailPath: json['thumbnailPath'],
    );
  }
}

class SavedResultsProvider extends ChangeNotifier {
  List<SavedResult> _savedResults = [];
  static const String _storageKey = 'saved_analysis_results';

  List<SavedResult> get savedResults => List.unmodifiable(_savedResults);

  SavedResultsProvider() {
    _loadSavedResults();
  }

  Future<void> _loadSavedResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _savedResults = jsonList
            .map((json) => SavedResult.fromJson(json))
            .toList();
        notifyListeners();
        AppLogger.info('Loaded ${_savedResults.length} saved results');
      }
    } catch (e) {
      AppLogger.error('Error loading saved results', e);
    }
  }

  Future<void> _saveResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _savedResults.map((result) => result.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await prefs.setString(_storageKey, jsonString);
      AppLogger.info('Saved ${_savedResults.length} results to storage');
    } catch (e) {
      AppLogger.error('Error saving results', e);
    }
  }

  Future<void> saveImageResult(AnalysisResult result, String imagePath) async {
    final savedResult = SavedResult(
      result: result,
      type: ResultType.image,
      thumbnailPath: imagePath,
    );
    
    _savedResults.insert(0, savedResult); // Add to beginning
    await _saveResults();
    notifyListeners();
    AppLogger.info('Saved image analysis result');
  }

  Future<void> saveVoiceResult(AnalysisResult result) async {
    final savedResult = SavedResult(
      result: result,
      type: ResultType.voice,
    );
    
    _savedResults.insert(0, savedResult); // Add to beginning
    await _saveResults();
    notifyListeners();
    AppLogger.info('Saved voice analysis result');
  }

  Future<void> deleteResult(int index) async {
    if (index >= 0 && index < _savedResults.length) {
      _savedResults.removeAt(index);
      await _saveResults();
      notifyListeners();
      AppLogger.info('Deleted saved result at index $index');
    }
  }

  Future<void> clearAllResults() async {
    _savedResults.clear();
    await _saveResults();
    notifyListeners();
    AppLogger.info('Cleared all saved results');
  }
}

