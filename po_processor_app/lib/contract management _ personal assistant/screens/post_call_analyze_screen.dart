import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../providers/call_recordings_provider.dart';
import '../services/call_analysis_service.dart';
import '../models/call_recording.dart';
import '../widgets/recording_gallery_item.dart';
import '../widgets/transcript_chat_bubble.dart';
import '../widgets/call_insights_dashboard.dart';
import '../widgets/comprehensive_call_dashboard.dart';
import 'package:po_processor/presentation/widgets/ai_disclaimer.dart';
import '../utils/logger.dart';

class PostCallAnalyzeScreen extends StatefulWidget {
  const PostCallAnalyzeScreen({super.key});

  @override
  State<PostCallAnalyzeScreen> createState() => _PostCallAnalyzeScreenState();
}

class _PostCallAnalyzeScreenState extends State<PostCallAnalyzeScreen>
    with SingleTickerProviderStateMixin {
  final CallAnalysisService _analysisService = CallAnalysisService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  CallRecording? _selectedRecording;
  bool _isTranscribing = false;
  bool _isAnalyzing = false;
  String? _analyzingRecordingId; // Track which recording is being analyzed
  bool _isPlaying = false;
  String? _currentlyPlayingId; // Track which recording is currently playing
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  String? _errorMessage;
  bool _showAggregateDashboard = false;
  bool _audioSessionConfigured = false;

  late TabController _tabController;
  final List<StreamSubscription<dynamic>> _streamSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    // Listen to player state changes (cancel on dispose)
    _streamSubscriptions.add(
      _audioPlayer.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state.playing;
          if (!state.playing &&
              state.processingState == ProcessingState.completed) {
            _currentlyPlayingId = null;
            _audioPosition = Duration.zero;
          }
        });
      }),
    );
    _streamSubscriptions.add(
      _audioPlayer.durationStream.listen((duration) {
        if (!mounted) return;
        setState(() {
          _audioDuration = duration ?? Duration.zero;
        });
      }),
    );
    _streamSubscriptions.add(
      _audioPlayer.positionStream.listen((position) {
        if (!mounted) return;
        setState(() => _audioPosition = position);
      }),
    );

    // Initialize hardcoded audio files
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeHardcodedRecordings();
    });
  }

  /// Configure audio session for mobile (iOS/Android) so playback works.
  Future<void> _ensureAudioSession() async {
    if (_audioSessionConfigured || kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.music());
      if (mounted) _audioSessionConfigured = true;
    } catch (e) {
      AppLogger.error('Audio session configuration failed', e);
    }
  }

  @override
  void dispose() {
    for (final sub in _streamSubscriptions) {
      sub.cancel();
    }
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initializeHardcodedRecordings() async {
    final provider = Provider.of<CallRecordingsProvider>(
      context,
      listen: false,
    );

    // Define hardcoded audio files
    final hardcodedRecordings = [
      {
        'id': 'mall_audio_english',
        'fileName': 'mall_audio_english.wav',
        'filePath': 'assets/audio/mall_audio_english.wav',
        'language': 'English',
        'duration': const Duration(minutes: 5, seconds: 32),
      },
      {
        'id': 'mall_audio_tamil',
        'fileName': 'mall_audio_tamil.wav',
        'filePath': 'assets/audio/mall_audio_tamil.wav',
        'language': 'Tamil',
        'duration': const Duration(minutes: 5, seconds: 32),
      },
      {
        'id': 'mall_audio_thanglish',
        'fileName': 'mall_audio_thanglish.wav',
        'filePath': 'assets/audio/mall_audio_thanglish.wav',
        'language': 'Tanglish',
        'duration': const Duration(minutes: 5, seconds: 32),
      },
      {
        'id': 'mall_audio_toxic',
        'fileName': 'mall_audio_toxic.wav',
        'filePath': 'assets/audio/mall_audio_toxic.wav',
        'language': 'English',
        'duration': const Duration(minutes: 5, seconds: 32),
      },
    ];

    // Check if recordings already exist, if not, add them
    // If they exist but don't have filePaths, update them
    for (final recordingData in hardcodedRecordings) {
      final recordingId = recordingData['id'] as String;
      final recordingExists = provider.recordings.any(
        (r) => r.id == recordingId,
      );

      // Check if existing recording has filePath
      final existingRecording = provider.getRecordingWithData(recordingId);
      final hasFilePath =
          existingRecording != null && existingRecording.filePath.isNotEmpty;

      if (!recordingExists) {
        // Recording doesn't exist, add it
        final recording = CallRecording(
          id: recordingId,
          fileName: recordingData['fileName'] as String,
          filePath: recordingData['filePath'] as String,
          duration: recordingData['duration'] as Duration,
          createdAt: DateTime.now().subtract(
            Duration(days: hardcodedRecordings.indexOf(recordingData)),
          ),
          language: recordingData['language'] as String?,
        );

        AppLogger.info(
          'Initializing recording: ${recording.fileName} with path: ${recording.filePath}',
        );
        await provider.addRecording(recording);

        // Verify the filePath was stored correctly
        final verifyRecording = provider.getRecordingWithData(recording.id);
        AppLogger.info(
          'Verified recording filePath: ${verifyRecording?.filePath ?? "NULL"}',
        );
        AppLogger.info(
          'Initialized hardcoded recording: ${recording.fileName}',
        );
      } else if (!hasFilePath) {
        // Recording exists but doesn't have filePath, update it
        AppLogger.info(
          'Recording ${recordingData['fileName']} exists but missing filePath, updating...',
        );
        final updatedRecording = CallRecording(
          id: recordingId,
          fileName: existingRecording!.fileName,
          filePath: recordingData['filePath'] as String,
          duration: existingRecording.duration,
          createdAt: existingRecording.createdAt,
          transcript: existingRecording.transcript,
          analysis: existingRecording.analysis,
          language: existingRecording.language,
        );
        await provider.updateRecording(recordingId, updatedRecording);
        AppLogger.info(
          'Updated recording ${recordingData['fileName']} with filePath: ${recordingData['filePath']}',
        );
      }
    }
  }

  Future<void> _transcribeRecording(CallRecording recording) async {
    if (recording.transcript != null) {
      // Already transcribed, just stop - don't auto-analyze
      return;
    }

    setState(() {
      _isTranscribing = true;
      _analyzingRecordingId = recording.id;
      _errorMessage = null;
    });

    try {
      AppLogger.info('Transcribing recording: ${recording.fileName}');
      // For now, use a placeholder transcript
      // In production, integrate with a real transcription service
      final transcript = await _analysisService.transcribeAudio(
        recording.filePath,
      );

      final updated = CallRecording(
        id: recording.id,
        fileName: recording.fileName,
        filePath: recording.filePath,
        duration: recording.duration,
        createdAt: recording.createdAt,
        transcript: transcript,
        analysis: null,
      );

      if (!mounted) return;
      final provider = Provider.of<CallRecordingsProvider>(
        context,
        listen: false,
      );
      await provider.updateRecording(recording.id, updated);

      if (!mounted) return;
      // Refresh selected recording with latest data from provider
      final refreshed = provider.getRecordingWithData(recording.id);
      if (refreshed != null) {
        setState(() {
          _selectedRecording = refreshed;
          _isTranscribing = false;
          _analyzingRecordingId =
              null; // Clear analyzing ID after transcription
        });
        // Transcription complete - STOP here, don't auto-analyze
        // User must explicitly click Analyze to proceed
      } else {
        setState(() {
          _isTranscribing = false;
          _analyzingRecordingId = null;
        });
      }
    } catch (e) {
      AppLogger.error('Error transcribing recording', e);
      setState(() {
        _isTranscribing = false;
        _analyzingRecordingId = null;
        _errorMessage = 'Failed to transcribe audio: ${e.toString()}';
      });
    }
  }

  Future<void> _analyzeRecording(
    CallRecording recording, {
    bool shouldNavigate = true,
    bool forceReAnalyze = false,
  }) async {
    // Check if transcript exists, if not, transcribe first
    if (recording.transcript == null) {
      // Need to transcribe first, then analyze
      await _transcribeRecording(recording);
      // Wait a bit for state to update
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      // After transcription, get the updated recording and analyze
      final provider = Provider.of<CallRecordingsProvider>(
        context,
        listen: false,
      );
      final refreshed = provider.getRecordingWithData(recording.id);
      if (refreshed != null && refreshed.transcript != null) {
        // Now analyze with the transcript
        await _analyzeRecording(
          refreshed,
          shouldNavigate: shouldNavigate,
          forceReAnalyze: forceReAnalyze,
        );
      }
      return;
    }

    // If already analyzed and has complete data, show pre-analyzed data (unless force re-analyze)
    if (recording.analysis != null && !forceReAnalyze) {
      // Validate that analysis has all required data
      if (_hasCompleteAnalysisData(recording.analysis!)) {
        if (shouldNavigate) {
          _selectRecording(recording);
        }
        return;
      } else {
        // Analysis exists but incomplete, force re-analyze
        AppLogger.warning('Analysis data incomplete, re-analyzing...');
      }
    }

    setState(() {
      _isAnalyzing = true;
      _analyzingRecordingId = recording.id;
      _errorMessage = null;
    });

    try {
      AppLogger.info('Analyzing recording: ${recording.fileName}');
      final messages = _analysisService.parseTranscript(recording.transcript!);
      final analysis = await _analysisService.analyzeCallTranscript(
        recording.transcript!,
        messages,
      );

      final updated = CallRecording(
        id: recording.id,
        fileName: recording.fileName,
        filePath: recording.filePath,
        duration: recording.duration,
        createdAt: recording.createdAt,
        transcript: recording.transcript,
        analysis: analysis,
      );

      if (!mounted) return;
      final provider = Provider.of<CallRecordingsProvider>(
        context,
        listen: false,
      );
      await provider.updateRecording(recording.id, updated);

      if (!mounted) return;
      // Refresh selected recording with latest data from provider
      final refreshed = provider.getRecordingWithData(recording.id);

      // Clear loading state
      setState(() {
        _isAnalyzing = false;
        _analyzingRecordingId = null;
      });

      // Only select recording if shouldNavigate is true and we have complete data
      if (shouldNavigate &&
          refreshed != null &&
          refreshed.analysis != null &&
          refreshed.transcript != null &&
          mounted) {
        // Small delay to ensure UI updates
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          _selectRecording(refreshed);
        }
      }
    } catch (e) {
      AppLogger.error('Error analyzing recording', e);
      setState(() {
        _isAnalyzing = false;
        _analyzingRecordingId = null;
        _errorMessage = 'Failed to analyze call: ${e.toString()}';
      });
    }
  }

  void _selectRecording(CallRecording recording) {
    // Clear all loading states before selecting
    setState(() {
      _isTranscribing = false;
      _isAnalyzing = false;
      _analyzingRecordingId = null;
      _selectedRecording = recording;
      // Reset to transcript tab when selecting a recording
      _tabController.animateTo(0);
    });
  }

  /// Validate that analysis has all required data for graphs
  bool _hasCompleteAnalysisData(CallAnalysis analysis) {
    // Check required fields
    if (analysis.sentimentScore.overall.isEmpty) return false;
    if (analysis.keyHighlights.issue.isEmpty) return false;
    if (analysis.keyHighlights.resolution.isEmpty) return false;
    if (analysis.keyHighlights.summary.isEmpty) return false;
    if (analysis.agentScore.rating < 1 || analysis.agentScore.rating > 10) {
      return false;
    }
    if (analysis.sentimentTrend.dataPoints.isEmpty) return false;
    if (analysis.topics.isEmpty) return false;
    if (analysis.agentPerformance.greeting < 0 ||
        analysis.agentPerformance.greeting > 10) {
      return false;
    }
    if (analysis.agentPerformance.problemSolving < 0 ||
        analysis.agentPerformance.problemSolving > 10) {
      return false;
    }
    if (analysis.agentPerformance.closing < 0 ||
        analysis.agentPerformance.closing > 10) {
      return false;
    }

    // Optional but recommended fields
    // wordCloud and loudnessTrend can be empty but should exist
    // agentTalkSeconds and customerTalkSeconds should be >= 0

    return true;
  }

  Future<void> _seekAudio(Duration position) async {
    try {
      await _audioPlayer.seek(position);
      setState(() {
        _audioPosition = position;
      });
    } catch (e) {
      AppLogger.error('Error seeking audio', e);
    }
  }

  Future<void> _playRecording(CallRecording recording) async {
    try {
      AppLogger.info('Attempting to play recording: ${recording.fileName}');
      AppLogger.info('File path: ${recording.filePath}');

      // On mobile (iOS/Android), configure audio session so playback works
      await _ensureAudioSession();

      final isCurrentRecording = _currentlyPlayingId == recording.id;

      if (_isPlaying && isCurrentRecording) {
        AppLogger.info('Pausing current recording');
        await _audioPlayer.pause();
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
        });
      } else if (!_isPlaying && isCurrentRecording) {
        AppLogger.info(
          'Resuming paused recording from position: $_audioPosition',
        );
        await _audioPlayer.play();
        if (!mounted) return;
        setState(() => _isPlaying = true);
      } else {
        if (_isPlaying && _currentlyPlayingId != null) {
          AppLogger.info('Stopping previous recording');
          await _audioPlayer.stop();
          if (!mounted) return;
          setState(() {
            _isPlaying = false;
            _currentlyPlayingId = null;
            _audioPosition = Duration.zero;
          });
        }

        // Load the new recording
        if (recording.filePath.startsWith('assets/')) {
          // just_audio setAsset expects path WITHOUT 'assets/' prefix
          final assetPath = recording.filePath.replaceFirst('assets/', '');
          AppLogger.info('Loading asset: $assetPath');
          await _audioPlayer.setAsset(assetPath);
        } else if (recording.filePath.startsWith('http') ||
            recording.filePath.startsWith('data:')) {
          AppLogger.info('Loading URL');
          await _audioPlayer.setUrl(recording.filePath);
        } else if (!kIsWeb) {
          AppLogger.info('Loading file path: ${recording.filePath}');
          await _audioPlayer.setFilePath(recording.filePath);
        } else {
          throw UnsupportedError(
            'File path playback is not supported on web. Use assets or URLs.',
          );
        }

        if (!mounted) return;
        setState(() {
          _currentlyPlayingId = recording.id;
          _isPlaying = true;
        });
        await _audioPlayer.play();
        AppLogger.info('Playback started successfully');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error playing recording: ${e.toString()}', e);
      AppLogger.error('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _currentlyPlayingId = null;
        _isPlaying = false;
      });
      final message = e.toString().contains('Unable to load asset') ||
              e.toString().contains('NotFound')
          ? 'Audio file not found. Please ensure the app has the audio assets.'
          : 'Unable to play audio. ${e.toString().split('\n').first}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _deleteRecording(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording'),
        content: const Text('Are you sure you want to delete this recording?'),
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
      if (!mounted) return;
      final provider = Provider.of<CallRecordingsProvider>(
        context,
        listen: false,
      );
      await provider.deleteRecording(id);
      if (!mounted) return;
      if (_selectedRecording?.id == id) {
        setState(() {
          _selectedRecording = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        leading: _selectedRecording != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedRecording = null;
                  });
                },
              )
            : null,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics),
            SizedBox(width: 8),
            Text('Customer Call Insights'),
          ],
        ),
        actions: [
          if (_selectedRecording != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectedRecording = null;
                });
              },
              tooltip: 'Back to List',
            ),
          IconButton(
            icon: Icon(
              _showAggregateDashboard ? Icons.phone_in_talk : Icons.dashboard,
            ),
            onPressed: () {
              setState(() {
                _showAggregateDashboard = !_showAggregateDashboard;
                if (_showAggregateDashboard) {
                  _selectedRecording = null;
                }
              });
            },
            tooltip: _showAggregateDashboard
                ? 'View Single Call'
                : 'View Dashboard',
          ),
        ],
        bottom: _selectedRecording != null
            ? TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(icon: Icon(Icons.chat), text: 'Transcript'),
                  Tab(icon: Icon(Icons.analytics), text: 'Dashboard'),
                  Tab(icon: Icon(Icons.dashboard), text: 'Call Insights'),
                  Tab(icon: Icon(Icons.info), text: 'Summary'),
                ],
              )
            : null,
      ),
      body: SafeArea(
        child: Consumer<CallRecordingsProvider>(
          builder: (context, provider, _) {
            if (_showAggregateDashboard) {
              return ComprehensiveCallDashboard(showAggregateMetrics: true);
            }

            if (provider.recordings.isEmpty && _selectedRecording == null) {
              return _buildEmptyState();
            }

            if (_selectedRecording == null) {
              return _buildRecordingGallery(provider);
            }

          // Always get fresh data from provider when building TabBarView
          final currentRecording = _selectedRecording != null
              ? provider.getRecordingWithData(_selectedRecording!.id)
              : null;

          if (currentRecording == null) {
            return _buildRecordingGallery(provider);
          }

            return TabBarView(
              key: ValueKey(currentRecording.id),
              controller: _tabController,
              children: [
                _buildTranscriptView(currentRecording),
                _buildComprehensiveDashboard(currentRecording),
                _buildInsightsView(currentRecording),
                _buildSummaryView(currentRecording),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.phone_in_talk, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Call Recordings',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Loading recordings...',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingGallery(CallRecordingsProvider provider) {
    return Column(
      children: [
        // Removed loader banner - loaders only show in the card buttons
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            itemCount: provider.recordings.length,
            itemBuilder: (context, index) {
              final recording = provider.recordings[index];
              // Get full recording with data from memory
              final fullRecording = provider.getRecordingWithData(recording.id);
              if (fullRecording == null) {
                return const SizedBox.shrink();
              }
              final isCurrentlyPlaying =
                  _isPlaying && _currentlyPlayingId == recording.id;
              final isLoaded =
                  _currentlyPlayingId ==
                  recording.id; // Loaded (playing or paused)
              return RecordingGalleryItem(
                recording: fullRecording,
                isPlaying: isCurrentlyPlaying,
                isAnalyzing: _isTranscribing || _isAnalyzing
                    ? _analyzingRecordingId == recording.id
                    : false,
                currentPosition: isLoaded ? _audioPosition : null,
                totalDuration: isLoaded && _audioDuration.inMilliseconds > 0
                    ? _audioDuration
                    : fullRecording.duration,
                onSeek: isLoaded ? _seekAudio : null,
                onTap: () {
                  // Select recording to view details
                  _selectRecording(fullRecording);
                },
                onAnalyze: () async {
                  // If already analyzed, show details directly without re-analyzing
                  if (fullRecording.analysis != null) {
                    // Show details/view analysis
                    _selectRecording(fullRecording);
                    return;
                  }
                  // If not analyzed, proceed with analysis
                  await _analyzeRecording(
                    fullRecording,
                    shouldNavigate: true,
                    forceReAnalyze: false,
                  );
                },
                onPlay: () => _playRecording(fullRecording),
                onDelete: () => _deleteRecording(recording.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTranscriptView([CallRecording? recording]) {
    final currentRecording = recording ?? _selectedRecording;
    if (currentRecording == null) return const SizedBox();

    if (currentRecording.transcript == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isTranscribing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Transcribing audio...'),
            ] else ...[
              const Icon(Icons.transcribe, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No transcript available'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _transcribeRecording(currentRecording),
                child: const Text('Transcribe Recording'),
              ),
            ],
          ],
        ),
      );
    }

    final messages = _analysisService.parseTranscript(
      currentRecording.transcript!,
    );

    return Column(
      children: [
        // Action buttons
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Show analyze button if not analyzed or re-analyze if already analyzed
              ElevatedButton.icon(
                onPressed: _isAnalyzing
                    ? null
                    : () => _analyzeRecording(
                        currentRecording,
                        shouldNavigate: true,
                        forceReAnalyze: currentRecording.analysis != null,
                      ),
                icon: _isAnalyzing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.analytics),
                label: Text(
                  _isAnalyzing
                      ? 'Analyzing...'
                      : currentRecording.analysis != null
                      ? 'Re-analyze Call'
                      : 'Analyze Call',
                ),
              ),
              // Show view insights button if analysis is complete
              if (currentRecording.analysis != null &&
                  _hasCompleteAnalysisData(currentRecording.analysis!))
                ElevatedButton.icon(
                  onPressed: () {
                    _tabController.animateTo(1);
                  },
                  icon: const Icon(Icons.dashboard),
                  label: const Text('View Insights'),
                ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return TranscriptChatBubble(message: messages[index]);
                  },
                ),
              ),
              // AI Disclaimer
              const AIDisclaimer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsightsView([CallRecording? recording]) {
    final currentRecording = recording ?? _selectedRecording;
    if (currentRecording == null || currentRecording.analysis == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dashboard, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No analysis available'),
            const SizedBox(height: 8),
            const Text(
              'Transcribe and analyze the call to view insights',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: currentRecording != null
                  ? () => _analyzeRecording(
                      currentRecording,
                      shouldNavigate: false,
                      forceReAnalyze: false,
                    )
                  : null,
              icon: const Icon(Icons.analytics),
              label: const Text('Analyze Now'),
            ),
          ],
        ),
      );
    }

    // Validate analysis data completeness
    if (!_hasCompleteAnalysisData(currentRecording.analysis!)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, size: 64, color: Colors.orange.shade400),
            const SizedBox(height: 16),
            const Text(
              'Analysis data incomplete',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Some required data is missing. Please re-analyze the call.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _analyzeRecording(
                currentRecording,
                shouldNavigate: false,
                forceReAnalyze: true,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Re-analyze Call'),
            ),
          ],
        ),
      );
    }

    return CallInsightsDashboard(analysis: currentRecording.analysis!);
  }

  Widget _buildComprehensiveDashboard([CallRecording? recording]) {
    final currentRecording = recording ?? _selectedRecording;
    if (currentRecording == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.analytics, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No recording selected'),
            const SizedBox(height: 8),
            const Text(
              'Select a recording to view comprehensive analytics',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Show loader if no analysis
    if (currentRecording.analysis == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Analyzing dashboard data...',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait while we generate analytics',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // Validate analysis data completeness
    if (!_hasCompleteAnalysisData(currentRecording.analysis!)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, size: 64, color: Colors.orange.shade400),
            const SizedBox(height: 16),
            const Text(
              'Analysis data incomplete',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Some required data is missing. Please re-analyze the call.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _analyzeRecording(
                currentRecording,
                shouldNavigate: false,
                forceReAnalyze: true,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Re-analyze Call'),
            ),
          ],
        ),
      );
    }

    return ComprehensiveCallDashboard(
      singleCallAnalysis: currentRecording.analysis,
    );
  }

  Widget _buildSummaryView([CallRecording? recording]) {
    final currentRecording = recording ?? _selectedRecording;
    if (currentRecording == null) return const SizedBox();

    final analysis = currentRecording.analysis;
    if (analysis == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Generating summary...',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait while we analyze the call',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // Validate analysis data completeness
    if (!_hasCompleteAnalysisData(analysis)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, size: 64, color: Colors.orange.shade400),
            const SizedBox(height: 16),
            const Text(
              'Analysis data incomplete',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Some required data is missing. Please re-analyze the call.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _analyzeRecording(
                currentRecording,
                shouldNavigate: false,
                forceReAnalyze: true,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Re-analyze Call'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sentiment Score
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sentiment Score',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _getSentimentColor(
                            analysis.sentimentScore.overall,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _getSentimentColor(
                              analysis.sentimentScore.overall,
                            ),
                          ),
                        ),
                        child: Text(
                          analysis.sentimentScore.overall,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getSentimentColor(
                              analysis.sentimentScore.overall,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${(analysis.sentimentScore.score * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Key Highlights
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Key Highlights',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildHighlightItem('Issue', analysis.keyHighlights.issue),
                  const SizedBox(height: 12),
                  // _buildHighlightItem(
                  //   'Resolution',
                  //   analysis.keyHighlights.resolution,
                  // ),
                  //const SizedBox(height: 12),
                  _buildHighlightItem(
                    'Summary',
                    analysis.keyHighlights.summary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Agent Score
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Agent Performance',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${analysis.agentScore.rating}/10',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text('Overall Rating'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Professionalism:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(analysis.agentScore.professionalism),
                            const SizedBox(height: 8),
                            Text(
                              'Efficiency:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(analysis.agentScore.efficiency),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Call Metrics
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Call Metrics',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  // const SizedBox(height: 16),
                  // Row(
                  //   children: [
                  //     Expanded(
                  //       child: _buildMetricItem(
                  //         'Agent Talk Time',
                  //         '${analysis.agentTalkSeconds.toStringAsFixed(0)}s',
                  //         Icons.mic,
                  //         Colors.blue,
                  //       ),
                  //     ),
                  //     Expanded(
                  //       child: _buildMetricItem(
                  //         'Customer Talk Time',
                  //         '${analysis.customerTalkSeconds.toStringAsFixed(0)}s',
                  //         Icons.person,
                  //         Colors.green,
                  //       ),
                  //     ),
                  //     Expanded(
                  //       child: _buildMetricItem(
                  //         'Total Duration',
                  //         '${(analysis.agentTalkSeconds + analysis.customerTalkSeconds).toStringAsFixed(0)}s',
                  //         Icons.timer,
                  //         Colors.purple,
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (analysis.detectedLanguage != null)
                        Expanded(
                          child: _buildMetricItem(
                            'Detected Language',
                            analysis.detectedLanguage!,
                            Icons.language,
                            Colors.orange,
                          ),
                        ),
                      if (analysis.detectedLanguage != null)
                        const SizedBox(width: 12),
                      if (analysis.firstCallResolution != null)
                        Expanded(
                          child: _buildMetricItem(
                            'First Call Resolution',
                            analysis.firstCallResolution == true ? 'Yes' : 'No',
                            analysis.firstCallResolution == true
                                ? Icons.check_circle
                                : Icons.cancel,
                            analysis.firstCallResolution == true
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      if (analysis.topics.isNotEmpty) ...[
                        if (analysis.detectedLanguage != null ||
                            analysis.firstCallResolution != null)
                          const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricItem(
                            'Topics Identified',
                            '${analysis.topics.length}',
                            Icons.category,
                            Colors.teal,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Topics Summary
          if (analysis.topics.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Topics Mentioned',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: analysis.topics.map((topic) {
                        return Chip(
                          label: Text(
                            '${topic.category} (${topic.count})',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.blue.shade50,
                          side: BorderSide(color: Colors.blue.shade200),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Agent Performance Details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Agent Performance Breakdown',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${analysis.agentPerformance.greeting.toStringAsFixed(1)}/10',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _getPerformanceColor(
                                  analysis.agentPerformance.greeting,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Greeting',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${analysis.agentPerformance.problemSolving.toStringAsFixed(1)}/10',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _getPerformanceColor(
                                  analysis.agentPerformance.problemSolving,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Problem Solving',
                              style: TextStyle(fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${analysis.agentPerformance.closing.toStringAsFixed(1)}/10',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _getPerformanceColor(
                                  analysis.agentPerformance.closing,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Closing',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // AI Disclaimer
          const AIDisclaimer(),
        ],
      ),
    );
  }

  Widget _buildHighlightItem(String label, String value) {
    // Ensure value is not empty or just default text
    final displayValue =
        value.isEmpty ||
            value == 'Issue identified in call' ||
            value == 'Resolution discussed' ||
            value == 'Call summary' ||
            value == 'Analysis unavailable' ||
            value == 'Unable to extract resolution' ||
            value == 'Call analysis could not be completed. Please try again.'
        ? 'No specific information available for this section.'
        : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(
            displayValue,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getSentimentColor(String sentiment) {
    switch (sentiment.toLowerCase()) {
      case 'positive':
        return Colors.green;
      case 'negative':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Color _getPerformanceColor(double score) {
    if (score >= 8) return Colors.green;
    if (score >= 6) return Colors.orange;
    return Colors.red;
  }
}
