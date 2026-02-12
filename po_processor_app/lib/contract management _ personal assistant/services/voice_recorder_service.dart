import 'dart:io' if (dart.library.html) '../io_stub.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class VoiceRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;

  Future<bool> requestPermission() async {
    try {
      if (kIsWeb) {
        // On web, browsers handle permissions when you try to access the microphone
        // The hasPermission() check will trigger the browser's permission dialog if needed
        // We'll check permission, and if it fails, we'll let the start() method handle it
        try {
          final hasPermission = await _audioRecorder.hasPermission();
          if (hasPermission) {
            AppLogger.info('Microphone permission granted (web)');
            return true;
          } else {
            // Permission not granted, but we'll try anyway - browser will prompt
            AppLogger.info('Microphone permission not yet granted, will prompt on start (web)');
            return true; // Return true to allow the start() to trigger the prompt
          }
        } catch (e) {
          AppLogger.warning('Permission check failed, will attempt recording anyway: $e');
          // On web, sometimes the permission check fails but recording still works
          // Return true to allow attempting the recording
          return true;
        }
      } else {
        // For mobile platforms, use permission_handler
        final status = await Permission.microphone.request();
        if (status.isGranted) {
          AppLogger.info('Microphone permission granted');
          return true;
        } else {
          AppLogger.warning('Microphone permission denied');
          return false;
        }
      }
    } catch (e) {
      AppLogger.error('Error requesting microphone permission', e);
      // On web, if permission check fails, still allow attempting recording
      // The browser will handle the permission prompt
      if (kIsWeb) {
        AppLogger.info('Allowing recording attempt despite permission check error (web)');
        return true;
      }
      return false;
    }
  }

  Future<bool> startRecording() async {
    try {
      // Request permission first (on web, this might not block)
      await requestPermission();

      // On web, we'll attempt to start recording even if permission check fails
      // The browser will show the permission dialog when we try to access the mic
      if (!kIsWeb) {
        // For mobile, check permission before starting
        final hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          AppLogger.warning('Recorder does not have permission');
          return false;
        }
      }

      // For web, use a temporary path that will be replaced with the actual blob URL
      if (kIsWeb) {
        // On web, the recorder will return a blob URL when stopped
        // We use a placeholder path that will be replaced
        _currentRecordingPath = 'web_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _currentRecordingPath!,
        );
      } else {
        // For mobile platforms, use file path
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _currentRecordingPath = '${directory.path}/recording_$timestamp.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _currentRecordingPath!,
        );
      }

      _isRecording = true;
      AppLogger.info('Recording started: $_currentRecordingPath');
      return true;
    } catch (e) {
      AppLogger.error('Error starting recording', e);
      _isRecording = false;
      _currentRecordingPath = null;
      return false;
    }
  }

  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) {
        return null;
      }

      final path = await _audioRecorder.stop();
      _isRecording = false;
      
      // On web, the path returned is typically a blob URL or data URL
      // Update our stored path with the actual returned path
      if (path != null) {
        _currentRecordingPath = path;
        AppLogger.info('Recording stopped: $path');
        return path;
      } else {
        // If no path returned, use the stored path (for web blob URLs)
        AppLogger.info('Recording stopped: $_currentRecordingPath');
        return _currentRecordingPath;
      }
    } catch (e) {
      AppLogger.error('Error stopping recording', e);
      _isRecording = false;
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        await _audioRecorder.stop();
        if (!kIsWeb && _currentRecordingPath != null) {
          final file = File(_currentRecordingPath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
        _isRecording = false;
        _currentRecordingPath = null;
        AppLogger.info('Recording cancelled');
      }
    } catch (e) {
      AppLogger.error('Error cancelling recording', e);
    }
  }

  Future<void> dispose() async {
    try {
      if (_isRecording) {
        await _audioRecorder.stop();
      }
      await _audioRecorder.dispose();
    } catch (e) {
      AppLogger.error('Error disposing recorder', e);
    }
  }
}

