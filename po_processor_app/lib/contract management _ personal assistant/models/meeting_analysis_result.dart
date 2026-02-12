class MeetingAnalysisResult {
  final String summary;
  final String detailedTranscription;
  final List<String> importantPoints;
  final List<String> popularWords;
  final double confidenceScore;
  final String audioPath;
  final DateTime timestamp;

  MeetingAnalysisResult({
    required this.summary,
    required this.detailedTranscription,
    required this.importantPoints,
    required this.popularWords,
    required this.confidenceScore,
    required this.audioPath,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'summary': summary,
      'detailedTranscription': detailedTranscription,
      'importantPoints': importantPoints,
      'popularWords': popularWords,
      'confidenceScore': confidenceScore,
      'audioPath': audioPath,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MeetingAnalysisResult.fromJson(Map<String, dynamic> json) {
    return MeetingAnalysisResult(
      summary: json['summary'] ?? '',
      detailedTranscription: json['detailedTranscription'] ?? '',
      importantPoints: List<String>.from(json['importantPoints'] ?? []),
      popularWords: List<String>.from(json['popularWords'] ?? []),
      confidenceScore: (json['confidenceScore'] ?? 0.0).toDouble(),
      audioPath: json['audioPath'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

