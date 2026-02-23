import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/call_recording.dart';
import '../utils/logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class CallRecordingsProvider extends ChangeNotifier {
  // Store only minimal metadata in the list
  List<CallRecording> _recordings = [];
  // Store all large data separately in memory to avoid storage quota issues
  final Map<String, String> _filePaths = {}; // Store file paths in memory
  final Map<String, String> _transcripts = {};
  final Map<String, CallAnalysis> _analyses = {};
  static const String _storageKey = 'call_recordings_metadata';
  static const int _maxStorageSize = 100000; // 100KB limit for safety

  List<CallRecording> get recordings => List.unmodifiable(_recordings);

  CallRecordingsProvider() {
    _loadRecordings();
    // Clear any old corrupted storage on startup
    _clearOldStorageIfNeeded();
  }

  Future<void> _clearOldStorageIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Check if there's old storage with large data
      final oldKey = 'call_recordings';
      if (prefs.containsKey(oldKey)) {
        final oldData = prefs.getString(oldKey);
        if (oldData != null && oldData.length > 50000) {
          // Old data is too large, remove it
          await prefs.remove(oldKey);
          AppLogger.info('Cleared old large storage data');
        }
      }
    } catch (e) {
      AppLogger.error('Error clearing old storage', e);
    }
  }

  Future<void> _loadRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _recordings = jsonList.map((json) {
          // Load only minimal metadata (no filePath, transcript, or analysis)
          final id = json['id'] as String;
          return CallRecording(
            id: id,
            fileName: json['fileName'] as String? ?? 'Unknown',
            filePath: '', // Will be loaded from memory if available
            duration: Duration(seconds: json['duration'] as int? ?? 0),
            createdAt: DateTime.parse(json['createdAt'] as String),
            transcript: null,
            analysis: null,
          );
        }).toList();
        notifyListeners();
        AppLogger.info('Loaded ${_recordings.length} call recordings metadata');
      }
    } catch (e) {
      AppLogger.error('Error loading call recordings', e);
      // Clear corrupted data
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_storageKey);
      } catch (_) {}
    }
  }

  Future<void> _saveRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Save ONLY minimal metadata - never save filePath, transcript, or analysis
      final jsonList = _recordings.map((r) => <String, dynamic>{
        'id': r.id,
        'fileName': r.fileName,
        'duration': r.duration.inSeconds,
        'createdAt': r.createdAt.toIso8601String(),
      }).toList();
      
      final jsonString = jsonEncode(jsonList);
      
      // Check size before saving
      if (jsonString.length > _maxStorageSize) {
        // If too large, keep only the most recent 10 recordings
        AppLogger.warning('Storage size too large, keeping only recent recordings');
        final recentRecordings = _recordings.take(10).toList();
        final recentJsonList = recentRecordings.map((r) => <String, dynamic>{
          'id': r.id,
          'fileName': r.fileName,
          'duration': r.duration.inSeconds,
          'createdAt': r.createdAt.toIso8601String(),
        }).toList();
        final recentJsonString = jsonEncode(recentJsonList);
        await prefs.setString(_storageKey, recentJsonString);
        // Remove old recordings from memory
        _recordings = recentRecordings;
        AppLogger.info('Saved ${recentRecordings.length} recent recordings');
      } else {
        await prefs.setString(_storageKey, jsonString);
        AppLogger.info('Saved ${_recordings.length} recordings metadata to storage');
      }
    } catch (e) {
      AppLogger.error('Error saving recordings', e);
      // If storage fails completely, don't crash - just log the error
      // Data will remain in memory for the session
    }
  }

  Future<void> addRecording(CallRecording recording) async {
    // Create a minimal recording for storage (without filePath, transcript, analysis)
    final minimalRecording = CallRecording(
      id: recording.id,
      fileName: recording.fileName,
      filePath: '', // Don't store in the list
      duration: recording.duration,
      createdAt: recording.createdAt,
      transcript: null,
      analysis: null,
    );
    
    _recordings.insert(0, minimalRecording);
    
    // Store all large data separately in memory
    if (recording.filePath.isNotEmpty) {
      _filePaths[recording.id] = recording.filePath;
      AppLogger.info('Stored filePath for ${recording.id}: ${recording.filePath}');
    } else {
      AppLogger.warning('Recording ${recording.id} has empty filePath!');
    }
    if (recording.transcript != null) {
      _transcripts[recording.id] = recording.transcript!;
    }
    if (recording.analysis != null) {
      _analyses[recording.id] = recording.analysis!;
    }
    
    await _saveRecordings();
    notifyListeners();
    AppLogger.info('Added new call recording: ${recording.fileName}');
  }

  Future<void> updateRecording(String id, CallRecording updated) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      // Update only metadata in the list
      _recordings[index] = CallRecording(
        id: updated.id,
        fileName: updated.fileName,
        filePath: '', // Don't store in the list
        duration: updated.duration,
        createdAt: updated.createdAt,
        transcript: null,
        analysis: null,
      );
      
      // Store all large data separately in memory
      if (updated.filePath.isNotEmpty) {
        _filePaths[updated.id] = updated.filePath;
        AppLogger.info('Stored filePath for ${updated.id}: ${updated.filePath}');
      } else {
        AppLogger.warning('Updated recording ${updated.id} has empty filePath!');
      }
      if (updated.transcript != null) {
        _transcripts[updated.id] = updated.transcript!;
      }
      if (updated.analysis != null) {
        _analyses[updated.id] = updated.analysis!;
      }
      
      await _saveRecordings();
      notifyListeners();
      AppLogger.info('Updated call recording: $id');
    }
  }

  // Get recording with all data from memory
  CallRecording? getRecordingWithData(String id) {
    try {
      final recording = _recordings.firstWhere((r) => r.id == id);
      final filePath = _filePaths[id] ?? recording.filePath;
      AppLogger.info('Retrieving recording $id - filePath: ${filePath.isEmpty ? "EMPTY" : filePath}');
      AppLogger.info('_filePaths contains key $id: ${_filePaths.containsKey(id)}');
      if (_filePaths.containsKey(id)) {
        AppLogger.info('Stored filePath value: ${_filePaths[id]}');
      }
      return CallRecording(
        id: recording.id,
        fileName: recording.fileName,
        filePath: filePath, // Get from memory
        duration: recording.duration,
        createdAt: recording.createdAt,
        transcript: _transcripts[id],
        analysis: _analyses[id],
      );
    } catch (e) {
      AppLogger.error('Recording not found: $id', e);
      return null;
    }
  }

  Future<void> deleteRecording(String id) async {
    _recordings.removeWhere((r) => r.id == id);
    // Also remove from all memory maps
    _filePaths.remove(id);
    _transcripts.remove(id);
    _analyses.remove(id);
    await _saveRecordings();
    notifyListeners();
    AppLogger.info('Deleted call recording: $id');
  }

  // Clear all recordings and free memory
  Future<void> clearAllRecordings() async {
    _recordings.clear();
    _filePaths.clear();
    _transcripts.clear();
    _analyses.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      AppLogger.error('Error clearing storage', e);
    }
    notifyListeners();
    AppLogger.info('Cleared all call recordings');
  }

  Future<String?> pickAudioFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac'],
        withData: kIsWeb,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        String filePath;
        String fileName = file.name;

        if (kIsWeb) {
          if (file.bytes != null) {
            final base64 = base64Encode(file.bytes!);
            filePath = 'data:audio/mpeg;base64,$base64';
          } else {
            throw Exception('Audio file bytes are not available');
          }
        } else {
          if (file.path != null) {
            filePath = file.path!;
          } else {
            throw Exception('Audio file path is not available');
          }
        }

        // Get file duration (simplified - in production, use audio metadata)
        final duration = _estimateDuration(file.size);

        final recording = CallRecording(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fileName: fileName,
          filePath: filePath,
          duration: duration,
          createdAt: DateTime.now(),
        );

        await addRecording(recording);
        return recording.id;
      }
    } catch (e) {
      AppLogger.error('Error picking audio file', e);
    }
    return null;
  }

  Duration _estimateDuration(int fileSizeBytes) {
    // Rough estimation: ~1MB per minute for MP3
    final minutes = (fileSizeBytes / (1024 * 1024)).ceil();
    return Duration(minutes: minutes);
  }
}

