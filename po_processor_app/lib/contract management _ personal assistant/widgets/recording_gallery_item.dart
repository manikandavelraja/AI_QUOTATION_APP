import 'package:flutter/material.dart';
import '../models/call_recording.dart';

class RecordingGalleryItem extends StatelessWidget {
  final CallRecording recording;
  final VoidCallback? onTap;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback? onAnalyze;
  final bool isPlaying;
  final bool isAnalyzing;
  final Duration? currentPosition;
  final Duration? totalDuration;
  final ValueChanged<Duration>? onSeek;

  const RecordingGalleryItem({
    super.key,
    required this.recording,
    this.onTap,
    required this.onPlay,
    required this.onDelete,
    this.onAnalyze,
    this.isPlaying = false,
    this.isAnalyzing = false,
    this.currentPosition,
    this.totalDuration,
    this.onSeek,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Play button
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.indigo.shade700,
                ),
                onPressed: onPlay,
                iconSize: 32,
              ),
              const SizedBox(width: 12),
              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recording.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (recording.analysis != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.green.shade300,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Already Analyzed',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Progress slider (show when loaded - playing or paused)
                    if (currentPosition != null && totalDuration != null && totalDuration!.inMilliseconds > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            _formatDuration(currentPosition!),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.indigo.shade700,
                                inactiveTrackColor: Colors.grey.shade300,
                                thumbColor: Colors.indigo.shade700,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                trackHeight: 3,
                                disabledThumbColor: Colors.indigo.shade700,
                                disabledActiveTrackColor: Colors.indigo.shade700,
                                disabledInactiveTrackColor: Colors.grey.shade300,
                              ),
                              child: Slider(
                                value: currentPosition!.inMilliseconds.toDouble().clamp(
                                  0.0,
                                  totalDuration!.inMilliseconds.toDouble(),
                                ),
                                max: totalDuration!.inMilliseconds.toDouble(),
                                onChanged: onSeek != null
                                    ? (value) {
                                        onSeek!(Duration(milliseconds: value.toInt()));
                                      }
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(totalDuration!),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Analyze/View Details button
              if (onAnalyze != null)
                IconButton(
                  icon: isAnalyzing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          recording.analysis != null
                              ? Icons.visibility
                              : Icons.analytics,
                        ),
                  color: recording.analysis != null
                      ? Colors.green.shade700
                      : Colors.indigo.shade700,
                  onPressed: isAnalyzing ? null : onAnalyze,
                  tooltip: recording.analysis != null
                      ? 'View Details'
                      : 'Analyze',
                ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: Colors.red,
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ),
      ),
    );
  }
}

